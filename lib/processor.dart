import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:ffmpeg_kit_flutter_new_full/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new_full/ffprobe_kit.dart';
import 'package:ffmpeg_kit_flutter_new_full/return_code.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'models.dart';

class JobCancelled implements Exception {}

String frameFilter(VideoMetadata m, Settings s, int width, int height) {
  final factor = s.effectiveCrop
      ? math.max(width / m.width, height / m.height)
      : math.min(width / m.width, height / m.height);
  int dimension(double n) =>
      math.max(2, s.effectiveCrop ? (n / 2).ceil() * 2 : (n / 2).floor() * 2);
  final scaledWidth = dimension(m.width * factor),
      scaledHeight = dimension(m.height * factor);
  final fit = s.effectiveCrop
      ? 'crop=$width:$height:(iw-ow)/2:(ih-oh)/2'
      : 'pad=$width:$height:(ow-iw)/2:(oh-ih)/2:color=${s.dark ? '0x111827' : '0xf4f5f7'}';
  return 'scale=$scaledWidth:$scaledHeight,setsar=1,$fit';
}

/// Sequential native sessions bound memory use and allow cancellation between steps.
class MosaicProcessor {
  bool _cancelled = false;
  int? _sessionId;
  bool? _zscale;
  void begin() {
    _cancelled = false;
  }

  void checkCancelled() {
    if (_cancelled) throw JobCancelled();
  }

  Future<void> cancel() async {
    _cancelled = true;
    final id = _sessionId;
    if (id != null) await FFmpegKit.cancel(id);
  }

  Future<String> run(List<String> args) async {
    checkCancelled();
    final finished = Completer<void>();
    final session = await FFmpegKit.executeWithArgumentsAsync(
      [
        '-hide_banner',
        '-loglevel',
        'error',
        '-y',
        '-threads',
        '2',
        '-filter_threads',
        '1',
        '-filter_complex_threads',
        '1',
        ...args,
      ],
      (session) async {
        try {
          final code = await session.getReturnCode();
          if (_cancelled || ReturnCode.isCancel(code)) {
            finished.completeError(JobCancelled());
          } else if (!ReturnCode.isSuccess(code)) {
            final logs = await session.getOutput() ?? '영상 처리 실패';
            finished.completeError(
              Exception(
                logs.length > 1600 ? logs.substring(logs.length - 1600) : logs,
              ),
            );
          } else {
            finished.complete();
          }
        } catch (e, st) {
          if (!finished.isCompleted) finished.completeError(e, st);
        }
      },
    );
    _sessionId = session.getSessionId();
    // Attach the error handler before awaiting a cancellation request.
    final completion = finished.future;
    if (_cancelled) unawaited(FFmpegKit.cancel(_sessionId));
    try {
      await completion;
      checkCancelled();
      return await session.getOutput() ?? '';
    } finally {
      _sessionId = null;
    }
  }

  Future<VideoMetadata> probe(String path) async {
    checkCancelled();
    final session = await FFprobeKit.executeWithArguments([
      '-v',
      'quiet',
      '-show_format',
      '-show_streams',
      '-of',
      'json',
      path,
    ]);
    checkCancelled();
    if (!ReturnCode.isSuccess(await session.getReturnCode())) {
      throw Exception('동영상 정보를 읽지 못했습니다. 파일 형식을 확인하세요.');
    }
    final raw = await session.getOutput() ?? '{}';
    final json = jsonDecode(raw) as Map<String, dynamic>;
    final streams = (json['streams'] as List? ?? []).whereType<Map>();
    final video = streams
        .where(
          (s) =>
              s['codec_type'] == 'video' &&
              (s['disposition']?['attached_pic'] ?? 0) != 1,
        )
        .firstOrNull;
    if (video != null) {
      final side = (video['side_data_list'] as List? ?? []).whereType<Map>();
      if (!side.any((data) => data['rotation'] != null) &&
          video['tags']?['rotate'] == null) {
        int? rotation;
        try {
          rotation = await const MethodChannel(
            'mosaic/media',
          ).invokeMethod<int>('rotation', {'path': path});
        } on PlatformException {
          /* Some containers are unsupported by Android. */
        } on MissingPluginException {
          /* Non-Android test hosts can use FFmpeg. */
        }
        if (rotation != null) {
          json['mosaic_android_rotation'] = rotation;
        } else {
          // FFprobeKit can omit side_data_list. Measure one decoded frame
          // after FFmpeg autorotation instead of assuming encoded dimensions.
          final logs = await run([
            '-loglevel',
            'info',
            '-i',
            path,
            '-map',
            '0:${video['index'] ?? 0}',
            '-frames:v',
            '1',
            '-vf',
            'showinfo',
            '-an',
            '-f',
            'null',
            '-',
          ]);
          final match = RegExp(
            r'sar:(\d+)/(\d+)\s+s:(\d+)x(\d+)',
          ).firstMatch(logs);
          if (match != null) {
            final sar =
                int.parse(match[1]!) / math.max(1, int.parse(match[2]!));
            json['mosaic_display_width'] = (int.parse(match[3]!) * sar).round();
            json['mosaic_display_height'] = int.parse(match[4]!);
          }
        }
      }
    }
    checkCancelled();
    return parseVideoMetadata(json);
  }

  Future<String> createThumbnail(String source, VideoMetadata m) async {
    checkCancelled();
    final dir = await Directory(
      p.join((await getTemporaryDirectory()).path, 'mosaic_thumbnails'),
    ).create(recursive: true);
    final output = p.join(
      dir.path,
      '${DateTime.now().microsecondsSinceEpoch}.jpg',
    );
    final factor = math.min(1.0, math.min(256 / m.width, 384 / m.height));
    final width = math.max(2, (m.width * factor).floor() ~/ 2 * 2);
    final height = math.max(2, (m.height * factor).floor() ~/ 2 * 2);
    final time = math.min(
      m.duration * .1,
      math.max(0.0, m.duration - m.frameSeconds),
    );
    try {
      final tone = await _tone(m);
      await run([
        '-ss',
        time.toStringAsFixed(6),
        '-i',
        source,
        '-map',
        '0:${m.streamIndex}',
        '-an',
        '-frames:v',
        '1',
        '-vf',
        '$tone${frameFilter(m, Settings(), width, height)}',
        '-q:v',
        '5',
        output,
      ]);
      if (!await File(output).exists()) {
        throw const FormatException('미리보기 프레임을 추출하지 못했습니다.');
      }
      return output;
    } catch (_) {
      final file = File(output);
      if (await file.exists()) await file.delete();
      rethrow;
    }
  }

  Future<void> clearQueueCache(QueueItem item) async {
    final cache = (await getTemporaryDirectory()).path;
    for (final path in [item.thumbnailPath, item.path]) {
      if (path != null &&
          (p.isWithin(p.join(cache, 'mosaic_thumbnails'), path) ||
              p.isWithin(p.join(cache, 'mosaic_imports'), path))) {
        final file = File(path);
        if (await file.exists()) await file.delete();
      }
    }
  }

  Future<String> _tone(VideoMetadata m) async {
    if (m.dolbyVision) {
      throw Exception(
        'Dolby Vision은 이 모바일 버전에서 정확한 색상을 보장할 수 없어 제외했습니다. SDR 영상으로 변환 후 선택하세요.',
      );
    }
    if (!m.hdr) return '';
    if (_zscale == null) {
      final session = await FFmpegKit.executeWithArguments([
        '-hide_banner',
        '-filters',
      ]);
      _zscale = (await session.getOutput() ?? '').contains('zscale');
    }
    checkCancelled();
    if (!_zscale!) {
      throw Exception('이 FFmpeg 빌드에는 HDR 색상 변환 기능이 없습니다. SDR 영상을 사용하세요.');
    }
    return 'zscale=t=linear:npl=100,format=gbrpf32le,zscale=p=bt709,tonemap=tonemap=hable:desat=0,zscale=t=bt709:m=bt709:r=tv,';
  }

  Future<List<GeneratedFile>> generate(
    QueueItem item,
    Settings s,
    void Function(double, String) progress,
    void Function(GeneratedFile) onResult,
  ) async {
    final m = item.metadata ??= await probe(item.path);
    final tone = await _tone(m);
    final root = await getApplicationDocumentsDirectory();
    final results = await Directory(
      p.join(root.path, 'results'),
    ).create(recursive: true);
    final temp = await Directory(
      p.join((await getTemporaryDirectory()).path, 'mosaic'),
    ).create(recursive: true);
    final work = await temp.createTemp('job_');
    final outputs = <GeneratedFile>[];
    try {
      var completedKinds = 0;
      for (final kind in s.outputs) {
        checkCancelled();
        final dir = await Directory(p.join(work.path, kind.name)).create();
        final local = <String>[];
        final animated =
            kind == OutputKind.reel || kind == OutputKind.animatedSheet;
        final samples = SamplePlan.create(s, m, kind);
        final count = samples.count;
        final clip = samples.clip;
        final times = samples.times;
        final layout = SheetLayout.create(s, m, kind, count);
        final cellWidth = layout.cellWidth, cellHeight = layout.cellHeight;
        for (var i = 0; i < count; i++) {
          checkCancelled();
          progress(
            (completedKinds + i / (count + 1)) / s.outputs.length,
            '${kind.label} · ${i + 1}/$count',
          );
          final path = p.join(
            dir.path,
            '${i.toString().padLeft(3, '0')}.${animated ? 'mkv' : 'png'}',
          );
          await run([
            '-ss',
            times[i].toStringAsFixed(6),
            '-i',
            item.path,
            '-map',
            '0:${m.streamIndex}',
            '-an',
            '-sn',
            '-dn',
            if (animated) ...['-t', clip.toStringAsFixed(6)],
            '-vf',
            '$tone${frameFilter(m, s, cellWidth, cellHeight)}${animated ? ',fps=${s.fps},setpts=PTS-STARTPTS' : ''}',
            if (animated) ...[
              '-c:v',
              'ffv1',
              '-pix_fmt',
              'yuv420p',
            ] else ...[
              '-frames:v',
              '1',
            ],
            path,
          ]);
          local.add(path);
        }
        if (kind == OutputKind.screenshots) {
          for (var i = 0; i < local.length; i++) {
            final png = p.join(dir.path, 'shot_$i.png');
            await _compose(
              [local[i]],
              png,
              item,
              s,
              cellWidth,
              cellHeight,
              [times[i]],
              single: true,
              layout: layout,
            );
            final encoded = await _encodeStill(png, dir.path, 'encoded_$i', s);
            final output = await _commit(
              encoded,
              results,
              item.name,
              '${s.suffix.isEmpty ? '_screens' : s.suffix}_${(i + 1).toString().padLeft(2, '0')}',
              kind,
            );
            outputs.add(output);
            onResult(output);
          }
        } else if (kind == OutputKind.sheet) {
          final png = p.join(dir.path, 'sheet.png');
          await _compose(
            local,
            png,
            item,
            s,
            cellWidth,
            cellHeight,
            times,
            layout: layout,
          );
          final output = await _commit(
            await _encodeStill(png, dir.path, 'sheet', s),
            results,
            item.name,
            s.suffix.isEmpty ? '_sheet' : s.suffix,
            kind,
          );
          outputs.add(output);
          onResult(output);
        } else {
          final ext = kind == OutputKind.animatedSheet
              ? 'webp'
              : s.animationFormat;
          final output = p.join(dir.path, 'animation.$ext');
          final grid = kind == OutputKind.animatedSheet;
          final args = <String>[];
          if (grid) {
            final merged = await _mergeGrid(local, dir, layout, clip, s.dark);
            args.addAll(['-i', merged]);
          } else {
            // Only generated basenames enter concat syntax.
            final list = File(p.join(dir.path, 'clips.txt'));
            await list.writeAsString(
              local.map((path) => "file '${p.basename(path)}'").join('\n'),
            );
            args.addAll(['-f', 'concat', '-safe', '1', '-i', list.path]);
          }
          final overlay = p.join(dir.path, 'overlay.png');
          await _compose(
            [],
            overlay,
            item,
            s,
            cellWidth,
            cellHeight,
            times,
            single: !grid,
            transparent: true,
            labels: grid,
            layout: layout,
          );
          args.addAll(['-i', overlay]);
          args.addAll([
            '-filter_complex',
            '[0:v][1:v]overlay=0:0:format=auto,format=yuv420p[out]',
            '-map',
            '[out]',
            '-an',
            '-t',
            (grid ? clip : clip * count).toStringAsFixed(6),
          ]);
          args.addAll([
            '-colorspace',
            'bt709',
            '-color_primaries',
            'bt709',
            '-color_trc',
            'bt709',
          ]);
          args.addAll(switch (ext) {
            'webp' => [
              '-c:v',
              'libwebp_anim',
              '-quality',
              '${s.webpQuality}',
              '-loop',
              '0',
            ],
            'webm' => [
              '-c:v',
              'libvpx-vp9',
              '-crf',
              '35',
              '-b:v',
              '0',
              '-cpu-used',
              '5',
            ],
            _ => ['-loop', '0'],
          });
          args.add(output);
          progress(
            (completedKinds + .95) / s.outputs.length,
            '${kind.label} 인코딩 중',
          );
          await run(args);
          final result = await _commit(
            output,
            results,
            item.name,
            s.suffix.isEmpty
                ? (grid ? '_animated_sheet' : '_preview')
                : s.suffix,
            kind,
          );
          outputs.add(result);
          onResult(result);
        }
        completedKinds++;
      }
      progress(1, '완료');
      return outputs;
    } finally {
      await work.delete(recursive: true);
    }
  }

  /// Compose at most ten streams at a time instead of opening every grid cell.
  Future<String> _mergeGrid(
    List<String> clips,
    Directory dir,
    SheetLayout layout,
    double clip,
    bool dark,
  ) async {
    final bg = dark ? '0x111827' : '0xf4f5f7';
    final rows = <String>[];
    for (var row = 0; row < layout.rows; row++) {
      checkCancelled();
      final start = row * layout.columns;
      final inputs = clips.sublist(
        start,
        math.min(start + layout.columns, clips.length),
      );
      final args = <String>[];
      for (final input in inputs) {
        args.addAll(['-threads', '1', '-i', input]);
      }
      final parts = <String>[];
      for (var i = 0; i < inputs.length; i++) {
        parts.add(
          '[$i:v]pad=${layout.cellWidth + (i + 1 < inputs.length ? layout.gap : 0)}:${layout.cellHeight}:0:0:color=$bg[c$i]',
        );
      }
      final labels = List.generate(inputs.length, (i) => '[c$i]').join();
      final stack = inputs.length > 1
          ? '${labels}hstack=inputs=${inputs.length}'
          : '${labels}null';
      final out = p.join(dir.path, 'row_$row.mkv');
      parts.add(
        '$stack,pad=${layout.gridWidth}:${layout.cellHeight}:0:0:color=$bg[out]',
      );
      await run([
        ...args,
        '-filter_complex',
        parts.join(';'),
        '-map',
        '[out]',
        '-t',
        '$clip',
        '-an',
        '-c:v',
        'ffv1',
        '-threads',
        '2',
        '-pix_fmt',
        'yuv420p',
        out,
      ]);
      rows.add(out);
    }
    final args = <String>[];
    for (final row in rows) {
      args.addAll(['-threads', '1', '-i', row]);
    }
    final parts = <String>[];
    for (var i = 0; i < rows.length; i++) {
      parts.add(
        '[$i:v]pad=${layout.gridWidth}:${layout.cellHeight + (i + 1 < rows.length ? layout.gap : 0)}:0:0:color=$bg[r$i]',
      );
    }
    final labels = List.generate(rows.length, (i) => '[r$i]').join();
    final stack = rows.length > 1
        ? '${labels}vstack=inputs=${rows.length}'
        : '${labels}null';
    parts.add(
      '$stack,pad=${layout.width}:${layout.height}:${layout.left}:${layout.top}:color=$bg[out]',
    );
    final out = p.join(dir.path, 'grid.mkv');
    await run([
      ...args,
      '-filter_complex',
      parts.join(';'),
      '-map',
      '[out]',
      '-t',
      '$clip',
      '-an',
      '-c:v',
      'ffv1',
      '-threads',
      '2',
      '-pix_fmt',
      'yuv420p',
      out,
    ]);
    return out;
  }

  Future<String> _encodeStill(
    String png,
    String dir,
    String name,
    Settings s,
  ) async {
    if (s.imageFormat == 'png') return png;
    final jpg = p.join(dir, '$name.jpg');
    await run([
      '-i',
      png,
      '-frames:v',
      '1',
      '-q:v',
      '${(31 - s.jpegQuality * .29).round().clamp(2, 31)}',
      jpg,
    ]);
    return jpg;
  }

  Future<GeneratedFile> _commit(
    String source,
    Directory dir,
    String name,
    String suffix,
    OutputKind kind,
  ) async {
    checkCancelled();
    final base = p
        .basenameWithoutExtension(name)
        .replaceAll(RegExp(r'[<>:"/\\|?*\x00-\x1F]'), '_');
    var path = p.join(dir.path, '$base$suffix${p.extension(source)}');
    var i = 1;
    while (await File(path).exists()) {
      path = p.join(dir.path, '$base$suffix (${i++})${p.extension(source)}');
    }
    await File(source).rename(path);
    return GeneratedFile(path, kind);
  }

  Future<void> _compose(
    List<String> images,
    String output,
    QueueItem item,
    Settings s,
    int cw,
    int ch,
    List<double> times, {
    bool single = false,
    bool transparent = false,
    bool labels = true,
    required SheetLayout layout,
  }) async {
    checkCancelled();
    final cols = layout.columns;
    final gap = layout.gap, header = layout.header;
    final w = layout.width, h = layout.height;
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    final fg = s.dark ? Colors.white : const Color(0xff111827);
    if (!transparent) {
      canvas.drawColor(
        s.dark ? const Color(0xff111827) : const Color(0xfff4f5f7),
        BlendMode.src,
      );
    }
    void text(
      String value,
      double x,
      double y,
      double size,
      double maxWidth, {
      bool badge = false,
    }) {
      final painter = TextPainter(
        text: TextSpan(
          text: value,
          style: TextStyle(color: badge ? Colors.white : fg, fontSize: size),
        ),
        textDirection: TextDirection.ltr,
        maxLines: 1,
        ellipsis: '…',
      )..layout(maxWidth: maxWidth);
      if (badge) {
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTWH(x - 3, y - 2, painter.width + 6, painter.height + 4),
            const Radius.circular(3),
          ),
          Paint()..color = const Color(0xb3000000),
        );
      }
      painter.paint(canvas, Offset(x, y));
    }

    if (header > 0) {
      text(item.name, gap + 8.0, 10, 22, w - gap * 2 - 16.0);
      final m = item.metadata!;
      text(
        '${m.width} × ${m.height}  •  ${timestamp(m.duration)}  •  ${m.codec.toUpperCase()}${m.hdr ? '  •  HDR → SDR' : ''}',
        gap + 8.0,
        47,
        17,
        w - gap * 2 - 16.0,
      );
    }
    for (var i = 0; i < times.length; i++) {
      checkCancelled();
      final x = (layout.left + i % cols * (cw + gap)).toDouble(),
          y = (layout.top + i ~/ cols * (ch + gap)).toDouble();
      if (i < images.length) {
        final codec = await ui.instantiateImageCodec(
          await File(images[i]).readAsBytes(),
        );
        final image = (await codec.getNextFrame()).image;
        canvas.drawImageRect(
          image,
          Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
          Rect.fromLTWH(x, y, cw.toDouble(), ch.toDouble()),
          Paint(),
        );
        image.dispose();
        codec.dispose();
      }
      if (s.timestamps && labels && i < times.length) {
        text(
          timestamp(times[i]),
          x + 8,
          y + ch - math.min(24.0, cw / 10) - 8,
          math.min(22.0, cw / 11),
          cw - 16.0,
          badge: true,
        );
      }
    }
    final picture = recorder.endRecording();
    final image = await picture.toImage(w, h);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    await File(output).writeAsBytes(bytes!.buffer.asUint8List(), flush: true);
    image.dispose();
    picture.dispose();
  }
}

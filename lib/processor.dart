import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:ffmpeg_kit_flutter_new_full/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new_full/ffprobe_kit.dart';
import 'package:ffmpeg_kit_flutter_new_full/return_code.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'models.dart';

class JobCancelled implements Exception {}

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

  Future<void> run(List<String> args) async {
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
    final j = jsonDecode(raw) as Map<String, dynamic>;
    final streams = (j['streams'] as List).cast<Map<String, dynamic>>();
    final videos = streams.where(
      (s) =>
          s['codec_type'] == 'video' &&
          (s['disposition']?['attached_pic'] ?? 0) != 1,
    );
    if (videos.isEmpty) throw Exception('영상 트랙이 없는 파일입니다.');
    final v = videos.first;
    final duration =
        double.tryParse('${j['format']?['duration'] ?? v['duration']}') ?? 0;
    if (!duration.isFinite || duration <= 0) {
      throw Exception('길이를 확인할 수 없는 영상은 지원하지 않습니다.');
    }
    double width = (v['width'] as num?)?.toDouble() ?? 0;
    double height = (v['height'] as num?)?.toDouble() ?? 0;
    final sar = '${v['sample_aspect_ratio'] ?? '1:1'}'.split(':');
    if (sar.length == 2) {
      final a = double.tryParse(sar[0]) ?? 1, b = double.tryParse(sar[1]) ?? 1;
      if (a > 0 && b > 0) width *= a / b;
    }
    final side = (v['side_data_list'] as List? ?? []).whereType<Map>();
    final rotation =
        side.where((s) => s['rotation'] != null).firstOrNull?['rotation'] ??
        v['tags']?['rotate'] ??
        0;
    if ((double.tryParse('$rotation') ?? 0).abs() % 180 == 90) {
      final t = width;
      width = height;
      height = t;
    }
    if (width <= 0 || height <= 0) throw Exception('영상 크기가 올바르지 않습니다.');
    return VideoMetadata(
      duration,
      width.round(),
      height.round(),
      '${v['codec_name'] ?? 'unknown'}',
      '${v['color_transfer'] ?? ''}',
      const JsonEncoder.withIndent('  ').convert(j),
      streamIndex: (v['index'] as num?)?.toInt() ?? 0,
      dolbyVision: side.any(
        (s) => '${s['side_data_type']}'.toLowerCase().contains('dovi'),
      ),
    );
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
        if (kind == OutputKind.animatedSheet && s.columns * s.rows > 9) {
          throw Exception('움직이는 썸네일 모음은 메모리 사용을 줄이기 위해 최대 9칸입니다. 행·열을 줄여 주세요.');
        }
        final count =
            kind == OutputKind.sheet || kind == OutputKind.animatedSheet
            ? s.columns * s.rows
            : s.count;
        final clip = math.min(s.clipSeconds, m.duration);
        final times = sampleTimes(m.duration, count, clip: animated ? clip : 0);
        final cellWidth =
            kind == OutputKind.sheet || kind == OutputKind.animatedSheet
            ? ((s.width - s.gap * (s.columns + 1)) ~/ s.columns) ~/ 2 * 2
            : math.min(s.width, m.width) ~/ 2 * 2;
        final cellHeight = math.max(
          2,
          (cellWidth * m.height / m.width).round() ~/ 2 * 2,
        );
        if (cellWidth < 16 ||
            cellHeight > 4096 ||
            (cellHeight * s.rows + 120) * s.width > 16000000) {
          throw Exception('출력 이미지가 너무 큽니다. 너비나 행 수를 줄여 주세요.');
        }
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
            '${tone}scale=$cellWidth:$cellHeight,setsar=1${animated ? ',fps=${s.fps},setpts=PTS-STARTPTS' : ''}',
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
          await _compose(local, png, item, s, cellWidth, cellHeight, times);
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
          final args = <String>[];
          if (kind == OutputKind.reel) {
            // Generated basenames only: source names never enter concat syntax.
            final list = File(p.join(dir.path, 'clips.txt'));
            await list.writeAsString(
              List.generate(
                local.length,
                (i) => "file '${p.basename(local[i])}'",
              ).join('\n'),
            );
            args.addAll(['-f', 'concat', '-safe', '1', '-i', list.path]);
          } else {
            for (final path in local) {
              args.addAll(['-i', path]);
            }
          }
          final grid = kind == OutputKind.animatedSheet;
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
          );
          args.addAll(['-i', overlay]);
          final header = grid && s.header ? 88 : 0;
          final bg = s.dark ? '0x111827' : '0xf4f5f7';
          String graph;
          if (grid && count > 1) {
            final cells = List.generate(
              count,
              (i) =>
                  '[$i:v]pad=${cellWidth + s.gap}:${cellHeight + s.gap}:0:0:color=$bg[c$i]',
            ).join(';');
            final layout = List.generate(
              count,
              (i) =>
                  '${i % s.columns * (cellWidth + s.gap)}_${i ~/ s.columns * (cellHeight + s.gap)}',
            ).join('|');
            graph =
                '$cells;${List.generate(count, (i) => '[c$i]').join()}xstack=inputs=$count:layout=$layout:fill=$bg, pad=${cellWidth * s.columns + s.gap * (s.columns + 1)}:${cellHeight * s.rows + s.gap * (s.rows + 1) + header}:${s.gap}:${s.gap + header}:color=$bg[base]';
          } else if (grid) {
            graph =
                '[0:v]pad=${cellWidth + s.gap * 2}:${cellHeight + s.gap * 2 + header}:${s.gap}:${s.gap + header}:color=$bg[base]';
          } else {
            graph = '[0:v]null[base]';
          }
          graph +=
              ';[base][${grid ? count : 1}:v]overlay=0:0:format=auto,format=yuv420p[out]';
          args.addAll([
            '-filter_complex',
            graph,
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
              '${s.quality}',
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
      '${(31 - s.quality * .29).round().clamp(2, 31)}',
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
  }) async {
    checkCancelled();
    final cols = single ? 1 : s.columns, rows = single ? 1 : s.rows;
    final gap = single ? 0 : s.gap;
    final header = !single && s.header ? 88 : 0;
    final w = cw * cols + gap * (cols + 1),
        h = ch * rows + gap * (rows + 1) + header;
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
    for (var i = 0; i < cols * rows; i++) {
      checkCancelled();
      final x = (gap + i % cols * (cw + gap)).toDouble(),
          y = (header + gap + i ~/ cols * (ch + gap)).toDouble();
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

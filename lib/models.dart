import 'dart:math' as math;
import 'dart:convert';

enum OutputKind { sheet, screenshots, reel, animatedSheet }

extension OutputLabel on OutputKind {
  String get label =>
      const ['썸네일 모음', '개별 스크린샷', '움직이는 미리보기', '움직이는 썸네일 모음'][index];
}

class Settings {
  int columns = 3,
      rows = 4,
      width = 1280,
      gap = 8,
      fps = 8,
      jpegQuality = 85,
      webpQuality = 85,
      screenshotCount = 6,
      reelCount = 6,
      gridCount = 12;
  bool autoArrange = false;
  int get gridCapacity => autoArrange ? gridCount : columns * rows;
  OutputKind get previewKind => outputs.contains(OutputKind.sheet)
      ? OutputKind.sheet
      : outputs.contains(OutputKind.animatedSheet)
      ? OutputKind.animatedSheet
      : outputs.contains(OutputKind.screenshots)
      ? OutputKind.screenshots
      : outputs.contains(OutputKind.reel)
      ? OutputKind.reel
      : OutputKind.sheet;
  int get count => screenshotCount;
  set count(int value) {
    screenshotCount = value;
    reelCount = value;
  }

  int get quality => webpQuality;
  set quality(int value) {
    jpegQuality = value;
    webpQuality = value;
  }

  bool get gridEnabled =>
      outputs.contains(OutputKind.sheet) ||
      outputs.contains(OutputKind.animatedSheet);
  bool get stillEnabled =>
      outputs.contains(OutputKind.sheet) ||
      outputs.contains(OutputKind.screenshots);
  bool get animationEnabled =>
      outputs.contains(OutputKind.reel) ||
      outputs.contains(OutputKind.animatedSheet);
  bool get timestampEnabled =>
      stillEnabled || outputs.contains(OutputKind.animatedSheet);
  bool get webpQualityEnabled =>
      outputs.contains(OutputKind.animatedSheet) ||
      (outputs.contains(OutputKind.reel) && animationFormat == 'webp');
  bool get effectiveCrop =>
      crop && thumbnailAspect != 'source' && thumbnailAspect != 'auto';
  double clipSeconds = 2;
  double sampleInterval = 2;
  bool adaptiveCount = true, crop = false;
  bool fitSheetWidth = true;
  String thumbnailAspect = 'source', sheetAspect = 'auto';
  bool timestamps = true, header = true, dark = true;
  String imageFormat = 'jpg', animationFormat = 'webp', suffix = '';
  Set<OutputKind> outputs = {OutputKind.sheet};

  Map<String, dynamic> toJson() => {
    'columns': columns,
    'rows': rows,
    'width': width,
    'gap': gap,
    'screenshotCount': screenshotCount,
    'reelCount': reelCount,
    'gridCount': gridCount,
    'autoArrange': autoArrange,
    'fps': fps,
    'jpegQuality': jpegQuality,
    'webpQuality': webpQuality,
    'clipSeconds': clipSeconds,
    'sampleInterval': sampleInterval,
    'adaptiveCount': adaptiveCount,
    'crop': crop,
    'fitSheetWidth': fitSheetWidth,
    'thumbnailAspect': thumbnailAspect,
    'sheetAspect': sheetAspect,
    'timestamps': timestamps,
    'header': header,
    'dark': dark,
    'imageFormat': imageFormat,
    'animationFormat': animationFormat,
    'suffix': suffix,
    'outputs': outputs.map((e) => e.name).toList(),
  };

  factory Settings.fromJson(Map<String, dynamic> j) {
    final s = Settings();
    int number(String key, int fallback, int min, int max) =>
        ((j[key] as num?)?.toInt() ?? fallback).clamp(min, max);
    s.columns = number('columns', 3, 1, 10);
    s.rows = number('rows', 4, 1, 10);
    s.width = number('width', 1280, 320, 1920);
    s.gap = number('gap', 8, 0, 24);
    final oldCount = number('count', 6, 1, 100);
    s.screenshotCount = number('screenshotCount', oldCount, 1, 100);
    s.reelCount = number('reelCount', oldCount, 1, 100);
    s.gridCount = number('gridCount', s.columns * s.rows, 1, 100);
    s.autoArrange = j['autoArrange'] as bool? ?? false;
    s.fps = number('fps', 8, 4, 15);
    final oldQuality = number('quality', 85, 40, 100);
    s.jpegQuality = number('jpegQuality', oldQuality, 40, 100);
    s.webpQuality = number('webpQuality', oldQuality, 40, 100);
    s.clipSeconds = ((j['clipSeconds'] as num?)?.toDouble() ?? 2).clamp(.5, 5);
    s.sampleInterval = ((j['sampleInterval'] as num?)?.toDouble() ?? 2).clamp(
      .5,
      10,
    );
    s.adaptiveCount = j['adaptiveCount'] as bool? ?? true;
    s.crop = j['crop'] as bool? ?? false;
    s.fitSheetWidth = j['fitSheetWidth'] as bool? ?? true;
    s.thumbnailAspect = aspectValues.contains(j['thumbnailAspect'])
        ? j['thumbnailAspect'] as String
        : 'source';
    s.sheetAspect = aspectValues.contains(j['sheetAspect'])
        ? j['sheetAspect'] as String
        : 'auto';
    s.timestamps = j['timestamps'] as bool? ?? true;
    s.header = j['header'] as bool? ?? true;
    s.dark = j['dark'] as bool? ?? true;
    s.imageFormat = j['imageFormat'] == 'png' ? 'png' : 'jpg';
    s.animationFormat = ['webp', 'gif', 'webm'].contains(j['animationFormat'])
        ? j['animationFormat'] as String
        : 'webp';
    final suffix = (j['suffix'] as String? ?? '').replaceAll(
      RegExp(r'[^a-zA-Z0-9_\-]'),
      '',
    );
    s.suffix = suffix.substring(0, math.min(32, suffix.length));
    final selected = (j['outputs'] as List?)?.whereType<String>().toSet();
    if (selected != null) {
      s.outputs = OutputKind.values
          .where((e) => selected.contains(e.name))
          .toSet();
    }
    return s;
  }

  Settings();
}

const aspectValues = ['source', 'auto', '16:9', '9:16', '4:3', '3:4', '1:1'];
double? aspectRatio(String value) {
  final pair = value.split(':');
  if (pair.length != 2) return null;
  return double.parse(pair.first) / double.parse(pair.last);
}

/// Count means an upper bound in adaptive mode, rather than mandatory repeats.
class SamplePlan {
  final List<double> times;
  final double clip;
  final int requested;
  int get count => times.length;
  const SamplePlan(this.times, this.clip, this.requested);
  factory SamplePlan.create(Settings s, VideoMetadata m, OutputKind kind) {
    final grid = kind == OutputKind.sheet || kind == OutputKind.animatedSheet;
    final animated =
        kind == OutputKind.reel || kind == OutputKind.animatedSheet;
    final requested =
        (grid
                ? s.gridCapacity
                : kind == OutputKind.screenshots
                ? s.screenshotCount
                : s.reelCount)
            .clamp(1, 100);
    final clip = animated ? math.min(s.clipSeconds, m.duration) : 0.0;
    var count = requested;
    if (s.adaptiveCount) {
      final spacing = math.max(s.sampleInterval, clip);
      count = math.min(count, math.max(1, (m.duration / spacing).floor()));
    }
    if (animated && m.duration - clip < .001) count = 1;
    if (!animated) {
      count = math.min(
        count,
        math.max(1, (m.duration / m.frameSeconds).round()),
      );
    }
    final times = animated
        ? List.generate(
            count,
            (i) => count == 1
                ? (m.duration - clip) / 2
                : (m.duration - clip) * i / (count - 1),
          )
        : sampleTimes(m.duration, count)
              .map(
                (t) => math.min(t, math.max(0.0, m.duration - m.frameSeconds)),
              )
              .toList();
    return SamplePlan(times, clip, requested);
  }
}

int bestColumns(
  int count,
  double cellAspect,
  double canvasAspect, {
  int maximum = 10,
  bool exact = false,
}) {
  var best = 1;
  var score = double.infinity;
  for (var columns = 1; columns <= math.min(count, maximum); columns++) {
    if (exact && count % columns != 0) continue;
    final rows = (count / columns).ceil();
    if (rows > 10) continue;
    final candidate =
        (math.log(columns * cellAspect / rows / canvasAspect)).abs() +
        (columns * rows - count) / count * .3;
    if (candidate < score) {
      best = columns;
      score = candidate;
    }
  }
  return best;
}

/// Shared by UI preview, still rendering and native animation composition.
class SheetLayout {
  final int columns,
      rows,
      cellWidth,
      cellHeight,
      width,
      height,
      left,
      top,
      gap,
      header;
  const SheetLayout(
    this.columns,
    this.rows,
    this.cellWidth,
    this.cellHeight,
    this.width,
    this.height,
    this.left,
    this.top,
    this.gap,
    this.header,
  );
  int get gridWidth => columns * cellWidth + (columns - 1) * gap;
  int get gridHeight => rows * cellHeight + (rows - 1) * gap;
  factory SheetLayout.create(
    Settings s,
    VideoMetadata m,
    OutputKind kind,
    int count,
  ) {
    final grid = kind == OutputKind.sheet || kind == OutputKind.animatedSheet;
    final ratio = aspectRatio(s.thumbnailAspect) ?? m.width / m.height;
    final canvasRatio = grid && !s.fitSheetWidth
        ? aspectRatio(s.sheetAspect)
        : null;
    var cols = grid ? math.min(s.columns, count) : 1;
    if (grid && s.autoArrange) {
      cols = bestColumns(count, ratio, canvasRatio ?? ratio, maximum: 10);
    }
    final rows = grid ? (count / cols).ceil() : 1;
    final gap = grid ? s.gap ~/ 2 * 2 : 0;
    final header = grid && s.header ? 88 : 0;
    final outer = grid && !s.fitSheetWidth ? gap : 0;
    var wantedWidth = grid ? s.width : math.min(s.width, m.width);
    final budget = kind == OutputKind.animatedSheet ? 8000000 : 16000000;
    for (var attempt = 0; attempt < 20; attempt++) {
      var width = wantedWidth ~/ 2 * 2;
      var cw = (width - gap * (cols - 1) - 2 * outer) ~/ cols ~/ 2 * 2;
      var ch = math.max(2, (cw / ratio).round() ~/ 2 * 2);
      int height;
      if (canvasRatio != null) {
        height = (width / canvasRatio).round() ~/ 2 * 2;
        final maxCh = (height - header - gap * (rows + 1)) ~/ rows ~/ 2 * 2;
        if (ch > maxCh) {
          ch = maxCh;
          cw = (ch * ratio).round() ~/ 2 * 2;
        }
      } else {
        width = cw * cols + gap * (cols - 1) + 2 * outer;
        height = ch * rows + gap * (rows - 1) + 2 * outer + header;
      }
      if (cw < 16 || ch < 16 || height <= header) {
        throw const FormatException(
          '선택한 비율에 비해 칸이 너무 많습니다. 행·열을 줄이거나 출력 너비를 늘려 주세요.',
        );
      }
      if (width * height <= budget && height <= 8192) {
        final gw = cw * cols + gap * (cols - 1),
            gh = ch * rows + gap * (rows - 1);
        final left = (width - gw) ~/ 4 * 2;
        final top = header + (height - header - gh) ~/ 4 * 2;
        return SheetLayout(
          cols,
          rows,
          cw,
          ch,
          width,
          height,
          left,
          top,
          gap,
          header,
        );
      }
      wantedWidth =
          (wantedWidth *
                  math.min(
                    math.sqrt(budget / (width * height)),
                    8192 / height,
                  ) *
                  .95)
              .floor();
    }
    throw const FormatException('출력 크기를 계산하지 못했습니다. 행·열을 줄여 주세요.');
  }
}

/// Normalize rotation and sample aspect ratio before choosing output dimensions.
VideoMetadata parseVideoMetadata(Map<String, dynamic> j) {
  final streams = (j['streams'] as List? ?? []).cast<Map<String, dynamic>>();
  final videos = streams.where(
    (s) =>
        s['codec_type'] == 'video' &&
        (s['disposition']?['attached_pic'] ?? 0) != 1,
  );
  if (videos.isEmpty) throw const FormatException('영상 트랙이 없는 파일입니다.');
  final v = videos.first;
  final videoDuration = double.tryParse('${v['duration']}') ?? 0;
  final duration = videoDuration > 0
      ? videoDuration
      : double.tryParse('${j['format']?['duration']}') ?? 0;
  if (!duration.isFinite || duration <= 0) {
    throw const FormatException('길이를 확인할 수 없는 영상은 지원하지 않습니다.');
  }
  var width = (v['width'] as num?)?.toDouble() ?? 0;
  var height = (v['height'] as num?)?.toDouble() ?? 0;
  final sar = '${v['sample_aspect_ratio'] ?? '1:1'}'.split(':');
  if (sar.length == 2) {
    final a = double.tryParse(sar[0]) ?? 1, b = double.tryParse(sar[1]) ?? 1;
    if (a > 0 && b > 0) width *= a / b;
  }
  final side = (v['side_data_list'] as List? ?? []).whereType<Map>();
  final rotation =
      side.where((s) => s['rotation'] != null).firstOrNull?['rotation'] ??
      v['tags']?['rotate'] ??
      j['mosaic_android_rotation'] ??
      0;
  if ((double.tryParse('$rotation') ?? 0).round().abs() % 180 == 90) {
    final swap = width;
    width = height;
    height = swap;
  }
  if (j['mosaic_display_width'] is num && j['mosaic_display_height'] is num) {
    width = (j['mosaic_display_width'] as num).toDouble();
    height = (j['mosaic_display_height'] as num).toDouble();
  }
  if (width <= 0 || height <= 0) {
    throw const FormatException('영상 크기가 올바르지 않습니다.');
  }
  final frameRate = '${v['avg_frame_rate'] ?? v['r_frame_rate'] ?? '0/1'}'
      .split('/');
  final fps = frameRate.length == 2
      ? (double.tryParse(frameRate[0]) ?? 0) /
            (double.tryParse(frameRate[1]) ?? 1)
      : double.tryParse(frameRate.first) ?? 0;
  return VideoMetadata(
    duration,
    width.round(),
    height.round(),
    '${v['codec_name'] ?? 'unknown'}',
    '${v['color_transfer'] ?? ''}',
    const JsonEncoder.withIndent('  ').convert(j),
    streamIndex: (v['index'] as num?)?.toInt() ?? 0,
    frameSeconds: fps.isFinite && fps > 0 ? 1 / fps : 1 / 30,
    dolbyVision: side.any(
      (s) => '${s['side_data_type']}'.toLowerCase().contains('dovi'),
    ),
  );
}

List<double> sampleTimes(double duration, int count, {double clip = 0}) {
  if (!duration.isFinite || duration <= 0 || count < 1) return [];
  final span = math.max(0.0, duration - clip);
  return List.generate(count, (i) => span * (i + 1) / (count + 1));
}

String timestamp(double seconds) {
  final n = seconds.floor();
  return '${(n ~/ 3600).toString().padLeft(2, '0')}:${(n ~/ 60 % 60).toString().padLeft(2, '0')}:${(n % 60).toString().padLeft(2, '0')}';
}

class VideoMetadata {
  final double duration;
  final int width, height;
  final String codec, transfer, raw;
  final bool dolbyVision;
  final int streamIndex;
  final double frameSeconds;
  const VideoMetadata(
    this.duration,
    this.width,
    this.height,
    this.codec,
    this.transfer,
    this.raw, {
    this.dolbyVision = false,
    this.streamIndex = 0,
    this.frameSeconds = 1 / 30,
  });
  bool get hdr => transfer == 'smpte2084' || transfer == 'arib-std-b67';
}

class QueueItem {
  final String path, name;
  final String? sourceId;
  String status = '대기 중';
  VideoMetadata? metadata;
  String? thumbnailPath;
  bool thumbnailLoading = false;
  QueueItem(this.path, this.name, {this.sourceId});
}

class GeneratedFile {
  final String path;
  final OutputKind kind;
  GeneratedFile(this.path, this.kind);
}

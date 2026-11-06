import 'dart:math' as math;

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
      count = 6,
      fps = 8,
      quality = 85;
  double clipSeconds = 2;
  bool timestamps = true, header = true, dark = true;
  String imageFormat = 'jpg', animationFormat = 'webp', suffix = '';
  Set<OutputKind> outputs = {OutputKind.sheet};

  Map<String, dynamic> toJson() => {
    'columns': columns,
    'rows': rows,
    'width': width,
    'gap': gap,
    'count': count,
    'fps': fps,
    'quality': quality,
    'clipSeconds': clipSeconds,
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
    s.columns = number('columns', 3, 1, 6);
    s.rows = number('rows', 4, 1, 6);
    s.width = number('width', 1280, 320, 1920);
    s.gap = number('gap', 8, 0, 24);
    s.count = number('count', 6, 1, 24);
    s.fps = number('fps', 8, 4, 15);
    s.quality = number('quality', 85, 40, 100);
    s.clipSeconds = ((j['clipSeconds'] as num?)?.toDouble() ?? 2).clamp(.5, 5);
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
  const VideoMetadata(
    this.duration,
    this.width,
    this.height,
    this.codec,
    this.transfer,
    this.raw, {
    this.dolbyVision = false,
    this.streamIndex = 0,
  });
  bool get hdr => transfer == 'smpte2084' || transfer == 'arib-std-b67';
}

class QueueItem {
  final String path, name;
  String status = '대기 중';
  VideoMetadata? metadata;
  QueueItem(this.path, this.name);
}

class GeneratedFile {
  final String path;
  final OutputKind kind;
  GeneratedFile(this.path, this.kind);
}

import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'models.dart';
import 'settings_group.dart';

class LayoutControls extends StatelessWidget {
  final Settings settings;
  final VideoMetadata? metadata;
  final VoidCallback onChanged;
  const LayoutControls({
    super.key,
    required this.settings,
    required this.metadata,
    required this.onChanged,
  });
  void change(VoidCallback action) {
    action();
    onChanged();
  }

  VideoMetadata get source =>
      metadata ?? const VideoMetadata(60, 1920, 1080, '', '', '');
  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final enabled = settings.outputs.isNotEmpty;
    final kind = settings.previewKind;
    final sample = SamplePlan.create(settings, source, kind);
    SheetLayout? layout;
    String? error;
    try {
      layout = SheetLayout.create(settings, source, kind, sample.count);
    } on FormatException catch (e) {
      error = e.message;
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Card(
          color: colors.primaryContainer,
          elevation: 0,
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '미리보기 · ${kind.label}',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 14),
                if (layout != null)
                  Center(
                    child: SizedBox(
                      height: 210,
                      child: AspectRatio(
                        aspectRatio: layout.width / layout.height,
                        child: CustomPaint(
                          painter: LayoutPreviewPainter(
                            layout,
                            kind == OutputKind.screenshots ||
                                    kind == OutputKind.reel
                                ? 1
                                : sample.count,
                            source.width / source.height,
                            settings.effectiveCrop,
                            settings.dark,
                          ),
                        ),
                      ),
                    ),
                  ),
                if (error != null)
                  Text(error, style: TextStyle(color: colors.error)),
                const SizedBox(height: 12),
                if (layout != null)
                  Text(
                    '${sample.count}개 · ${layout.columns}열 × ${layout.rows}행 · ${layout.width} × ${layout.height}px',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                const SizedBox(height: 4),
                Text(
                  metadata == null
                      ? '예시 16:9 · 1분 기준. 영상을 선택하면 실제 결과를 미리 볼 수 있어요.'
                      : '원본 ${source.width} × ${source.height} · ${timestamp(source.duration)}${sample.count < sample.requested ? '\n최대 ${sample.requested}개 중 실제 ${sample.count}개 생성' : ''}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                if (layout != null && layout.width < settings.width - 20)
                  const Text(
                    '메모리 한도에 맞춰 출력 해상도를 줄였습니다.',
                    style: TextStyle(fontSize: 12),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        SettingsGroup(
          title: '1. 개별 장면 비율',
          description: '선택된 모든 출력에 적용',
          enabled: enabled,
          disabledReason: '동영상 화면에서 생성할 결과를 선택하세요.',
          children: [
            _aspects(
              settings.thumbnailAspect,
              false,
              (v) => change(() => settings.thumbnailAspect = v),
            ),
            const SizedBox(height: 12),
            SegmentedButton<bool>(
              segments: const [
                ButtonSegment(
                  value: false,
                  label: Text('전체 보이기'),
                  icon: Icon(Icons.fit_screen),
                ),
                ButtonSegment(
                  value: true,
                  label: Text('잘라서 채우기'),
                  icon: Icon(Icons.crop),
                ),
              ],
              selected: {settings.crop},
              onSelectionChanged: settings.thumbnailAspect == 'source'
                  ? null
                  : (v) => change(() => settings.crop = v.single),
            ),
            const SizedBox(height: 8),
            Text(
              settings.thumbnailAspect == 'source'
                  ? '원본 비율에서는 자르기 설정을 사용하지 않습니다. 이전 선택은 보관됩니다.'
                  : settings.effectiveCrop
                  ? '가장자리를 잘라 채웁니다. 영상을 늘리지는 않습니다.'
                  : '전체 영상이 보이도록 필요한 여백을 넣습니다.',
              style: const TextStyle(fontSize: 12),
            ),
          ],
        ),
        SettingsGroup(
          title: '2. 모음 캔버스',
          description: '썸네일 모음 · 움직이는 모음 전용',
          enabled: settings.gridEnabled,
          disabledReason: '모음 출력을 선택하면 사용할 수 있습니다.',
          children: [
            SegmentedButton<bool>(
              segments: const [
                ButtonSegment(
                  value: true,
                  label: Text('너비에 맞춤'),
                  icon: Icon(Icons.width_normal),
                ),
                ButtonSegment(
                  value: false,
                  label: Text('고정 비율'),
                  icon: Icon(Icons.aspect_ratio),
                ),
              ],
              selected: {settings.fitSheetWidth},
              onSelectionChanged: (v) =>
                  change(() => settings.fitSheetWidth = v.single),
            ),
            const SizedBox(height: 12),
            _aspects(
              settings.sheetAspect,
              true,
              (v) => change(() => settings.sheetAspect = v),
              enabled: !settings.fitSheetWidth,
            ),
            const SizedBox(height: 8),
            Text(
              settings.fitSheetWidth
                  ? '너비에 맞춤 사용 중: 바깥 검정 여백 없이 채웁니다. 고정 비율 값은 비활성 상태로 보관됩니다.'
                  : '고정 비율 사용 중: 전체 이미지 비율을 유지하므로 여백이 생길 수 있습니다.',
              style: const TextStyle(fontSize: 12),
            ),
          ],
        ),
        SettingsGroup(
          title: '3. 모음 배치',
          description: '자동 개수 배치 또는 직접 행·열 중 하나만 사용',
          enabled: settings.gridEnabled,
          disabledReason: '모음 출력을 선택하면 사용할 수 있습니다.',
          children: [
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('자동 배치'),
              subtitle: const Text('켜면 최대 개수로 배치하고, 끄면 직접 지정한 행·열을 사용합니다.'),
              value: settings.autoArrange,
              onChanged: (v) => change(() => settings.autoArrange = v),
            ),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                for (final n in [4, 9, 12, 16, 20, 24, 36, 48, 64, 100])
                  ChoiceChip(
                    label: Text('$n개'),
                    selected: settings.gridCount == n,
                    onSelected: settings.autoArrange
                        ? (_) => change(() => settings.gridCount = n)
                        : null,
                  ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              settings.autoArrange
                  ? '직접 행·열은 비활성입니다. 보관된 값을 덮어쓰지 않습니다.'
                  : '최대 ${settings.columns * settings.rows}개 · 자동 개수 프리셋은 비활성입니다.',
              style: const TextStyle(fontSize: 12),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: _stepper(
                    context,
                    '열',
                    settings.columns,
                    (n) => change(() => settings.columns = n),
                    enabled: !settings.autoArrange,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _stepper(
                    context,
                    '행',
                    settings.rows,
                    (n) => change(() => settings.rows = n),
                    enabled: !settings.autoArrange,
                  ),
                ),
              ],
            ),
          ],
        ),
      ],
    );
  }

  Widget _aspects(
    String value,
    bool canvas,
    ValueChanged<String> onChanged, {
    bool enabled = true,
  }) => Wrap(
    spacing: 8,
    runSpacing: 6,
    children: [
      for (final ratio in [
        canvas ? 'auto' : 'source',
        '16:9',
        '9:16',
        '4:3',
        '3:4',
        '1:1',
      ])
        ChoiceChip(
          label: Text(
            ratio == 'source'
                ? '원본'
                : ratio == 'auto'
                ? '자동'
                : ratio,
          ),
          selected: value == ratio,
          onSelected: enabled ? (_) => onChanged(ratio) : null,
        ),
    ],
  );
  Widget _stepper(
    BuildContext context,
    String label,
    int value,
    ValueChanged<int> onChanged, {
    required bool enabled,
  }) => Container(
    decoration: BoxDecoration(
      border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
      borderRadius: BorderRadius.circular(16),
    ),
    child: Column(
      children: [
        const SizedBox(height: 8),
        Text(label),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            IconButton(
              tooltip: '$label 줄이기',
              onPressed: enabled && value > 1
                  ? () => onChanged(value - 1)
                  : null,
              icon: const Icon(Icons.remove),
            ),
            Text('$value', style: Theme.of(context).textTheme.titleLarge),
            IconButton(
              tooltip: '$label 늘리기',
              onPressed: enabled && value < 10
                  ? () => onChanged(value + 1)
                  : null,
              icon: const Icon(Icons.add),
            ),
          ],
        ),
      ],
    ),
  );
}

class LayoutPreviewPainter extends CustomPainter {
  final SheetLayout layout;
  final int count;
  final double sourceAspect;
  final bool crop, dark;
  const LayoutPreviewPainter(
    this.layout,
    this.count,
    this.sourceAspect,
    this.crop,
    this.dark,
  );
  @override
  void paint(Canvas canvas, Size size) {
    final scale = math.min(
      size.width / layout.width,
      size.height / layout.height,
    );
    canvas.translate(
      (size.width - layout.width * scale) / 2,
      (size.height - layout.height * scale) / 2,
    );
    canvas.scale(scale);
    canvas.drawRect(
      Rect.fromLTWH(0, 0, layout.width.toDouble(), layout.height.toDouble()),
      Paint()..color = dark ? const Color(0xff111827) : const Color(0xfff8fafc),
    );
    if (layout.header > 0) {
      for (var i = 0; i < 2; i++) {
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTWH(
              16,
              18.0 + i * 26,
              layout.width * (i == 0 ? .5 : .7),
              10,
            ),
            const Radius.circular(5),
          ),
          Paint()..color = Colors.grey.shade500,
        );
      }
    }
    for (var i = 0; i < count; i++) {
      final cell = Rect.fromLTWH(
        (layout.left + i % layout.columns * (layout.cellWidth + layout.gap))
            .toDouble(),
        (layout.top + i ~/ layout.columns * (layout.cellHeight + layout.gap))
            .toDouble(),
        layout.cellWidth.toDouble(),
        layout.cellHeight.toDouble(),
      );
      canvas.drawRect(
        cell,
        Paint()..color = dark ? Colors.black : Colors.grey.shade300,
      );
      var content = cell;
      if (!crop) {
        final w = math.min(cell.width, cell.height * sourceAspect),
            h = math.min(cell.height, cell.width / sourceAspect);
        content = Rect.fromCenter(center: cell.center, width: w, height: h);
      }
      canvas.drawRect(
        content,
        Paint()
          ..shader = LinearGradient(
            colors: [
              Color.lerp(
                const Color(0xff14b8a6),
                const Color(0xff818cf8),
                i / math.max(1, count - 1),
              )!,
              const Color(0xff164e63),
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ).createShader(content),
      );
      final painter = TextPainter(
        text: TextSpan(
          text: '${i + 1}',
          style: TextStyle(
            color: Colors.white,
            fontSize: math.min(content.height * .3, content.width * .25),
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      painter.paint(
        canvas,
        content.center - Offset(painter.width / 2, painter.height / 2),
      );
    }
  }

  @override
  bool shouldRepaint(covariant LayoutPreviewPainter oldDelegate) => true;
}

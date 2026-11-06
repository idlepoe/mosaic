import 'l10n/app_language.dart';
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
      metadata ?? VideoMetadata(60, 1920, 1080, '', '', '');
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
            padding: EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  tr('preview', [kind.label]),
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                SizedBox(height: 14),
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
                SizedBox(height: 12),
                if (layout != null)
                  Text(
                    tr('framesColumnsRowsPx', [
                      sample.count,
                      layout.columns,
                      layout.rows,
                      layout.width,
                      layout.height,
                    ]),
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                SizedBox(height: 4),
                Text(
                  metadata == null
                      ? tr('exampleMinuteSelectAVideoTo')
                      : tr('source', [
                          source.width,
                          source.height,
                          timestamp(source.duration),
                          sample.count < sample.requested
                              ? tr('generatingOfUpToFrames', [
                                  sample.requested,
                                  sample.count,
                                ])
                              : '',
                        ]),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                if (layout != null && layout.width < settings.width - 20)
                  Text(
                    tr('outputResolutionWasReducedToFit'),
                    style: TextStyle(fontSize: 12),
                  ),
              ],
            ),
          ),
        ),
        SizedBox(height: 16),
        SettingsGroup(
          title: tr('frameAspectRatio'),
          description: tr('appliesToAllSelectedOutputs'),
          enabled: enabled,
          disabledReason: tr('selectAnOutputOnTheVideos'),
          children: [
            _aspects(
              settings.thumbnailAspect,
              false,
              (v) => change(() => settings.thumbnailAspect = v),
            ),
            SizedBox(height: 12),
            SegmentedButton<bool>(
              segments: [
                ButtonSegment(
                  value: false,
                  label: Text(tr('fitEntireFrame')),
                  icon: Icon(Icons.fit_screen),
                ),
                ButtonSegment(
                  value: true,
                  label: Text(tr('cropToFill')),
                  icon: Icon(Icons.crop),
                ),
              ],
              selected: {settings.crop},
              onSelectionChanged: settings.thumbnailAspect == 'source'
                  ? null
                  : (v) => change(() => settings.crop = v.single),
            ),
            SizedBox(height: 8),
            Text(
              settings.thumbnailAspect == 'source'
                  ? tr('croppingIsInactiveAtTheSource')
                  : settings.effectiveCrop
                  ? tr('cropsTheEdgesToFillThe')
                  : tr('addsPaddingAsNeededToShow'),
              style: TextStyle(fontSize: 12),
            ),
          ],
        ),
        SettingsGroup(
          title: tr('sheetCanvas'),
          description: tr('contactSheetsAndAnimatedSheetsOnly'),
          enabled: settings.gridEnabled,
          disabledReason: tr('availableWhenASheetOutputIs'),
          children: [
            SegmentedButton<bool>(
              segments: [
                ButtonSegment(
                  value: true,
                  label: Text(tr('fitToContent')),
                  icon: Icon(Icons.width_normal),
                ),
                ButtonSegment(
                  value: false,
                  label: Text(tr('fixedAspectRatio')),
                  icon: Icon(Icons.aspect_ratio),
                ),
              ],
              selected: {settings.fitSheetWidth},
              onSelectionChanged: (v) =>
                  change(() => settings.fitSheetWidth = v.single),
            ),
            SizedBox(height: 12),
            _aspects(
              settings.sheetAspect,
              true,
              (v) => change(() => settings.sheetAspect = v),
              enabled: !settings.fitSheetWidth,
            ),
            SizedBox(height: 8),
            Text(
              settings.fitSheetWidth
                  ? tr('fitToContentFillsTheWidth')
                  : tr('fixedRatioPreservesTheOverallImage'),
              style: TextStyle(fontSize: 12),
            ),
          ],
        ),
        SettingsGroup(
          title: tr('sheetArrangement'),
          description: tr('chooseAutomaticArrangementOrManualRows'),
          enabled: settings.gridEnabled,
          disabledReason: tr('availableWhenASheetOutputIs'),
          children: [
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(tr('automaticArrangement')),
              subtitle: Text(tr('whenEnabledArrangesByMaximumCount')),
              value: settings.autoArrange,
              onChanged: (v) => change(() => settings.autoArrange = v),
            ),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                for (final n in [4, 9, 12, 16, 20, 24, 36, 48, 64, 100])
                  ChoiceChip(
                    label: Text(tr('frames', [n])),
                    selected: settings.gridCount == n,
                    onSelected: settings.autoArrange
                        ? (_) => change(() => settings.gridCount = n)
                        : null,
                  ),
              ],
            ),
            SizedBox(height: 12),
            Text(
              settings.autoArrange
                  ? tr('manualRowsAndColumnsAreInactive')
                  : tr('upToFramesAutomaticCountPresets', [
                      settings.columns * settings.rows,
                    ]),
              style: TextStyle(fontSize: 12),
            ),
            SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: _stepper(
                    context,
                    tr('columns'),
                    settings.columns,
                    (n) => change(() => settings.columns = n),
                    enabled: !settings.autoArrange,
                  ),
                ),
                SizedBox(width: 12),
                Expanded(
                  child: _stepper(
                    context,
                    tr('rows'),
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
                ? tr('sourceLabel')
                : ratio == 'auto'
                ? tr('auto')
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
        SizedBox(height: 8),
        Text(label),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            IconButton(
              tooltip: tr('decrease', [label]),
              onPressed: enabled && value > 1
                  ? () => onChanged(value - 1)
                  : null,
              icon: Icon(Icons.remove),
            ),
            Text('$value', style: Theme.of(context).textTheme.titleLarge),
            IconButton(
              tooltip: tr('increase', [label]),
              onPressed: enabled && value < 10
                  ? () => onChanged(value + 1)
                  : null,
              icon: Icon(Icons.add),
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
      Paint()..color = dark ? Color(0xff111827) : Color(0xfff8fafc),
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
            Radius.circular(5),
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
                Color(0xff14b8a6),
                Color(0xff818cf8),
                i / math.max(1, count - 1),
              )!,
              Color(0xff164e63),
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

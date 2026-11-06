import 'package:shadcn_ui/shadcn_ui.dart';
import 'ui/studio_theme.dart';
import 'ui/studio_components.dart';
import 'l10n/app_language.dart';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:video_player/video_player.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'models.dart';
import 'processor.dart';
import 'layout_controls.dart';
import 'queue_thumbnail.dart';
import 'settings_group.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await AppLanguage.instance.load();
  runApp(const MosaicApp());
}

class MosaicApp extends StatefulWidget {
  const MosaicApp({super.key});
  @override
  State<MosaicApp> createState() => _MosaicAppState();
}

class _MosaicAppState extends State<MosaicApp> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeLocales(List<Locale>? locales) =>
      AppLanguage.instance.deviceLocalesChanged();
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: AppLanguage.instance,
    builder: (context, _) => ShadApp.custom(
      theme: StudioTheme.shad(Brightness.light),
      darkTheme: StudioTheme.shad(Brightness.dark),
      appBuilder: (context) => MaterialApp(
        locale: AppLanguage.instance.value,
        supportedLocales: AppLanguage.supported,
        localizationsDelegates: const [
          GlobalShadLocalizations.delegate,
          ...GlobalMaterialLocalizations.delegates,
        ],
        localeListResolutionCallback: (locales, supported) =>
            AppLanguage.resolve(AppLanguage.instance.value, locales ?? []),
        title: 'Mosaic',
        debugShowCheckedModeBanner: false,
        theme: StudioTheme.material(Brightness.light),
        darkTheme: StudioTheme.material(Brightness.dark),
        builder: (context, child) => ShadAppBuilder(child: child!),
        home: HomePage(),
      ),
    ),
  );
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> with WidgetsBindingObserver {
  final processor = MosaicProcessor();
  final queue = <QueueItem>[];
  final results = <GeneratedFile>[];
  Settings settings = Settings();
  bool busy = false, picking = false, ready = false;
  bool saving = false;
  double progress = 0;
  String step = '';
  int page = 0;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _load();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    processor.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (busy && state == AppLifecycleState.paused) processor.cancel();
  }

  void message(String text) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
    }
  }

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getString('settings');
      if (saved != null) settings = Settings.fromJson(jsonDecode(saved));
      final dir = Directory(
        p.join((await getApplicationDocumentsDirectory()).path, 'results'),
      );
      if (await dir.exists()) {
        final files = await dir
            .list()
            .where((f) => f is File)
            .cast<File>()
            .toList();
        files.sort(
          (a, b) => b.lastModifiedSync().compareTo(a.lastModifiedSync()),
        );
        for (final f in files) {
          results.add(GeneratedFile(f.path, OutputKind.sheet));
        }
      }
    } catch (_) {
      message(tr('couldNotLoadSettingsUsingDefaults'));
    }
    if (mounted) setState(() => ready = true);
  }

  Future<void> _persist() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('settings', jsonEncode(settings.toJson()));
  }

  Future<void> _pick({bool files = false}) async {
    setState(() => picking = true);
    try {
      final selected = <QueueItem>[];
      if (files) {
        final picked = await FilePicker.platform.pickFiles(
          type: FileType.video,
          allowMultiple: true,
        );
        if (picked != null) {
          for (final f in picked.files) {
            if (f.path != null) selected.add(QueueItem(f.path!, f.name));
          }
        }
      } else {
        final picked =
            await MethodChannel(
              'mosaic/gallery',
            ).invokeListMethod<dynamic>('pickVideos') ??
            [];
        for (final value in picked) {
          final row = Map<String, dynamic>.from(value as Map);
          selected.add(
            QueueItem(
              row['path'] as String,
              row['name'] as String,
              sourceId: row['id'] as String?,
            ),
          );
        }
      }
      for (final item in selected) {
        if (queue.any(
          (q) => (q.sourceId ?? q.path) == (item.sourceId ?? item.path),
        )) {
          await processor.clearQueueCache(item);
        } else if (mounted) {
          setState(() {
            item.thumbnailLoading = true;
            queue.add(item);
          });
        }
      }
      processor.begin();
      for (final item in queue.where(
        (q) => q.metadata == null || q.thumbnailPath == null,
      )) {
        try {
          final metadata = item.metadata ?? await processor.probe(item.path);
          if (mounted) setState(() => item.metadata = metadata);
          try {
            final thumbnail = await processor.createThumbnail(
              item.path,
              metadata,
            );
            if (mounted) setState(() => item.thumbnailPath = thumbnail);
          } catch (_) {
            /* Preview failure does not prevent video processing. */
          }
        } catch (e) {
          if (mounted) {
            setState(() => item.setStatus('couldNotReadVideoInformation', e));
          }
        } finally {
          if (mounted) setState(() => item.thumbnailLoading = false);
        }
      }
    } catch (e) {
      message(tr('couldNotSelectFiles', [errorText(e)]));
    } finally {
      if (mounted) setState(() => picking = false);
    }
  }

  Future<void> _start() async {
    if (settings.outputs.isEmpty || queue.isEmpty) return;
    final snapshot = Settings.fromJson(settings.toJson());
    processor.begin();
    setState(() {
      busy = true;
      progress = 0;
      step = tr('readingVideoInformation');
    });
    try {
      await WakelockPlus.enable();
      await _persist();
      for (var i = 0; i < queue.length; i++) {
        processor.checkCancelled();
        final item = queue[i];
        setState(() => item.setStatus('processing'));
        try {
          await processor.generate(
            item,
            snapshot,
            (value, label) {
              if (mounted) {
                setState(() {
                  progress = ((i + value) / queue.length).clamp(0, 1);
                  step = '${i + 1}/${queue.length} · $label';
                });
              }
            },
            (file) {
              if (mounted) setState(() => results.insert(0, file));
            },
          );
          if (mounted) setState(() => item.setStatus('done'));
        } on JobCancelled {
          item.setStatus('canceled');
          rethrow;
        } catch (e) {
          if (mounted) setState(() => item.setStatus('failed', e));
        }
      }
      if (mounted) {
        setState(() {
          progress = 1;
          step = tr('processingFinishedCheckTheStatusOf');
        });
      }
    } on JobCancelled {
      message(tr('processingCanceledCompletedResultsAreRetained'));
    } catch (e) {
      message(tr('processingFailed', [errorText(e)]));
    } finally {
      await WakelockPlus.disable();
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _info(QueueItem item) async {
    setState(() => picking = true);
    try {
      processor.begin();
      final m = item.metadata ??= await processor.probe(item.path);
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (context) => ShadDialog(
          title: Text(item.name),
          actions: [
            StudioButton(
              ghost: true,
              onPressed: () => Navigator.pop(context),
              child: Text(tr('close')),
            ),
          ],
          child: SizedBox(
            width: 600,
            child: SingleChildScrollView(child: SelectableText(m.raw)),
          ),
        ),
      );
    } catch (e) {
      message(errorText(e));
    } finally {
      if (mounted) setState(() => picking = false);
    }
  }

  Future<void> _save(GeneratedFile file) async {
    if (saving) return;
    setState(() => saving = true);
    try {
      await MethodChannel(
        'mosaic/gallery',
      ).invokeMapMethod<String, dynamic>('save', {'path': file.path});
      message(tr('savedToTheMosaicAlbumIn'));
    } catch (e) {
      message(tr('couldNotSaveToGallery', [errorText(e)]));
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  Future<void> _removeQueueItem(QueueItem item) async {
    setState(() => queue.remove(item));
    try {
      await processor.clearQueueCache(item);
    } catch (_) {}
  }

  Future<void> _clearQueue() async {
    final old = List<QueueItem>.of(queue);
    setState(queue.clear);
    for (final item in old) {
      try {
        await processor.clearQueueCache(item);
      } catch (_) {}
    }
  }

  Future<void> _saveToFolder(GeneratedFile file) async {
    try {
      final saved = await MethodChannel('mosaic/storage').invokeMethod<bool>(
        'export',
        {'path': file.path, 'name': p.basename(file.path)},
      );
      if (saved == true) message(tr('savedToTheSelectedLocation'));
    } catch (e) {
      message(tr('couldNotSave', [errorText(e)]));
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !busy,
    onPopInvokedWithResult: (didPop, _) {
      if (!didPop && busy) message(tr('cancelProcessingBeforeClosingTheApp'));
    },
    child: Scaffold(
      appBar: AppBar(
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              LucideIcons.grid2x2,
              color: Theme.of(context).colorScheme.primary,
              size: 23,
            ),
            const SizedBox(width: 10),
            const Text('Mosaic'),
          ],
        ),
        actions: [
          IconButton(
            tooltip: tr('language'),
            icon: Icon(Icons.language),
            onPressed: _chooseLanguage,
          ),
          IconButton(
            tooltip: tr('about'),
            icon: Icon(Icons.info_outline),
            onPressed: () => showAboutDialog(
              context: context,
              applicationName: 'Mosaic Android',
              applicationVersion: '1.3.1',
              children: [Text(tr('aFlutterPortInspiredByMosaic'))],
            ),
          ),
        ],
      ),
      body: !ready
          ? Center(child: CircularProgressIndicator())
          : SafeArea(
              child: IndexedStack(
                index: page,
                children: [_queuePage(), _settingsPage(), _resultsPage()],
              ),
            ),
      bottomNavigationBar: StudioNavigation(
        index: page,
        onChanged: (i) => setState(() => page = i),
        labels: [tr('videos'), tr('settings'), tr('results')],
      ),
    ),
  );
  Future<void> _chooseLanguage() async {
    final choice = await showDialog<String>(
      context: context,
      builder: (context) => ShadDialog(
        title: Text(tr('language')),
        description: Text(tr('languageHint')),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final entry in {
              'system': tr('system'),
              'ko': '한국어',
              'en': 'English',
              'ja': '日本語',
            }.entries)
              StudioButton(
                ghost: true,
                onPressed: () => Navigator.pop(context, entry.key),
                icon: Icon(
                  (AppLanguage.instance.value?.languageCode ?? 'system') ==
                          entry.key
                      ? Icons.radio_button_checked
                      : Icons.radio_button_unchecked,
                  size: 18,
                ),
                child: Text(entry.value),
              ),
          ],
        ),
      ),
    );
    if (choice != null) {
      try {
        await AppLanguage.instance.select(
          choice == 'system' ? null : Locale(choice),
        );
      } catch (e) {
        message(tr('couldNotSave', [errorText(e)]));
      }
    }
  }

  VideoMetadata? get selectedMetadata =>
      queue.map((q) => q.metadata).whereType<VideoMetadata>().firstOrNull;

  Widget _queuePage() => Column(
    children: [
      Expanded(
        child: ListView(
          padding: EdgeInsets.all(20),
          children: [
            Container(
              padding: EdgeInsets.all(22),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primaryContainer,
                border: Border.all(
                  color: Theme.of(context).colorScheme.outlineVariant,
                ),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.auto_awesome_mosaic_rounded,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'MOSAIC STUDIO',
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.primary,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 2,
                          ),
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: 18),
                  Text(
                    tr('yourVideoMomentsInTheRight'),
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurface,
                      fontSize: 28,
                      fontWeight: FontWeight.w700,
                      height: 1.25,
                    ),
                  ),
                  SizedBox(height: 12),
                  Text(
                    tr('preserveSourceProportionsAdaptToShort'),
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                      height: 1.6,
                    ),
                  ),
                ],
              ),
            ),
            SizedBox(height: 18),
            StudioButton(
              onPressed: busy || picking ? null : _pick,
              icon: Icon(Icons.add_rounded),
              child: Text(
                picking ? tr('analyzingVideos') : tr('selectVideosFromGallery'),
              ),
            ),
            Align(
              alignment: Alignment.centerRight,
              child: StudioButton(
                ghost: true,
                onPressed: busy || picking ? null : () => _pick(files: true),
                icon: Icon(Icons.folder_open, size: 16),
                child: Text(tr('selectFiles')),
              ),
            ),
            SizedBox(height: 14),
            for (final item in queue)
              StudioPanel(
                child: ListTile(
                  contentPadding: EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  leading: QueueThumbnail(item: item),
                  title: Text(
                    item.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: Text(
                    '${item.metadata == null ? '' : '${item.metadata!.width} × ${item.metadata!.height} · ${timestamp(item.metadata!.duration)}\n'}${item.status}',
                  ),
                  onTap: busy || picking ? null : () => _info(item),
                  trailing: IconButton(
                    tooltip: tr('removeFromList'),
                    onPressed: busy || picking
                        ? null
                        : () => _removeQueueItem(item),
                    icon: Icon(Icons.close),
                  ),
                ),
              ),
            if (queue.isNotEmpty)
              Align(
                alignment: Alignment.centerRight,
                child: StudioButton(
                  ghost: true,
                  onPressed: busy || picking ? null : _clearQueue,
                  child: Text(tr('clearList')),
                ),
              ),
            SizedBox(height: 12),
            _layoutSummary(),
            SizedBox(height: 24),
            Text(
              tr('whatWouldYouLikeToCreate'),
              style: Theme.of(
                context,
              ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
            ),
            SizedBox(height: 12),
            LayoutBuilder(
              builder: (context, constraints) => Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  for (final kind in OutputKind.values)
                    SizedBox(
                      width: (constraints.maxWidth - 10) / 2,
                      child: _outputCard(kind),
                    ),
                ],
              ),
            ),
            SizedBox(height: 18),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.info_outline, size: 16),
                SizedBox(width: 6),
                Expanded(
                  child: Text(
                    tr('keepTheAppOpenWhileProcessing'),
                    style: TextStyle(fontSize: 12),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
      Container(
        padding: EdgeInsets.fromLTRB(20, 12, 20, 16),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          border: Border(
            top: BorderSide(
              color: Theme.of(context).colorScheme.outlineVariant,
            ),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (step.isNotEmpty) ...[
              Text(step, maxLines: 2, overflow: TextOverflow.ellipsis),
              SizedBox(height: 8),
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: ShadProgress(
                  value: progress,
                  minHeight: 6,
                  semanticsLabel: step,
                ),
              ),
              SizedBox(height: 12),
            ],
            StudioButton(
              onPressed: busy
                  ? () async {
                      await processor.cancel();
                    }
                  : queue.isEmpty || picking || settings.outputs.isEmpty
                  ? null
                  : _start,
              icon: Icon(busy ? Icons.stop_rounded : Icons.auto_awesome),
              child: Text(
                busy
                    ? tr('cancel', [(progress * 100).round()])
                    : queue.isEmpty
                    ? tr('selectAVideoFirst')
                    : tr('createFromVideoS', [queue.length]),
              ),
            ),
          ],
        ),
      ),
    ],
  );

  Widget _outputCard(OutputKind kind) {
    final selected = settings.outputs.contains(kind);
    final colors = Theme.of(context).colorScheme;
    final icons = [
      Icons.grid_view_rounded,
      Icons.photo_library_outlined,
      Icons.play_circle_outline,
      Icons.motion_photos_on_outlined,
    ];
    final captions = [
      tr('combineScenesIntoOneImage'),
      tr('saveEachSceneAsAnImage'),
      tr('playShortClipsInSequence'),
      tr('animateMultipleScenesTogether'),
    ];
    return Semantics(
      selected: selected,
      button: true,
      child: Material(
        color: selected ? colors.primaryContainer : colors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: BorderSide(
            color: selected ? colors.primary : colors.outlineVariant,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: busy
              ? null
              : () => _change(() {
                  selected
                      ? settings.outputs.remove(kind)
                      : settings.outputs.add(kind);
                }),
          child: Padding(
            padding: EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Icon(icons[kind.index], color: colors.primary),
                    Icon(
                      selected ? Icons.check_circle : Icons.circle_outlined,
                      color: selected ? colors.primary : colors.outline,
                      size: 20,
                    ),
                  ],
                ),
                SizedBox(height: 12),
                Text(kind.label, style: TextStyle(fontWeight: FontWeight.w700)),
                SizedBox(height: 6),
                Text(
                  captions[kind.index],
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _layoutSummary() {
    final m = selectedMetadata;
    final kind = settings.previewKind;
    final capacity = kind == OutputKind.screenshots
        ? settings.screenshotCount
        : kind == OutputKind.reel
        ? settings.reelCount
        : settings.gridCapacity;
    var details = tr('upToFrames', [
      kind.label,
      capacity,
      settings.thumbnailAspect == 'source'
          ? tr('sourceAspectRatio')
          : settings.thumbnailAspect,
    ]);
    if (m != null) {
      final samples = SamplePlan.create(settings, m, kind);
      try {
        final layout = SheetLayout.create(settings, m, kind, samples.count);
        details = tr('framesPx', [
          kind.label,
          samples.count,
          layout.width,
          layout.height,
          settings.adaptiveCount
              ? tr('automaticallyAdaptedToVideoLength')
              : tr('manuallySelectedCount'),
        ]);
      } on FormatException catch (e) {
        details = e.message;
      }
    }
    return StudioPanel(
      color: Theme.of(context).colorScheme.secondaryContainer,
      child: ListTile(
        contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: Icon(Icons.dashboard_customize_outlined),
        title: Text(
          tr('aspectRatioAndLayout'),
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
        subtitle: Text(details),
        trailing: Icon(Icons.chevron_right),
        onTap: () => setState(() => page = 1),
      ),
    );
  }

  Widget _settingsPage() => AbsorbPointer(
    absorbing: busy,
    child: ListView(
      padding: EdgeInsets.all(20),
      children: [
        Text(
          tr('outputSettings'),
          style: Theme.of(
            context,
          ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
        ),
        SizedBox(height: 8),
        StudioPanel(
          child: ListTile(
            title: Text(tr('selectedOutputs')),
            subtitle: Text(
              settings.outputs.isEmpty
                  ? tr('noOutputsSelectedChooseAnOutput')
                  : settings.outputs.map((e) => e.label).join(' · '),
            ),
            trailing: Icon(Icons.chevron_right),
            onTap: () => setState(() => page = 0),
          ),
        ),
        Padding(
          padding: EdgeInsets.symmetric(vertical: 12),
          child: Text(
            tr('onlySettingsNeededForSelectedOutputs'),
            style: TextStyle(fontSize: 12),
          ),
        ),
        if (busy) Text(tr('settingsCanBeChangedAfterProcessing')),
        LayoutControls(
          settings: settings,
          metadata: selectedMetadata,
          onChanged: () => _change(() {}),
        ),
        SettingsGroup(
          title: tr('samplingAndResolution'),
          description: tr('sharedByAllSelectedOutputs'),
          enabled: settings.outputs.isNotEmpty,
          disabledReason: tr('chooseAnOutputToGenerate'),
          children: [
            _slider(
              tr('outputWidthPx'),
              settings.width.toDouble(),
              320,
              1920,
              10,
              (v) => settings.width = v.round() ~/ 2 * 2,
            ),
            StudioToggle(
              title: Text(tr('reduceCountForShorterVideos')),
              subtitle: Text(tr('reducesTheActualSampleCountWithout')),
              value: settings.adaptiveCount,
              onChanged: (v) => _change(() => settings.adaptiveCount = v),
            ),
            _controlled(
              settings.adaptiveCount,
              tr('samplingIntervalIsInactiveWhileAutomatic'),
              Wrap(
                spacing: 8,
                children: [
                  for (final n in [1.0, 2.0, 5.0, 10.0])
                    StudioChoice(
                      label: Text(tr('framePerSeconds', [n.round()])),
                      selected: settings.sampleInterval == n,
                      onSelected: (_) =>
                          _change(() => settings.sampleInterval = n),
                    ),
                ],
              ),
            ),
          ],
        ),
        SettingsGroup(
          title: tr('stillImages'),
          description: tr('contactSheetsAndIndividualScreenshots'),
          enabled: settings.stillEnabled,
          disabledReason: tr('enabledWhenAStillSheetOr'),
          children: [
            _choice(
              tr('imageFormat'),
              settings.imageFormat,
              ['jpg', 'png'],
              (v) => settings.imageFormat = v,
            ),
            _controlled(
              settings.imageFormat == 'jpg',
              tr('pngIsLosslessYourJpegQuality'),
              _slider(
                tr('jpegQuality'),
                settings.jpegQuality.toDouble(),
                40,
                100,
                12,
                (v) => settings.jpegQuality = v.round(),
              ),
            ),
            _controlled(
              settings.outputs.contains(OutputKind.screenshots),
              tr('selectIndividualScreenshotsToAdjustTheir'),
              _slider(
                tr('maximumScreenshots'),
                settings.screenshotCount.toDouble(),
                1,
                100,
                99,
                (v) => settings.screenshotCount = v.round(),
              ),
            ),
          ],
        ),
        SettingsGroup(
          title: tr('animation'),
          description: tr('animatedPreviewsAndAnimatedSheets'),
          enabled: settings.animationEnabled,
          disabledReason: tr('enabledWhenAnimatedOutputsAreSelected'),
          children: [
            _controlled(
              settings.outputs.contains(OutputKind.reel),
              tr('animatedSheetsAlwaysUseWebpYour'),
              _choice(
                tr('previewFormat'),
                settings.animationFormat,
                ['webp', 'gif', 'webm'],
                (v) => settings.animationFormat = v,
              ),
            ),
            _controlled(
              settings.outputs.contains(OutputKind.reel),
              tr('selectAnimatedPreviewsToAdjustTheir'),
              _slider(
                tr('maximumPreviewClips'),
                settings.reelCount.toDouble(),
                1,
                100,
                99,
                (v) => settings.reelCount = v.round(),
              ),
            ),
            _slider(
              tr('clipDurationSecondsAllAnimations'),
              settings.clipSeconds,
              .5,
              5,
              9,
              (v) => settings.clipSeconds = v,
            ),
            _slider(
              tr('fpsAllAnimations'),
              settings.fps.toDouble(),
              4,
              15,
              11,
              (v) => settings.fps = v.round(),
            ),
            _controlled(
              settings.webpQualityEnabled,
              tr('webpQualityDoesNotApplyTo'),
              _slider(
                tr('webpQuality'),
                settings.webpQuality.toDouble(),
                40,
                100,
                12,
                (v) => settings.webpQuality = v.round(),
              ),
            ),
          ],
        ),
        SettingsGroup(
          title: tr('overlaysAndSpacing'),
          description: tr('appliesOnlyToSupportedOutputs'),
          enabled: settings.timestampEnabled || settings.gridEnabled,
          disabledReason: tr('headersAndTimestampsDoNotApply'),
          children: [
            _controlled(
              settings.gridEnabled,
              tr('cellSpacingIsUsedOnlyFor'),
              _slider(
                tr('cellSpacingPx'),
                settings.gap.toDouble(),
                0,
                24,
                12,
                (v) => settings.gap = v.round() ~/ 2 * 2,
              ),
            ),
            StudioToggle(
              title: Text(tr('timestamps')),
              subtitle: Text(tr('clipStartTimesOnStillImages')),
              value: settings.timestamps,
              onChanged: settings.timestampEnabled
                  ? (v) => _change(() => settings.timestamps = v)
                  : null,
            ),
            StudioToggle(
              title: Text(tr('fileInformationHeader')),
              subtitle: Text(tr('sheetOutputsOnly')),
              value: settings.header,
              onChanged: settings.gridEnabled
                  ? (v) => _change(() => settings.header = v)
                  : null,
            ),
            StudioToggle(
              title: Text(tr('darkOutputBackground')),
              subtitle: Text(tr('appliesToSheetBackgroundsAndAspect')),
              value: settings.dark,
              onChanged:
                  settings.gridEnabled ||
                      settings.thumbnailAspect != 'source' &&
                          !settings.effectiveCrop
                  ? (v) => _change(() => settings.dark = v)
                  : null,
            ),
          ],
        ),
        SettingsGroup(
          title: tr('fileNames'),
          description: tr('appliesToTheNamesOfAll'),
          children: [
            Text(
              tr('fileNameSuffix'),
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            ShadInput(
              initialValue: settings.suffix,
              placeholder: Text(tr('fileNameSuffix')),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp('[a-zA-Z0-9_-]')),
                LengthLimitingTextInputFormatter(32),
              ],
              onChanged: (v) {
                settings.suffix = v;
                _persist();
              },
            ),
            const SizedBox(height: 8),
            Text(
              tr('leaveEmptyForDefaultNamesExisting'),
              style: Theme.of(context).textTheme.bodySmall,
            ),
            SizedBox(height: 12),
            Text(
              tr('savingToGalleryCreatesANew'),
              style: TextStyle(fontSize: 12),
            ),
          ],
        ),
      ],
    ),
  );

  Widget _controlled(bool enabled, String reason, Widget child) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Semantics(
        enabled: enabled,
        child: ExcludeFocus(
          excluding: !enabled,
          child: AbsorbPointer(
            absorbing: !enabled,
            child: Opacity(opacity: enabled ? 1 : .4, child: child),
          ),
        ),
      ),
      if (!enabled)
        Padding(
          padding: EdgeInsets.only(top: 4, bottom: 8),
          child: Text(reason, style: Theme.of(context).textTheme.bodySmall),
        ),
    ],
  );
  void _change(VoidCallback change) {
    setState(change);
    _persist();
  }

  Widget _slider(
    String title,
    double value,
    double min,
    double max,
    int divisions,
    ValueChanged<double> change,
  ) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      SizedBox(height: 14),
      Text(
        '$title: ${value == value.roundToDouble() ? value.round() : value.toStringAsFixed(1)}',
      ),
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: ShadSlider(
          initialValue: value,
          min: min,
          max: max,
          divisions: divisions,
          onChanged: (v) => _change(() => change(v)),
        ),
      ),
    ],
  );
  Widget _choice(
    String title,
    String value,
    List<String> values,
    ValueChanged<String> change,
  ) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 8),
    child: Row(
      children: [
        Expanded(
          child: Text(
            title,
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
        ),
        const SizedBox(width: 12),
        ShadSelect<String>(
          initialValue: value,
          minWidth: 100,
          options: values.map(
            (v) => ShadOption(value: v, child: Text(v.toUpperCase())),
          ),
          selectedOptionBuilder: (_, v) => Text(v.toUpperCase()),
          onChanged: (v) {
            if (v != null) _change(() => change(v));
          },
        ),
      ],
    ),
  );
  Widget _resultsPage() => results.isEmpty
      ? Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.secondaryContainer,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Icon(
                    LucideIcons.images,
                    size: 32,
                    color: Theme.of(context).colorScheme.onSecondaryContainer,
                  ),
                ),
                const SizedBox(height: 20),
                Text(
                  tr('completedResultsWillAppearHere'),
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ],
            ),
          ),
        )
      : ListView.builder(
          padding: EdgeInsets.all(16),
          itemCount: results.length,
          itemBuilder: (context, i) {
            final file = results[i];
            return StudioPanel(
              child: Padding(
                padding: EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (p.extension(file.path) != '.webm')
                      GestureDetector(
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute<void>(
                            builder: (_) => PreviewPage(path: file.path),
                          ),
                        ),
                        child: Image.file(
                          File(file.path),
                          fit: BoxFit.fitWidth,
                          width: double.infinity,
                          cacheWidth: 640,
                          errorBuilder: (_, error, stack) => Center(
                            child: Icon(Icons.image_outlined, size: 48),
                          ),
                        ),
                      )
                    else
                      StudioButton(
                        outline: true,
                        onPressed: () => Navigator.push(
                          context,
                          MaterialPageRoute<void>(
                            builder: (_) => PreviewPage(path: file.path),
                          ),
                        ),
                        icon: Icon(Icons.play_arrow),
                        child: Text(tr('playPreview')),
                      ),
                    SizedBox(height: 8),
                    Text(
                      p.basename(file.path),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Wrap(
                      alignment: WrapAlignment.end,
                      children: [
                        StudioButton(
                          color: Theme.of(context).colorScheme.secondary,
                          onPressed: busy || saving ? null : () => _save(file),
                          icon: Icon(Icons.save_alt),
                          child: Text(
                            saving ? tr('saving') : tr('saveToGallery'),
                          ),
                        ),
                        StudioButton(
                          ghost: true,
                          onPressed: busy
                              ? null
                              : () async {
                                  try {
                                    await SharePlus.instance.share(
                                      ShareParams(files: [XFile(file.path)]),
                                    );
                                  } catch (e) {
                                    message(
                                      tr('couldNotShare', [errorText(e)]),
                                    );
                                  }
                                },
                          icon: Icon(Icons.share_outlined),
                          child: Text(tr('share')),
                        ),
                        IconButton(
                          tooltip: tr('saveFileToAnotherLocation'),
                          onPressed: busy || saving
                              ? null
                              : () => _saveToFolder(file),
                          icon: Icon(Icons.folder_copy_outlined),
                        ),
                        IconButton(
                          tooltip: tr('deleteResult'),
                          onPressed: busy
                              ? null
                              : () async {
                                  final yes = await showDialog<bool>(
                                    context: context,
                                    builder: (context) => ShadDialog(
                                      title: Text(tr('deleteThisResult')),
                                      actions: [
                                        StudioButton(
                                          ghost: true,
                                          onPressed: () =>
                                              Navigator.pop(context, false),
                                          child: Text(tr('cancel2')),
                                        ),
                                        StudioButton(
                                          ghost: true,
                                          onPressed: () =>
                                              Navigator.pop(context, true),
                                          child: Text(tr('delete')),
                                        ),
                                      ],
                                      child: Text(p.basename(file.path)),
                                    ),
                                  );
                                  if (yes == true) {
                                    try {
                                      await File(file.path).delete();
                                      if (mounted) {
                                        setState(() => results.remove(file));
                                      }
                                    } catch (e) {
                                      message(
                                        tr('couldNotDelete', [errorText(e)]),
                                      );
                                    }
                                  }
                                },
                          icon: Icon(Icons.delete_outline),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        );
}

class PreviewPage extends StatefulWidget {
  final String path;
  const PreviewPage({super.key, required this.path});
  @override
  State<PreviewPage> createState() => _PreviewPageState();
}

class _PreviewPageState extends State<PreviewPage> {
  VideoPlayerController? controller;
  String? error;
  @override
  void initState() {
    super.initState();
    if (p.extension(widget.path) == '.webm') _initializeVideo();
  }

  Future<void> _initializeVideo() async {
    final player = VideoPlayerController.file(File(widget.path));
    controller = player;
    try {
      await player.initialize();
      if (!mounted) return;
      await player.setLooping(true);
      await player.play();
      if (mounted) setState(() {});
    } catch (_) {
      if (mounted) {
        setState(() => error = tr('thisDeviceCannotPlayThisFile'));
      }
    }
  }

  @override
  void dispose() {
    controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: Color(0xff090e17),
    appBar: AppBar(
      backgroundColor: Color(0xff090e17),
      foregroundColor: Colors.white,
      title: Text(
        p.basename(widget.path),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
    ),
    body: Center(
      child: error != null
          ? Text(error!)
          : controller != null
          ? controller!.value.isInitialized
                ? AspectRatio(
                    aspectRatio: controller!.value.aspectRatio,
                    child: VideoPlayer(controller!),
                  )
                : CircularProgressIndicator()
          : InteractiveViewer(
              maxScale: 6,
              child: Image.file(File(widget.path)),
            ),
    ),
  );
}

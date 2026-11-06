import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
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

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MosaicApp());
}

class MosaicApp extends StatelessWidget {
  const MosaicApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Mosaic',
    debugShowCheckedModeBanner: false,
    theme: ThemeData(
      colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xff008768)),
      useMaterial3: true,
    ),
    darkTheme: ThemeData(
      colorScheme: ColorScheme.fromSeed(
        seedColor: const Color(0xff61d9b1),
        brightness: Brightness.dark,
      ),
      useMaterial3: true,
    ),
    home: const HomePage(),
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
      message('설정을 불러오지 못해 기본값을 사용합니다.');
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
            await const MethodChannel(
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
          if (mounted) setState(() => item.status = '정보 확인 실패: $e');
        } finally {
          if (mounted) setState(() => item.thumbnailLoading = false);
        }
      }
    } catch (e) {
      message('파일 선택 실패: $e');
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
      step = '영상 정보 확인 중';
    });
    try {
      await WakelockPlus.enable();
      await _persist();
      for (var i = 0; i < queue.length; i++) {
        processor.checkCancelled();
        final item = queue[i];
        setState(() => item.status = '처리 중');
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
          if (mounted) setState(() => item.status = '완료');
        } on JobCancelled {
          item.status = '취소됨';
          rethrow;
        } catch (e) {
          if (mounted) setState(() => item.status = '실패: $e');
        }
      }
      if (mounted) {
        setState(() {
          progress = 1;
          step = '처리가 끝났습니다. 파일별 상태를 확인하세요.';
        });
      }
    } on JobCancelled {
      message('작업을 취소했습니다. 완료된 결과는 보관됩니다.');
    } catch (e) {
      message('처리 실패: $e');
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
        builder: (context) => AlertDialog(
          title: Text(item.name),
          content: SizedBox(
            width: 600,
            child: SingleChildScrollView(child: SelectableText(m.raw)),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('닫기'),
            ),
          ],
        ),
      );
    } catch (e) {
      message('$e');
    } finally {
      if (mounted) setState(() => picking = false);
    }
  }

  Future<void> _save(GeneratedFile file) async {
    if (saving) return;
    setState(() => saving = true);
    try {
      await const MethodChannel(
        'mosaic/gallery',
      ).invokeMapMethod<String, dynamic>('save', {'path': file.path});
      message('갤러리의 Mosaic 앨범에 저장했습니다.');
    } catch (e) {
      message('갤러리 저장 실패: $e');
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
      final saved = await const MethodChannel('mosaic/storage')
          .invokeMethod<bool>('export', {
            'path': file.path,
            'name': p.basename(file.path),
          });
      if (saved == true) message('선택한 위치에 저장했습니다.');
    } catch (e) {
      message('저장 실패: $e');
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !busy,
    onPopInvokedWithResult: (didPop, _) {
      if (!didPop && busy) message('작업을 취소한 뒤 앱을 종료해 주세요.');
    },
    child: Scaffold(
      appBar: AppBar(
        title: const Text('Mosaic'),
        actions: [
          IconButton(
            tooltip: '앱 정보',
            icon: const Icon(Icons.info_outline),
            onPressed: () => showAboutDialog(
              context: context,
              applicationName: 'Mosaic Android',
              applicationVersion: '1.1.0',
              children: [
                const Text(
                  'Mosaic을 참고한 Flutter 포팅. 영상은 기기 안에서 처리합니다.\n\n백그라운드로 이동하면 작업을 취소합니다. Dolby Vision은 제외하며 HDR은 엔진이 지원할 때 변환합니다.\n\n원본: github.com/mosaicvideo/mosaic\nMosaic contributors · MIT\n영상 처리: FFmpegKit full (LGPL).',
                ),
              ],
            ),
          ),
        ],
      ),
      body: !ready
          ? const Center(child: CircularProgressIndicator())
          : SafeArea(
              child: IndexedStack(
                index: page,
                children: [_queuePage(), _settingsPage(), _resultsPage()],
              ),
            ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: page,
        onDestinationSelected: (i) => setState(() => page = i),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.video_library_outlined),
            label: '동영상',
          ),
          NavigationDestination(icon: Icon(Icons.tune), label: '설정'),
          NavigationDestination(
            icon: Icon(Icons.collections_outlined),
            label: '결과',
          ),
        ],
      ),
    ),
  );
  VideoMetadata? get selectedMetadata =>
      queue.map((q) => q.metadata).whereType<VideoMetadata>().firstOrNull;

  Widget _queuePage() => Column(
    children: [
      Expanded(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Container(
              padding: const EdgeInsets.all(22),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xff064e3b), Color(0xff0f766e)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(24),
              ),
              child: const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.auto_awesome_mosaic_rounded,
                        color: Color(0xff99f6e4),
                      ),
                      SizedBox(width: 8),
                      Text(
                        'MOSAIC STUDIO',
                        style: TextStyle(
                          color: Color(0xff99f6e4),
                          fontWeight: FontWeight.w700,
                          letterSpacing: 2,
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: 18),
                  Text(
                    '영상의 순간을,\n원하는 비율로.',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 28,
                      fontWeight: FontWeight.w700,
                      height: 1.25,
                    ),
                  ),
                  SizedBox(height: 12),
                  Text(
                    '원본 비율 유지 · 짧은 영상 자동 조절\n모든 처리는 내 기기 안에서',
                    style: TextStyle(color: Color(0xffccfbf1), height: 1.6),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),
            FilledButton.icon(
              onPressed: busy || picking ? null : _pick,
              icon: const Icon(Icons.add_rounded),
              label: Padding(
                padding: const EdgeInsets.symmetric(vertical: 13),
                child: Text(picking ? '동영상 분석 중…' : '갤러리에서 동영상 선택'),
              ),
            ),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: busy || picking ? null : () => _pick(files: true),
                icon: const Icon(Icons.folder_open, size: 16),
                label: const Text('파일에서 선택'),
              ),
            ),
            const SizedBox(height: 14),
            for (final item in queue)
              Card(
                elevation: 0,
                child: ListTile(
                  contentPadding: const EdgeInsets.symmetric(
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
                    tooltip: '목록에서 제거',
                    onPressed: busy || picking
                        ? null
                        : () => _removeQueueItem(item),
                    icon: const Icon(Icons.close),
                  ),
                ),
              ),
            if (queue.isNotEmpty)
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: busy || picking ? null : _clearQueue,
                  child: const Text('목록 비우기'),
                ),
              ),
            const SizedBox(height: 12),
            _layoutSummary(),
            const SizedBox(height: 24),
            Text(
              '무엇을 만들까요?',
              style: Theme.of(
                context,
              ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 12),
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
            const SizedBox(height: 18),
            const Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.info_outline, size: 16),
                SizedBox(width: 6),
                Expanded(
                  child: Text(
                    '처리 중에는 앱을 열어 두세요. 다른 앱으로 이동하면 취소됩니다.',
                    style: TextStyle(fontSize: 12),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
      Container(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
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
              const SizedBox(height: 8),
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: LinearProgressIndicator(value: progress, minHeight: 5),
              ),
              const SizedBox(height: 12),
            ],
            FilledButton.icon(
              onPressed: busy
                  ? () async {
                      await processor.cancel();
                    }
                  : queue.isEmpty || picking || settings.outputs.isEmpty
                  ? null
                  : _start,
              icon: Icon(busy ? Icons.stop_rounded : Icons.auto_awesome),
              label: Padding(
                padding: const EdgeInsets.symmetric(vertical: 13),
                child: Text(
                  busy
                      ? '작업 취소 · ${(progress * 100).round()}%'
                      : queue.isEmpty
                      ? '동영상을 먼저 선택하세요'
                      : '${queue.length}개 동영상으로 만들기',
                ),
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
      '한 장의 이미지로 모아 보기',
      '장면을 각각 이미지로 저장',
      '짧은 구간을 이어서 재생',
      '여러 장면이 동시에 움직여요',
    ];
    return Material(
      color: selected ? colors.secondaryContainer : colors.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
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
          padding: const EdgeInsets.all(14),
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
              const SizedBox(height: 12),
              Text(
                kind.label,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 6),
              Text(
                captions[kind.index],
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
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
    var details =
        '${kind.label} · 최대 $capacity개 · ${settings.thumbnailAspect == 'source' ? '원본 비율' : settings.thumbnailAspect}';
    if (m != null) {
      final samples = SamplePlan.create(settings, m, kind);
      try {
        final layout = SheetLayout.create(settings, m, kind, samples.count);
        details =
            '${kind.label} · ${samples.count}개 · ${layout.width} × ${layout.height}px\n${settings.adaptiveCount ? '영상 길이에 맞게 자동 조절' : '직접 지정한 개수'}';
      } on FormatException catch (e) {
        details = e.message;
      }
    }
    return Card(
      elevation: 0,
      color: Theme.of(context).colorScheme.surfaceContainerHigh,
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: const Icon(Icons.dashboard_customize_outlined),
        title: const Text(
          '비율과 배치',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
        subtitle: Text(details),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => setState(() => page = 1),
      ),
    );
  }

  Widget _settingsPage() => AbsorbPointer(
    absorbing: busy,
    child: ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Text(
          '출력 설정',
          style: Theme.of(
            context,
          ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 8),
        Card(
          elevation: 0,
          child: ListTile(
            title: const Text('현재 적용할 결과'),
            subtitle: Text(
              settings.outputs.isEmpty
                  ? '선택된 결과가 없습니다. 결과 종류를 먼저 선택하세요.'
                  : settings.outputs.map((e) => e.label).join(' · '),
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => setState(() => page = 0),
          ),
        ),
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 12),
          child: Text(
            '선택한 결과에 필요한 설정만 활성화됩니다. 비활성 값은 지우거나 덮어쓰지 않고 보관합니다.',
            style: TextStyle(fontSize: 12),
          ),
        ),
        if (busy) const Text('작업이 끝나면 설정을 변경할 수 있습니다.'),
        LayoutControls(
          settings: settings,
          metadata: selectedMetadata,
          onChanged: () => _change(() {}),
        ),
        SettingsGroup(
          title: '4. 추출과 해상도',
          description: '선택한 모든 출력에 공통 적용',
          enabled: settings.outputs.isNotEmpty,
          disabledReason: '생성할 결과를 선택하세요.',
          children: [
            _slider(
              '출력 너비 (px)',
              settings.width.toDouble(),
              320,
              1920,
              10,
              (v) => settings.width = v.round() ~/ 2 * 2,
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('영상 길이에 맞춰 개수 줄이기'),
              subtitle: const Text('최대 개수와 배치 값을 바꾸지 않고 실제 추출 개수만 줄입니다.'),
              value: settings.adaptiveCount,
              onChanged: (v) => _change(() => settings.adaptiveCount = v),
            ),
            _controlled(
              settings.adaptiveCount,
              '자동 개수 조절이 꺼져 있어 간격 설정을 사용하지 않습니다.',
              Wrap(
                spacing: 8,
                children: [
                  for (final n in [1.0, 2.0, 5.0, 10.0])
                    ChoiceChip(
                      label: Text('${n.round()}초당 1개'),
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
          title: '5. 정적 이미지',
          description: '썸네일 모음 · 개별 스크린샷',
          enabled: settings.stillEnabled,
          disabledReason: '정적 모음 또는 스크린샷을 선택하면 활성화됩니다.',
          children: [
            _choice('이미지 형식', settings.imageFormat, [
              'jpg',
              'png',
            ], (v) => settings.imageFormat = v),
            _controlled(
              settings.imageFormat == 'jpg',
              'PNG는 무손실 형식입니다. JPEG 품질 값은 보관만 합니다.',
              _slider(
                'JPEG 품질',
                settings.jpegQuality.toDouble(),
                40,
                100,
                12,
                (v) => settings.jpegQuality = v.round(),
              ),
            ),
            _controlled(
              settings.outputs.contains(OutputKind.screenshots),
              '개별 스크린샷을 선택하면 최대 개수를 조절할 수 있습니다.',
              _slider(
                '스크린샷 최대 개수',
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
          title: '6. 애니메이션',
          description: '움직이는 미리보기 · 움직이는 모음',
          enabled: settings.animationEnabled,
          disabledReason: '움직이는 출력을 선택하면 활성화됩니다.',
          children: [
            _controlled(
              settings.outputs.contains(OutputKind.reel),
              '움직이는 모음은 WebP로 고정됩니다. 미리보기 형식 값은 보관됩니다.',
              _choice(
                '미리보기 형식',
                settings.animationFormat,
                ['webp', 'gif', 'webm'],
                (v) => settings.animationFormat = v,
              ),
            ),
            _controlled(
              settings.outputs.contains(OutputKind.reel),
              '움직이는 미리보기를 선택하면 구간 개수를 조절할 수 있습니다.',
              _slider(
                '미리보기 최대 구간 수',
                settings.reelCount.toDouble(),
                1,
                100,
                99,
                (v) => settings.reelCount = v.round(),
              ),
            ),
            _slider(
              '구간 길이 (초) · 움직이는 출력 공통',
              settings.clipSeconds,
              .5,
              5,
              9,
              (v) => settings.clipSeconds = v,
            ),
            _slider(
              'FPS · 움직이는 출력 공통',
              settings.fps.toDouble(),
              4,
              15,
              11,
              (v) => settings.fps = v.round(),
            ),
            _controlled(
              settings.webpQualityEnabled,
              'GIF와 WebM에는 WebP 품질을 적용하지 않습니다. 이전 값은 보관됩니다.',
              _slider(
                'WebP 품질',
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
          title: '7. 표시와 간격',
          description: '지원되는 출력에만 표시됩니다.',
          enabled: settings.timestampEnabled || settings.gridEnabled,
          disabledReason: '미리보기 영상에는 헤더·시간 표시가 적용되지 않습니다.',
          children: [
            _controlled(
              settings.gridEnabled,
              '모음 출력에서만 칸 사이 간격을 사용합니다.',
              _slider(
                '칸 사이 간격 (px)',
                settings.gap.toDouble(),
                0,
                24,
                12,
                (v) => settings.gap = v.round() ~/ 2 * 2,
              ),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('시간 표시'),
              subtitle: const Text('정적 이미지와 움직이는 모음의 구간 시작 시각'),
              value: settings.timestamps,
              onChanged: settings.timestampEnabled
                  ? (v) => _change(() => settings.timestamps = v)
                  : null,
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('파일 정보 헤더'),
              subtitle: const Text('모음 출력 전용'),
              value: settings.header,
              onChanged: settings.gridEnabled
                  ? (v) => _change(() => settings.header = v)
                  : null,
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('어두운 출력 배경'),
              subtitle: const Text('모음 또는 비율 맞춤의 여백에 적용'),
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
          title: '8. 파일 이름',
          description: '선택된 모든 결과의 이름에 적용',
          children: [
            TextFormField(
              initialValue: settings.suffix,
              decoration: const InputDecoration(
                labelText: '파일명 접미사',
                helperText: '비우면 종류별 기본 이름 · 기존 파일은 덮어쓰지 않습니다.',
              ),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp('[a-zA-Z0-9_-]')),
                LengthLimitingTextInputFormatter(32),
              ],
              onChanged: (v) {
                settings.suffix = v;
                _persist();
              },
            ),
            const SizedBox(height: 12),
            const Text(
              '갤러리 저장은 Mosaic 앨범에 새 복사본을 만듭니다. 원본 영상과 기존 결과는 덮어쓰지 않습니다.',
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
          padding: const EdgeInsets.only(top: 4, bottom: 8),
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
      const SizedBox(height: 14),
      Text(
        '$title: ${value == value.roundToDouble() ? value.round() : value.toStringAsFixed(1)}',
      ),
      Slider(
        value: value,
        min: min,
        max: max,
        divisions: divisions,
        onChanged: (v) => _change(() => change(v)),
      ),
    ],
  );
  Widget _choice(
    String title,
    String value,
    List<String> values,
    ValueChanged<String> change,
  ) => ListTile(
    contentPadding: EdgeInsets.zero,
    title: Text(title),
    trailing: DropdownButton<String>(
      value: value,
      items: values
          .map((v) => DropdownMenuItem(value: v, child: Text(v.toUpperCase())))
          .toList(),
      onChanged: (v) => _change(() => change(v!)),
    ),
  );
  Widget _resultsPage() => results.isEmpty
      ? const Center(child: Text('완성된 결과가 여기에 표시됩니다.'))
      : ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: results.length,
          itemBuilder: (context, i) {
            final file = results[i];
            return Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
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
                          errorBuilder: (_, error, stack) => const Center(
                            child: Icon(Icons.image_outlined, size: 48),
                          ),
                        ),
                      )
                    else
                      OutlinedButton.icon(
                        onPressed: () => Navigator.push(
                          context,
                          MaterialPageRoute<void>(
                            builder: (_) => PreviewPage(path: file.path),
                          ),
                        ),
                        icon: const Icon(Icons.play_arrow),
                        label: const Text('미리보기 재생'),
                      ),
                    const SizedBox(height: 8),
                    Text(
                      p.basename(file.path),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Wrap(
                      alignment: WrapAlignment.end,
                      children: [
                        TextButton.icon(
                          onPressed: busy || saving ? null : () => _save(file),
                          icon: const Icon(Icons.save_alt),
                          label: Text(saving ? '저장 중…' : '갤러리 저장'),
                        ),
                        TextButton.icon(
                          onPressed: busy
                              ? null
                              : () async {
                                  try {
                                    await SharePlus.instance.share(
                                      ShareParams(files: [XFile(file.path)]),
                                    );
                                  } catch (e) {
                                    message('공유 실패: $e');
                                  }
                                },
                          icon: const Icon(Icons.share_outlined),
                          label: const Text('공유'),
                        ),
                        IconButton(
                          tooltip: '다른 위치에 파일로 저장',
                          onPressed: busy || saving
                              ? null
                              : () => _saveToFolder(file),
                          icon: const Icon(Icons.folder_copy_outlined),
                        ),
                        IconButton(
                          tooltip: '결과 삭제',
                          onPressed: busy
                              ? null
                              : () async {
                                  final yes = await showDialog<bool>(
                                    context: context,
                                    builder: (context) => AlertDialog(
                                      title: const Text('결과를 삭제할까요?'),
                                      content: Text(p.basename(file.path)),
                                      actions: [
                                        TextButton(
                                          onPressed: () =>
                                              Navigator.pop(context, false),
                                          child: const Text('취소'),
                                        ),
                                        TextButton(
                                          onPressed: () =>
                                              Navigator.pop(context, true),
                                          child: const Text('삭제'),
                                        ),
                                      ],
                                    ),
                                  );
                                  if (yes == true) {
                                    try {
                                      await File(file.path).delete();
                                      if (mounted) {
                                        setState(() => results.remove(file));
                                      }
                                    } catch (e) {
                                      message('삭제 실패: $e');
                                    }
                                  }
                                },
                          icon: const Icon(Icons.delete_outline),
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
        setState(() => error = '이 기기에서 재생할 수 없습니다. 저장 또는 공유하여 확인하세요.');
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
    backgroundColor: const Color(0xff090e17),
    appBar: AppBar(
      backgroundColor: const Color(0xff090e17),
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
                : const CircularProgressIndicator()
          : InteractiveViewer(
              maxScale: 6,
              child: Image.file(File(widget.path)),
            ),
    ),
  );
}

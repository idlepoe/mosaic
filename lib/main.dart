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

  Future<void> _pick() async {
    setState(() => picking = true);
    try {
      final picked = await FilePicker.platform.pickFiles(
        type: FileType.video,
        allowMultiple: true,
      );
      if (picked != null && mounted) {
        setState(() {
          for (final f in picked.files) {
            if (f.path != null && !queue.any((q) => q.path == f.path)) {
              queue.add(QueueItem(f.path!, f.name));
            }
          }
        });
      }
    } catch (e) {
      message('파일 선택 실패: $e');
    } finally {
      if (mounted) setState(() => picking = false);
    }
  }

  Future<void> _start() async {
    if (settings.outputs.isEmpty || queue.isEmpty) return;
    if (settings.outputs.contains(OutputKind.animatedSheet) &&
        settings.columns * settings.rows > 9) {
      message('움직이는 썸네일 모음은 최대 9칸입니다. 설정에서 행·열을 줄여 주세요.');
      return;
    }
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
              applicationVersion: '1.0.0',
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
  Widget _queuePage() => Column(
    children: [
      Expanded(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text(
              '영상의 순간을 한눈에',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: Text('동영상을 선택하고 썸네일과 움직이는 미리보기를 만드세요. 영상은 업로드하지 않습니다.'),
            ),
            FilledButton.icon(
              onPressed: busy || picking ? null : _pick,
              icon: const Icon(Icons.add),
              label: Text(picking ? '파일 확인 중…' : '동영상 추가'),
            ),
            if (queue.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 48),
                child: Center(child: Text('선택한 동영상이 여기에 표시됩니다.')),
              ),
            for (final item in queue)
              Card(
                child: ListTile(
                  leading: const Icon(Icons.movie_outlined),
                  title: Text(
                    item.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: Text(item.status),
                  onTap: busy || picking ? null : () => _info(item),
                  trailing: IconButton(
                    tooltip: '목록에서 제거',
                    onPressed: busy || picking
                        ? null
                        : () => setState(() => queue.remove(item)),
                    icon: const Icon(Icons.close),
                  ),
                ),
              ),
            if (queue.isNotEmpty)
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: busy || picking
                      ? null
                      : () => setState(queue.clear),
                  child: const Text('목록 비우기'),
                ),
              ),
            const SizedBox(height: 12),
            Text('생성할 결과', style: Theme.of(context).textTheme.titleMedium),
            for (final kind in OutputKind.values)
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(kind.label),
                subtitle: kind == OutputKind.animatedSheet
                    ? const Text('WebP · 최대 9칸')
                    : null,
                value: settings.outputs.contains(kind),
                onChanged: busy
                    ? null
                    : (v) {
                        setState(() {
                          v!
                              ? settings.outputs.add(kind)
                              : settings.outputs.remove(kind);
                        });
                        _persist();
                      },
              ),
            const Text(
              '처리 중에는 앱을 화면에 유지해 주세요. 다른 앱으로 이동하면 작업을 취소합니다.',
              style: TextStyle(fontSize: 12),
            ),
          ],
        ),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (step.isNotEmpty) ...[
              Text(step),
              const SizedBox(height: 8),
              LinearProgressIndicator(value: progress),
              const SizedBox(height: 8),
            ],
            FilledButton.icon(
              onPressed: busy
                  ? () async {
                      await processor.cancel();
                    }
                  : queue.isEmpty || picking || settings.outputs.isEmpty
                  ? null
                  : _start,
              icon: Icon(busy ? Icons.stop : Icons.auto_awesome),
              label: Text(busy ? '작업 취소' : '${queue.length}개 동영상 생성'),
            ),
          ],
        ),
      ),
    ],
  );
  Widget _settingsPage() => AbsorbPointer(
    absorbing: busy,
    child: ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text('출력 설정', style: Theme.of(context).textTheme.headlineSmall),
        if (busy) const Text('작업이 끝나면 설정을 변경할 수 있습니다.'),
        _slider(
          '열',
          settings.columns.toDouble(),
          1,
          6,
          5,
          (v) => settings.columns = v.round(),
        ),
        _slider(
          '행',
          settings.rows.toDouble(),
          1,
          6,
          5,
          (v) => settings.rows = v.round(),
        ),
        _slider(
          '출력 너비 (px)',
          settings.width.toDouble(),
          320,
          1920,
          10,
          (v) => settings.width = v.round() ~/ 2 * 2,
        ),
        _slider(
          '간격 (px)',
          settings.gap.toDouble(),
          0,
          24,
          12,
          (v) => settings.gap = v.round() ~/ 2 * 2,
        ),
        _slider(
          '스크린샷 / 미리보기 구간 수',
          settings.count.toDouble(),
          1,
          24,
          23,
          (v) => settings.count = v.round(),
        ),
        _slider(
          '구간 길이 (초)',
          settings.clipSeconds,
          .5,
          5,
          9,
          (v) => settings.clipSeconds = v,
        ),
        _slider(
          '애니메이션 FPS',
          settings.fps.toDouble(),
          4,
          15,
          11,
          (v) => settings.fps = v.round(),
        ),
        _slider(
          '이미지 품질',
          settings.quality.toDouble(),
          40,
          100,
          12,
          (v) => settings.quality = v.round(),
        ),
        SwitchListTile(
          title: const Text('시간 표시'),
          subtitle: const Text('정적 이미지와 움직이는 모음의 구간 시작 시각'),
          value: settings.timestamps,
          onChanged: (v) => _change(() => settings.timestamps = v),
        ),
        SwitchListTile(
          title: const Text('파일 정보 헤더'),
          subtitle: const Text('썸네일 모음에 파일명·해상도·길이·코덱 표시'),
          value: settings.header,
          onChanged: (v) => _change(() => settings.header = v),
        ),
        SwitchListTile(
          title: const Text('어두운 출력 배경'),
          value: settings.dark,
          onChanged: (v) => _change(() => settings.dark = v),
        ),
        _choice('정적 이미지 형식', settings.imageFormat, [
          'jpg',
          'png',
        ], (v) => settings.imageFormat = v),
        _choice(
          '움직이는 미리보기 형식',
          settings.animationFormat,
          ['webp', 'gif', 'webm'],
          (v) => settings.animationFormat = v,
        ),
        TextFormField(
          initialValue: settings.suffix,
          decoration: const InputDecoration(
            labelText: '파일명 접미사',
            helperText: '비우면 종류별 기본 이름 · 영문, 숫자, _, -',
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
        const SizedBox(height: 16),
        const Text(
          '결과는 앱 내부에 보관합니다. 결과 화면에서 저장 위치를 선택하거나 공유할 수 있습니다. 앱 삭제 시 내부 결과도 삭제됩니다.\n\n메모리와 발열을 고려해 순서대로 처리하며 정적 모음은 최대 36칸, 움직이는 모음은 최대 9칸을 지원합니다.',
        ),
      ],
    ),
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
                        child: SizedBox(
                          height: 180,
                          child: Image.file(
                            File(file.path),
                            fit: BoxFit.contain,
                            cacheWidth: 640,
                            errorBuilder: (_, error, stack) => const Center(
                              child: Icon(Icons.image_outlined, size: 48),
                            ),
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
                          onPressed: busy ? null : () => _save(file),
                          icon: const Icon(Icons.save_alt),
                          label: const Text('저장'),
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
    appBar: AppBar(title: Text(p.basename(widget.path))),
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

# Mosaic Android

An Android app built with Flutter that creates video contact sheets, screenshots, animated previews, and animated contact sheets directly on your phone. Videos are processed locally with bundled FFmpeg and FFprobe libraries; no server, account, or separate command-line tool installation is required. The current app interface is in Korean.

## Original project

This project is a mobile port based on **[Mosaic by mosaicvideo](https://github.com/mosaicvideo/mosaic)**, an open-source desktop application for Windows, macOS, and Linux.

- Original repository: [mosaicvideo/mosaic](https://github.com/mosaicvideo/mosaic)
- Original website: [mosaicvideo.github.io](https://mosaicvideo.github.io/)
- Reference version: **v0.1.10**, commit [`ffed6a225267c063034b3e31eccfbadd70a21846`](https://github.com/mosaicvideo/mosaic/tree/ffed6a225267c063034b3e31eccfbadd70a21846)
- Local reference checkout used for this port: `C:\Workspace\mosaic_sample`
- Original license: **MIT**, copyright 2026 Mosaic contributors. See [LICENSE](LICENSE).

This Flutter implementation is an Android adaptation of the original project. It does not imply endorsement by the original maintainers.

## Features

| Output | Formats | Description |
|---|---|---|
| Contact sheet | JPEG, PNG | A grid of evenly sampled frames with optional timestamps and a filename/metadata header |
| Screenshots | JPEG, PNG | Individual frames sampled throughout a video, with optional timestamps |
| Animated preview | WebP, GIF, WebM | Short segments sampled throughout a video and joined into a silent preview |
| Animated contact sheet | WebP | Multiple short video segments playing together in a grid, with optional start-time labels and header |

Additional features include multiple-file selection, a sequential processing queue, per-file status, step progress, cancellation, saved settings, metadata inspection, image zoom, animation preview, Android document export, sharing, and collision-safe output filenames.

## Screenshots

These are actual screenshots of the physical **SM-S931N** device mirrored through **scrcpy**, captured during testing on **November 6, 2026**. The color-bar video is a test fixture from the original repository.

| Video queue | Output settings | Output selection |
|:---:|:---:|:---:|
| <img src="docs/screenshots/01-video-queue.jpg" width="240" alt="Video selected in the queue"> | <img src="docs/screenshots/02-output-settings.jpg" width="240" alt="Grid and output settings"> | <img src="docs/screenshots/03-selected-outputs.jpg" width="240" alt="All four output types selected"> |

| Processing | Animated results | Static contact sheet |
|:---:|:---:|:---:|
| <img src="docs/screenshots/04-generation-progress.jpg" width="240" alt="Generation progress and cancel control"> | <img src="docs/screenshots/06-animated-results.jpg" width="240" alt="Animated sheet and preview results"> | <img src="docs/screenshots/10-contact-sheet-preview.jpg" width="240" alt="Full contact sheet preview"> |

See the [complete screenshot index](docs/screenshots/README.md) for all 12 captures and the [physical-device test report](docs/TESTING.md) for the test steps and results.

## What was ported

The original application uses a **Tauri 2 frontend and Rust backend**, which launch desktop `ffmpeg`, `ffprobe`, and `mediainfo` processes. This port implements the UI in **Flutter/Dart** and calls **FFmpegKit full** through its Flutter plugin. The desktop executables and Tauri shell are not included in the Android app.

The Dart processing implementation follows the original application's four-output workflow, evenly spaced frame sampling, bounded clip-start sampling, aspect-ratio handling, grid composition, configurable suffixes, filename collision handling, and completion/cancellation model. Rust source is used as a reference rather than linked as an unchanged library.

| Original behavior | Android implementation |
|---|---|
| Desktop HTML/CSS/JavaScript interface | Korean Material 3 UI with Videos, Settings, and Results navigation |
| External FFmpeg and FFprobe processes | Bundled native libraries called through `ffmpeg_kit_flutter_new_full` |
| Frame sampling and pipeline orchestration | Dart implementation; sampled clips do not extend beyond the source duration |
| Static headers and timestamps | Flutter Canvas rendering, including phone font support |
| File and folder input | Multiple-file selection through Android's system picker |
| Desktop output directory | App-private result storage plus Android Storage Access Framework export |
| Reveal in Explorer/Finder | In-app preview, document export, and the Android share sheet |
| MediaInfo enrichment and report | FFprobe JSON metadata viewer; commercial codec-name enrichment is not reproduced |
| Parallel desktop work | Sequential processing to reduce memory pressure and heat |
| Output naming | Default or custom suffixes, with `(1)`, `(2)`, etc. added to avoid overwriting results |

### Mobile limits and excluded features

- **Static grids:** up to 6 × 6 cells. **Animated grids:** up to 9 cells. Screenshots and preview reels support up to 24 samples/segments.
- Output width is limited to **1920 px**. Very large combinations, including unusually tall images, are rejected to limit memory use.
- Fonts use mobile defaults instead of exposing every desktop typography option. Rendered results are not pixel-identical to the desktop version.
- Preview reels are silent and do not include metadata headers or timestamp overlays. Animated contact-sheet labels show each segment's start time, not a continuously updating clock.
- **HDR10/HLG:** SDR tone mapping is used only when the bundled engine exposes the required `zscale` filter. Otherwise the app reports an unsupported operation.
- **Dolby Vision:** excluded until accurate mobile color conversion is validated; affected input is rejected with an explanation.
- Desktop CLI commands, recursive folder scanning, desktop drag-and-drop, package-manager installation, and the desktop self-updater are excluded.
- Long-running background processing is not implemented. The app keeps the display awake while generating; moving it to the background cancels the active batch. Interrupted work must be started again.
- Codec and container support depends on the bundled FFmpeg build. This port does not promise support for every possible input file.

## Using the app

1. Open **Videos** (`동영상`) and tap **Add videos** (`동영상 추가`). Select one or more video files.
2. Select the output types. Tap a queue item to inspect its FFprobe metadata.
3. Open **Settings** (`설정`) to adjust grid size, width, spacing, sample count, segment duration, FPS, quality, timestamps, header, background, formats, and filename suffix.
4. Tap **Generate**. Keep the app visible until processing finishes. Use **Cancel** to stop the batch.
5. Open **Results** (`결과`) to preview the files. Tap an image to enlarge it; animated images play in the preview.
6. Tap **Save** (`저장`) to choose a location using Android's document dialog, or **Share** (`공유`) to open the share sheet.

### Storage and privacy

Videos are not uploaded. Input files may be copied into the system picker's app cache, so the device needs sufficient free space. Completed outputs are stored in the app's private documents directory and rediscovered after restarting the app. Export important results before uninstalling: uninstalling removes app-private files.

Each pipeline writes to a temporary working directory. Completed files are moved into the results directory only after successful generation. Cancellation or failure cleans up that job's temporary files while retaining already completed outputs. The input queue itself is not restored after restarting the app.

## Build and run

Requirements: Flutter 3.41 / Dart 3.11 or later, Android SDK, and a compatible Java toolchain. The Android build targets **API 24+ (Android 7.0+)**. The project compiles Java/Kotlin sources for Java 17.

```sh
flutter pub get
flutter devices
flutter run -d <physical-device-id>
```

Build a debug APK:

```sh
flutter build apk --debug
```

Build an ARM64 release-mode APK:

```sh
flutter build apk --release --target-platform android-arm64 --split-per-abi
```

Output: `build/app/outputs/flutter-apk/app-arm64-v8a-release.apk` (approximately 45.3 MB for the tested build).

The current release configuration uses the development signing key. Configure a production signing key and complete native-library licensing/distribution requirements before publishing.

## Project structure

| Path | Purpose |
|---|---|
| `lib/main.dart` | UI, video queue, settings persistence, result browser, and previews |
| `lib/models.dart` | Settings, output types, metadata models, and sampling helpers |
| `lib/processor.dart` | FFprobe inspection, FFmpeg sessions, composition, cancellation, and output handling |
| `android/app/src/main/kotlin/com/mosaicvideo/mosaic/MainActivity.kt` | SAF document export with streaming file copy |
| `test/sampling_test.dart` | Sampling bounds and saved-settings tests |
| `integration_test/processor_test.dart` | Real native processing and cancellation tests |
| `docs/screenshots/` | Physical-device scrcpy captures |
| `docs/test-results/` | Output exported during the manual test |

## Verification

```sh
flutter analyze
flutter test
flutter test integration_test/processor_test.dart -d <physical-device-id>
```

The automated native test creates a synthetic input video, exercises all four output types and JPEG/PNG/WebP/GIF/WebM outputs, checks filename collisions, and verifies cancellation followed by a fresh operation. It removes its own generated test files.

On **November 6, 2026**, code analysis completed without issues, all four unit tests passed, and the native integration test passed on an **SM-S931N running Android API 36**. The ARM64 APK was built, installed, and launched on that device.

The subsequent **scrcpy manual test passed** video selection, settings changes, all four output types, static and animated previews, FFprobe metadata display, SAF export to Downloads, and result restoration after restarting the app. The test produced nine files: one contact sheet, six screenshots, one preview reel, and one animated sheet. See [the test report](docs/TESTING.md) for evidence and checks that were not performed.

## Licenses and acknowledgments

The original Mosaic project is licensed under MIT; its copyright and license text are retained in [LICENSE](LICENSE). FFmpegKit, FFmpeg, and bundled native components have their own licenses. This project uses the full package without the optional GPL codec bundle; the Mosaic MIT license does not cover those native binaries. See [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md) for dependency attribution and distribution notes.

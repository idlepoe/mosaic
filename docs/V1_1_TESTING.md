# Version 1.1 validation

Version: **1.1.0+4**, November 6, 2026 (Asia/Seoul).

## Changes and original behavior

The reference Rust functions are in `mosaic_sample/src-tauri/src/layout.rs`. Still frames use evenly spaced interior timestamps and do not automatically reduce the requested count. Animated sampling restricts starts to the remaining span and rejects a source no longer than the requested clip. In the initial Flutter port, clamping the clip to a short source's entire duration left a zero-length start span; requesting several cells then repeated the same clip.

The new `SamplePlan` treats counts as upper bounds by default. The selected interval controls time-based density, clips are bounded to the source, and a zero-length start span produces one clip. Still sampling also considers the approximate frame interval to avoid seeking beyond a single-frame source. This is not visual duplicate or scene-change detection.

`SheetLayout` is shared by static composition, animation merging, and the live preview. Content-fit is now the default: the grid fills the output width, outer margins are zero, and output height follows the source aspect and row count. This fixes the reported portrait-grid / wide-canvas black gutters. Existing settings migrate to content fit. Thumbnail aspect and optional fixed canvas aspect remain independent. In fixed-ratio mode, selecting a ratio suggests a row/column arrangement without changing the requested capacity. Source content is fitted or explicitly center-cropped, never stretched.

The bundled FFprobeKit omitted rotation side data in an actual rotated MP4 test. Orientation is supplemented with Android MediaMetadataRetriever. When Android cannot inspect the container, one FFmpeg-decoded frame supplies displayed dimensions after autorotation. The FFprobe JSON viewer includes the supplementary display information used by the pipeline.

## Automated tests

- Static analysis: no issues found.
- Unit/widget tests: 24 passed. Coverage includes content-fit gutter removal and settings migration, short-source count reduction, nonoverlapping adaptive clips, source/canvas aspect ratios, rotation and SAR, native orientation fallback, bounded output area, independent quality/count preferences, disabled controls, preserved manual layout, and a narrow-phone settings widget.
- Existing physical-device native pipeline test: passed, including four output types, JPEG/PNG/WebP/GIF/WebM, filename collisions, cancellation, and a subsequent operation.
- New physical-device aspect test: passed on **TB320FC, Android API 35**.
- Opt-in MediaStore gallery test: passed on the same device. JPEG, PNG, animated WebP, GIF, and WebM each returned a valid gallery content URI. The five nonempty files were also verified under `Pictures/Mosaic` and `Movies/Mosaic`.

The new native test actually generated and decoded:

| Scenario | Result |
|---|---|
| 32-second landscape source, 16-cell static and animated grids | Both outputs decoded at the requested 640 × 360 canvas size |
| 100-cell animated grid | Generated through staged row composition and decoded at 640 × 360 |
| Two-second portrait source with all four outputs selected | One sample per output; four files generated, rather than repeated grids |
| Rotation-matrix MP4 | Normalized from encoded 320 × 180 to displayed 180 × 320 and generated a portrait screenshot |
| Portrait source with explicit 16:9 cells | Both contain/padding and center-crop modes generated valid 16:9 output |
| 16-cell portrait grid with an older 16:9 setting | Content-fit static and animated output filled the full 640-pixel width without outer gutters |
| Selected-list thumbnail for a rotated source | Cached JPEG decoded with the correct portrait aspect |
| Single-frame source | All four pipelines generated valid files without seeking past the only frame |

## Gallery and selected-video previews

The primary selection flow now uses Android's Photo Picker on API 33+, with an older gallery intent and document fallback on earlier versions. Selected URIs are streamed into app-private cache. The selected-video list shows a small, aspect-preserving scene JPEG alongside filename, dimensions, duration, and status; an unavailable preview uses an icon without blocking generation.

The default Save action now inserts a new MediaStore item in the public Mosaic album. API 29+ uses scoped storage with pending writes, while API 24–28 requests legacy write permission. Original gallery videos are not changed. The folder icon retains the separate document-export option. Legacy permission behavior was not manually exercised on the API 35 device.

## Manual validation status

The earlier scrcpy iteration verified the redesigned layout controls, short-source count reduction, and generation. Five intermediate UI captures are retained under `screenshots/v1.1/`; they predate the final gallery/default-content-fit additions and are historical design evidence, not screenshots of the final gallery workflow.

An earlier scrcpy attempt was interrupted by the user's Escape key. After the user requested a retry, the resumed manual session selected a real **2-minute-23-second, 720 × 1280 portrait video** through the gallery. Its scene thumbnail appeared in the selected-video list. Both a 12-cell static PNG and a 12-cell animated WebP were generated at **1280 × 1778** with original cell proportions and no outer horizontal gutters. The animated WebP was saved to `Pictures/Mosaic`; MediaStore reported a nonempty file and `is_pending=0`. The private video and its frames are not included in project documentation or release assets.

The grouped-settings revision adds eight numbered groups, explicit automatic/manual layout modes, independently stored JPEG/WebP quality and screenshot/reel counts, and output-specific disabled controls. Its 24 unit/widget tests passed. The extended physical-device native test also generated an automatic 20-cell grid while retaining the independently stored manual 2-column/3-row settings.

Final build **1.1.0+4** was installed on the TB320FC. Through scrcpy, automatic arrangement was enabled and disabled; stored manual **4-column/3-row** values remained unchanged. Content-fit visibly disabled fixed canvas controls. With only animated sheets selected, the static-image group and reel-only controls were visibly inactive. Public-safe settings screenshots 06–09 record these states.

The remaining real-video PNG was saved through the gallery button as well. MediaStore reported **2,631,091 bytes**, `Pictures/Mosaic/`, and `is_pending=0`. The earlier animated WebP gallery copy was **3,973,224 bytes** with the same completed status. Neither private media file nor its frames are included in the repository or release archive.

The 100-cell native test uses a small output canvas to validate the composition path. It does not establish that every device can sustain maximum resolution, frame rate, and cell count simultaneously. Larger layouts are proportionally reduced to the configured area/height budgets.

## Commands

```sh
flutter analyze --no-pub
flutter test
flutter test integration_test/processor_test.dart -d <physical-device-id>
flutter test integration_test/aspect_test.dart -d <physical-device-id>
flutter build apk --release --target-platform android-arm64 --split-per-abi
```

The optional gallery test intentionally creates five synthetic files in the public Mosaic album. Run it only on API 29+ devices where scoped saving does not need a legacy permission dialog:

```sh
flutter test integration_test/gallery_test.dart -d <physical-device-id> --dart-define=MOSAIC_GALLERY_TEST=true
```

Debug tests use application ID `com.mosaicvideo.mosaic.dev`; release builds retain `com.mosaicvideo.mosaic`. Test helpers create synthetic fixtures and clean up their generated files. Signing configuration and keystore files remain excluded from Git.

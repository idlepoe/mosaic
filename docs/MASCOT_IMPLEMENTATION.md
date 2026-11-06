# Mascot implementation — stages 3, 4 and 5

## Bundled artwork

The original approved icon and six-pose concept sheet define the character identity.
Individual transparent PNGs are bundled in `assets/mascot/`:

| Asset | Use |
|---|---|
| `splash.png` | Approved icon art, reused for native splash and Flutter initialization. |
| `select.png` | Empty video queue and empty Results state. |
| `settings.png` | Small settings-header illustration and neutral cancellation feedback. |
| `loading.png` | Stationary base with an empty upper-right mosaic slot. |
| `complete.png` | Successful generation and gallery-save feedback. |
| `error.png` | Failed generation, partial failure, and selection/save/share errors. |

The PNGs are square, have true alpha, contain no UI text, and were generated with
the approved icon and concept sheet as references. Localized text stays in the
app's JSON catalogs. Decorative images are excluded from accessibility semantics;
the adjacent text communicates the actual status. Artwork stays outside video
previews, settings controls, and cancel actions. Image decoding is bounded through
cache sizes and repeated paint is isolated with repaint boundaries. A subtle
neutral halo supports outline visibility on dark surfaces.

## Loading motion

`LoadingMascot` uses a Flutter animation controller and a small code-drawn tile
layer over the separately generated base image. The 2.4-second loop moves a white
tile from the raised tentacle toward the empty upper-right slot, pauses, and
returns. It is a decorative loop, not a percentage or proof of successful output.
The actual FFmpeg progress and cancel action remain separate.

The loop stops when the widget is inactive, hidden behind another route, removed,
or when the user requests reduced motion / accessible navigation. Reduced motion
shows a stable seated tile. Completion and cancellation remove the loading pose;
partial or total video failures show the error pose instead of a success mascot.
New run summaries are resolved in the current selected language when displayed.
No animated image codec, video player, Rive runtime, or network fetch is required.

## Splash generation

The native startup screen uses the existing brand palette in light and dark mode.
Android 12 artwork is padded within the circular safe region so the head and
tentacles are not clipped. Flutter continues with a matching initialization view
while settings/results load, with no artificial minimum delay.

Regenerate native assets from the project root:

```sh
dart run tool/prepare_splash.dart
dart run flutter_native_splash:create
```

`flutter_native_splash.yaml` configures Android only; this repository still has no
iOS application target. `tool/prepare_splash.dart` resizes and pads the approved
artwork for native packaging and does not redesign the character.

## Automated checks

The existing layout/sampling/localization/settings regression suite is retained.
Mascot tests verify separate tile movement, reduced-motion stability, stopping and
resuming hidden/inactive loaders, and decoding all six bundled assets. Native UI
coverage uses an actual FFmpeg-generated synthetic fixture and actual encoding;
the gallery-channel selection response and import error are injected to make the
UI test deterministic without accessing personal videos.


## Final verification (November 6, 2026)

- Flutter analysis passed with no issues.
- All 40 unit/widget tests passed, including three languages, 160% text, light and
  dark mode, 320 × 568 and 800 × 360 layouts, startup readiness and animation control.
- The mascot/decoding/layout subset was rechecked after making decode sizes follow
  device pixel ratio, bounded at 128–640 pixels.
- The native UI integration test passed on SM-S931N / Android 16 (API 36). It creates
  a 12-second synthetic source, performs actual contact-sheet and animated-sheet
  encoding, verifies two completed files and localized completion feedback, cancels
  a second job, and verifies an injected import error displays the error mascot.
- The system gallery picker itself is not automated in this smoke test. Only its
  selection response and an import error are injected; native probing and encoding
  are real. No personal gallery media is read or uploaded.
- Four processing-state screenshots were exported from the native integration
  renderer, and four final normal-app screenshots were captured through scrcpy.
  See [the screenshot index](screenshots/v1.4/README.md).
- Normal `.dev` installation was checked manually for video selection, settings,
  empty Results, and dark artwork contrast. The original night-mode setting was
  restored. The final test app opens on the video-selection screen in device-default
  Korean. The original differently-signed 1.0.0 application remains preserved.
- The integration runner removes its temporary `.dev` installation after testing;
  the normal debug build was installed again for manual review. Synthetic test
  sources and outputs were cleaned up by the test.
- Debug and ARM64 release builds succeeded. The release reports version 1.4.0 /
  Android version code 2009 and uses the existing release certificate. Its APK is
  about 61.2 MB, including the native engine and bundled artwork/splash densities.

The native integration test is `integration_test/mascot_flow_test.dart`:

```sh
flutter test integration_test/mascot_flow_test.dart -d DEVICE_SERIAL
```

The optional `--dart-define=MOSAIC_RECORD_UI=true` records renderer snapshots in the
test app's external `mascot-evidence` folder and in the binding's screenshot report.
Collect external files while the runner is active or use a host screenshot callback,
since Android removes that directory when the integration runner uninstalls its app.

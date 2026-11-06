# Mascot screens — version 1.4

All captures were made on the physical SM-S931N / Android 16 on November 6, 2026.
The original differently-signed legacy app is preserved. Validation used a separate
`.dev` app. No personal video frames appear in these captures.

## Normal app, captured through scrcpy

| File | Evidence |
|---|---|
| [01-videos.jpg](01-videos.jpg) | Inviting empty-queue mascot and compact actions. |
| [02-settings.jpg](02-settings.jpg) | Small settings-header mascot, separate from controls. |
| [03-empty-results.jpg](03-empty-results.jpg) | Reused empty-frame artwork. |
| [04-dark-results.jpg](04-dark-results.jpg) | True transparency and artwork contrast in dark mode. |

## Native automated UI snapshots

These are Flutter integration-test renderer captures on the physical phone, not
scrcpy window captures. The generated color-bar video is a synthetic fixture.

| File | Evidence |
|---|---|
| [native/01-loading.png](native/01-loading.png) | Moving-tile loading mascot alongside actual progress and cancellation. |
| [native/02-complete.png](native/02-complete.png) | Success pose after two real output files were generated. |
| [native/03-results.png](native/03-results.png) | Generated test results retain their normal preview area. |
| [native/04-cancelled.png](native/04-cancelled.png) | Neutral feedback and no loader after cancellation. |

The same test verified the import-error pose and message. Its final error snapshot
was not exported before the integration runner removed its test application.
Native splash resources include Android 12 circle-safe artwork and both brightness
variants; startup readiness and the Flutter splash are covered by widget tests.

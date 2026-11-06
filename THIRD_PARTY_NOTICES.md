# Third-party notices

## Mosaic

Reference implementation: https://github.com/mosaicvideo/mosaic

Copyright (c) 2026 Mosaic contributors. MIT license; full text in LICENSE.
The Flutter port follows Mosaic's four-output workflow, interval sampling,
clip start bounds, aspect-ratio normalization and collision-safe file naming.

## FFmpegKit full

Flutter package: https://pub.dev/packages/ffmpeg_kit_flutter_new_full

Native artifact: com.antonkarpenko:ffmpeg-kit-full:2.2.3

Upstream fork/source and build instructions are linked from the package page.
FFmpegKit is LGPL-3.0-or-later; FFmpeg and bundled third-party components retain
their own licenses. This project selects the full package without the optional
GPL encoder bundle. It does not claim that the MIT license covers these binaries.
Before distributing an APK, retain applicable notices and provide the exact
corresponding native sources/build changes and relinking materials required by
the included components' licenses. Flutter's in-app license page lists registered
Dart package notices; it is not a substitute for native distribution materials.

Other dependencies and their pinned resolved versions are in pubspec.lock.

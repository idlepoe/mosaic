# Launcher icon update (1.2.1)

The selected rough cartoon octopus illustration is now the Android app icon.
The octopus peeks from the upper-left of the original green four-tile Mosaic mark.

- Source: `assets/icon/mosaic_octopus.png` (transparent PNG).
- Generator: `flutter_launcher_icons` 0.14.4, pinned as a development dependency.
- Configuration: `flutter_launcher_icons.yaml`.
- Android manifest: `@mipmap/ic_launcher`.
- Generated assets: legacy mipmaps for five densities and adaptive foregrounds for five densities.
- Adaptive background: `#F4F8F5`; foreground inset: 26% to retain the full mascot inside launcher masks.
- iOS generation remains disabled until an iOS application target is added.

Regenerate from the project root with `dart run flutter_launcher_icons`.
The generated launcher image was visually inspected. Flutter analysis passed.
No physical Android device or scrcpy window was connected during this update,
so the installed launcher appearance was not verified on a device.

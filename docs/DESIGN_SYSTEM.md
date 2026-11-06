# Design system: stage 1 (1.3.0)

The first design stage introduces real Flutter ShadcnUI (`shadcn_ui` 0.57.4)
components and a shared brand palette, without adding new mascot artwork or
animations to app screens.

## Color roles

| Role | Light color | Use |
|---|---|---|
| Primary | `#8B3DCC` | Generate, selected controls, active navigation, progress, focus |
| Secondary action | `#008768` | Save to gallery |
| Accent | `#B6F5DC` | Layout summary and supporting highlights |
| Background | `#F7F5EF` | Main canvas |
| Foreground | `#291337` | Text and icons |

Dark mode uses a deep purple-neutral canvas, lighter purple actions, mint saving
controls, and separate readable muted, border, and destructive colors. Theme tokens
live in `lib/ui/studio_theme.dart`. Visual selection also uses borders, icons, or
semantic selected state, rather than relying only on color.

## Components and behavior

- ShadButton-backed actions and choices, ShadSwitch, ShadSlider, ShadSelect, ShadInput.
- ShadCard panels and ShadAccordion settings groups with retained child state.
- ShadDialog for language choice, video metadata, and deletion confirmation.
- ShadProgress with actual generation progress and a separate cancel action.
- A compact three-destination bottom bar built from shadcn buttons and Lucide icons.
- Rounded 8–12 px component outlines, restrained surfaces, and consistent spacing.
- Existing Flutter navigation, Android gallery/storage bridges, and license dialog
  remain integrated through a matching platform shell. This is a component migration,
  not the original web shadcn/ui code or a WebView.
- Long translated labels wrap; mutually exclusive modes and disabled settings keep
  their existing behavior. Language preference remains separate from output settings.
- Generated image dimensions, colors, timestamps, and processing pipelines are not
  changed by the UI theme.

## Automated validation

`flutter analyze --no-pub` passed without issues. All 33 tests passed, including
layout and sampling regressions, mode independence, three-language live switching,
and scrolling all settings at 360 × 800 with 160% text in both light and dark mode.
The shadcn package's deferred translations are preloaded outside fake async zones
in widget tests; the app uses the package's normal localization delegate.


## Physical-device validation (November 6, 2026)

The connected SM-S931N (Android 16 / API 36, serial `R3CY90B606E`) was operated
through scrcpy. Its installed 1.0.0 app uses a different signing certificate,
so an in-place release update was rejected by Android. The existing app and its
files were preserved. The same 1.3.0 source was installed as the separate debug
application `com.mosaicvideo.mosaic.dev` for UI validation.

Verified on the physical device:

- Videos, Settings, and empty Results screens render with the new visual system.
- Source/portrait aspect choices update the layout and cropping applicability.
- Automatic arrangement enables presets and disables manual controls; switching
  back preserves the original 3 × 4 manual arrangement.
- Choosing PNG disables JPEG quality while retaining the previous quality value.
- The language dialog switches the app to English; System default restores Korean.
- Both light and dark themes render correctly. The device's original night-mode
  setting (`no`) was restored after testing.

Ten safe UI screenshots are stored in [screenshots/v1.3](screenshots/v1.3/README.md).
They contain only empty states and synthetic layout previews. No personal videos
were imported for this visual update. Video encoding and gallery export were not
rerun in this stage because their implementations were unchanged.

Both debug and ARM64 release APKs built successfully. The release APK reports
1.3.0 / Android version code 2007 and verifies against the existing release
certificate. Devices already using that release certificate can update normally;
the older development-signed installation on this test phone cannot be updated
in place with that APK.

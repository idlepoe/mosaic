# Localization

Version 1.2.0 adds Korean (`ko`), English (`en`), and Japanese (`ja`).

## Behavior

- First launch follows the device's preferred supported language; English is the fallback.
- The app bar's language button offers System default, 한국어, English, and 日本語.
- A manual choice applies immediately and is stored under `app_language` in SharedPreferences.
- Language is independent of generation settings; the queue, results, and video options remain in place.
- Queue statuses are resolved when displayed, so they update with the language.
- Native channel error codes map to translated guidance rather than displaying raw native messages.
- Native Android picker language is controlled by the OS. File names, codec identifiers, and FFmpeg diagnostics retain their original text.
- Existing generated images retain their content. The generation and gallery-saving algorithms are unchanged.

## Maintaining translations

Edit `lib/l10n/en.json`, `ko.json`, and `ja.json`. Use the same semantic keys and numbered placeholders in every language. A placeholder may move to match the language's word order. Never translate identifiers, file paths, or format values.

Run:

```sh
dart run tool/generate_localizations.dart
dart format lib/l10n/catalogs.dart
flutter analyze
flutter test
```

Commit both JSON sources and the generated Dart catalog. The generator validates missing keys, empty values, and placeholder mismatches. The app loads the compiled catalog without extra startup IO. Flutter's SDK localization delegates provide translated Material/Cupertino dialogs.

## Verification

Automated tests cover catalog parity, placeholder safety, regional locale resolution,
English fallback, preference persistence, queue statuses, native error mapping, and
live language switching at 360 × 800 in all three languages. Existing layout,
sampling, and independent-settings tests remain part of the full test suite.


### Physical-device verification (November 6, 2026)

The release-signed ARM64 APK (1.2.0, version code 2005) was installed as an update
on TB320FC / Android API 35, connected as `HA20FDN6` and operated through scrcpy.
Korean, English, and Japanese rendered correctly. Live switching kept the current
Settings tab, selected animated-sheet output, and saved 4 × 3 arrangement intact.
English remained selected after force-stopping and relaunching the app. Returning
to System default restored Korean on this device. Five UI screenshots are saved
in [screenshots/v1.2](screenshots/v1.2/README.md); they contain no personal video frames.

`flutter analyze --no-pub` passed with no issues, and `flutter test` passed all 31
tests. This localization update did not rerun video encoding integration tests;
the generation pipelines were previously validated for 1.1 and were not changed.
The APK signature was verified against the existing release certificate.

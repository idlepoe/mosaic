import 'dart:ui';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'catalogs.dart';

/// App-wide locale, also available to processing code without a BuildContext.
class AppLanguage extends ValueNotifier<Locale?> {
  AppLanguage._() : super(null);
  static final instance = AppLanguage._();
  static const supported = [Locale('ko'), Locale('en'), Locale('ja')];
  static const preferenceKey = 'app_language';
  String get code =>
      resolve(value, PlatformDispatcher.instance.locales).languageCode;

  static Locale resolve(Locale? override, List<Locale> deviceLocales) {
    if (override != null && supported.contains(Locale(override.languageCode))) {
      return Locale(override.languageCode);
    }
    for (final locale in deviceLocales) {
      final language = Locale(locale.languageCode);
      if (supported.contains(language)) return language;
    }
    return const Locale('en');
  }

  Future<void> load() async {
    try {
      final code = (await SharedPreferences.getInstance()).getString(
        preferenceKey,
      );
      value = supported.where((l) => l.languageCode == code).firstOrNull;
    } catch (_) {
      value = null;
    }
  }

  Future<void> select(Locale? locale) async {
    final prefs = await SharedPreferences.getInstance();
    if (locale == null) {
      await prefs.remove(preferenceKey);
    } else {
      await prefs.setString(preferenceKey, locale.languageCode);
    }
    value = locale;
  }

  void deviceLocalesChanged() {
    if (value == null) notifyListeners();
  }
}

String tr(String key, [List<Object?> arguments = const []]) {
  final text =
      translations[AppLanguage.instance.code]?[key] ?? translations['en']?[key];
  if (text == null) {
    throw ArgumentError.value(key, 'key', 'Missing translation');
  }
  // A single pass prevents file names containing {0} from being substituted again.
  return text.replaceAllMapped(RegExp(r'\{(\d+)\}'), (match) {
    final index = int.parse(match[1]!);
    return index < arguments.length ? '${arguments[index]}' : match[0]!;
  });
}

/// Native diagnostics are kept out of user-facing text and do not leak paths.
String errorText(Object error) {
  if (error is PlatformException) {
    return tr(switch (error.code) {
      'BUSY' => 'nativeBusy',
      'IMPORT' => 'nativeImport',
      'INVALID' => 'nativeInvalid',
      'PERMISSION' => 'nativePermission',
      'GALLERY' || 'EXPORT' || 'SAVE' => 'nativeSave',
      'PICK' => 'nativePick',
      _ => 'nativeUnknown',
    });
  }
  if (error is FormatException) return error.message;
  return '$error'.replaceFirst(RegExp(r'^Exception: '), '');
}

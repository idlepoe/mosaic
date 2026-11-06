import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

/// Shared brand tokens for shadcn controls and the platform navigation shell.
abstract final class StudioTheme {
  static const purple = Color(0xff8b3dcc);
  static const green = Color(0xff008768);
  static const mint = Color(0xffb6f5dc);
  static const cream = Color(0xfff7f5ef);
  static const ink = Color(0xff291337);

  static ShadColorScheme colors(Brightness brightness) {
    final dark = brightness == Brightness.dark;
    final background = dark ? const Color(0xff17131d) : cream;
    final foreground = dark ? const Color(0xfff4edf8) : ink;
    final card = dark ? const Color(0xff221c2a) : Colors.white;
    final border = dark ? const Color(0xff44384f) : const Color(0xffded7e4);
    return ShadColorScheme(
      background: background,
      foreground: foreground,
      card: card,
      cardForeground: foreground,
      popover: card,
      popoverForeground: foreground,
      primary: dark ? const Color(0xffc995f5) : purple,
      primaryForeground: dark ? ink : Colors.white,
      secondary: dark ? const Color(0xff30253b) : const Color(0xffeee6f5),
      secondaryForeground: foreground,
      muted: dark ? const Color(0xff2a2331) : const Color(0xfff1edf3),
      mutedForeground: dark ? const Color(0xffbfb1c9) : const Color(0xff72647d),
      accent: dark ? const Color(0xff173f35) : mint,
      accentForeground: dark ? mint : const Color(0xff004f3c),
      destructive: dark ? const Color(0xffffa8a8) : const Color(0xffb42338),
      destructiveForeground: dark ? const Color(0xff43131c) : Colors.white,
      border: border,
      input: border,
      ring: dark ? const Color(0xffc995f5) : purple,
      selection: dark ? const Color(0xff503369) : const Color(0xffe9d9f5),
    );
  }

  static ShadThemeData shad(Brightness brightness) => ShadThemeData(
    brightness: brightness,
    colorScheme: colors(brightness),
    radius: BorderRadius.circular(10),
    primaryButtonTheme: const ShadButtonTheme(height: 48),
    outlineButtonTheme: const ShadButtonTheme(height: 44),
    ghostButtonTheme: const ShadButtonTheme(height: 44),
    switchTheme: const ShadSwitchTheme(width: 40, height: 24),
  );

  static ThemeData material(Brightness brightness) {
    final c = colors(brightness);
    final scheme =
        ColorScheme.fromSeed(
          seedColor: purple,
          brightness: brightness,
        ).copyWith(
          primary: c.primary,
          onPrimary: c.primaryForeground,
          secondary: brightness == Brightness.dark ? mint : green,
          onSecondary: brightness == Brightness.dark ? ink : Colors.white,
          secondaryContainer: c.accent,
          onSecondaryContainer: c.accentForeground,
          primaryContainer: c.secondary,
          onPrimaryContainer: c.secondaryForeground,
          surface: c.card,
          onSurface: c.foreground,
          surfaceContainerLow: c.card,
          surfaceContainerHigh: c.muted,
          outline: c.mutedForeground,
          outlineVariant: c.border,
          error: c.destructive,
        );
    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      scaffoldBackgroundColor: c.background,
      splashFactory: NoSplash.splashFactory,
      appBarTheme: AppBarTheme(
        backgroundColor: c.background,
        foregroundColor: c.foreground,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          color: c.foreground,
          fontSize: 22,
          fontWeight: FontWeight.w800,
          letterSpacing: -.7,
        ),
        shape: Border(bottom: BorderSide(color: c.border)),
      ),
      cardTheme: CardThemeData(
        color: c.card,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        margin: const EdgeInsets.only(bottom: 12),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: BorderSide(color: c.border),
        ),
      ),
      dividerColor: c.border,
      dialogTheme: DialogThemeData(
        backgroundColor: c.popover,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: c.border),
        ),
      ),
      textTheme: ThemeData(
        brightness: brightness,
      ).textTheme.apply(bodyColor: c.foreground, displayColor: c.foreground),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: c.foreground,
          borderRadius: BorderRadius.circular(6),
        ),
        textStyle: TextStyle(color: c.background, fontSize: 12),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: c.foreground,
        contentTextStyle: TextStyle(color: c.background),
        behavior: SnackBarBehavior.floating,
      ),
      iconTheme: IconThemeData(color: c.foreground, size: 20),
      listTileTheme: ListTileThemeData(
        iconColor: c.mutedForeground,
        titleTextStyle: TextStyle(
          color: c.foreground,
          fontSize: 14,
          fontWeight: FontWeight.w600,
        ),
        subtitleTextStyle: TextStyle(
          color: c.mutedForeground,
          fontSize: 12,
          height: 1.5,
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:mosaic/ui/studio_theme.dart';

class StudioTestApp extends StatelessWidget {
  final Widget home;
  const StudioTestApp({super.key, required this.home});
  @override
  Widget build(BuildContext context) => ShadApp.custom(
    theme: StudioTheme.shad(Brightness.light),
    appBuilder: (context) => MaterialApp(
      theme: StudioTheme.material(Brightness.light),
      localizationsDelegates: const [
        GlobalShadLocalizations.delegate,
        ...GlobalMaterialLocalizations.delegates,
      ],
      builder: (context, child) => ShadAppBuilder(child: child!),
      home: home,
    ),
  );
}

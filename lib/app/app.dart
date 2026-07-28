import 'dart:async';

import 'package:bilibili_player/app/home_page.dart';
import 'package:bilibili_player/app/system_presentation.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';

import 'design/app_visual_theme.dart';

class BilibiliPlayerApp extends StatefulWidget {
  const BilibiliPlayerApp({super.key});

  @override
  State<BilibiliPlayerApp> createState() => _BilibiliPlayerAppState();
}

class _BilibiliPlayerAppState extends State<BilibiliPlayerApp>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(refreshBiliAppPreferredOrientationsIfActive());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(refreshBiliAppPreferredOrientationsIfActive());
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final lightTheme = AppVisualTokens.lightTheme();
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Bilibili Player',
      builder: (context, child) => AnnotatedRegion<SystemUiOverlayStyle>(
        value: biliAppSystemUiStyle,
        child: child ?? const SizedBox.shrink(),
      ),
      theme: lightTheme.copyWith(
        appBarTheme: lightTheme.appBarTheme.copyWith(
          systemOverlayStyle: biliAppSystemUiStyle,
        ),
      ),
      darkTheme: AppVisualTokens.darkTheme(),
      home: const HomePage(),
    );
  }
}

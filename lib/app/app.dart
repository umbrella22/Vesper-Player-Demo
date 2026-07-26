import 'package:bilibili_player/app/home_page.dart';
import 'package:bilibili_player/app/system_presentation.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';

import 'design/app_visual_theme.dart';

class BilibiliPlayerApp extends StatelessWidget {
  const BilibiliPlayerApp({super.key});

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

import 'dart:io';

import 'package:bilibili_player/app/design/app_glass_controls.dart';
import 'package:bilibili_player/app/design/app_visual_theme.dart';
import 'package:bilibili_player/bili/common/services/bili_app_settings.dart';
import 'package:bilibili_player/bili/common/widgets/bili_glass_sheet.dart';
import 'package:bilibili_player/bili/tv_mode/widgets/tv_directional_focus_scope.dart';
import 'package:bilibili_player/bili/tv_mode/widgets/tv_focusable.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';
import 'package:material_ui/material_ui.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('visual theme uses blue primary and a single source pink token', () {
    final theme = AppVisualTokens.lightTheme();

    expect(theme.colorScheme.primary, AppVisualTokens.primaryBlue);
    expect(AppVisualTokens.primaryBlue, const Color(0xFF409EFF));
    expect(AppVisualTokens.biliSourcePink, const Color(0xFFFB7299));
    expect(theme.colorScheme.primary, isNot(AppVisualTokens.biliSourcePink));
    expect(theme.cardTheme.shape, isA<RoundedRectangleBorder>());
  });

  test(
    'app settings persists quality and serializes concurrent writes',
    () async {
      final root = Directory(
        '${Directory.systemTemp.path}/bili-visual-settings-${DateTime.now().microsecondsSinceEpoch}',
      );
      final first = BiliAppSettings(baseDirectory: root);
      final second = BiliAppSettings(baseDirectory: root);
      addTearDown(() async {
        if (await root.exists()) {
          await root.delete(recursive: true);
        }
      });

      await Future.wait<void>([
        first.setForceTvMode(true),
        second.setGlassQuality(GlassQuality.minimal),
      ]);

      expect(await first.getForceTvMode(), isTrue);
      expect(await second.getGlassQuality(), GlassQuality.minimal);

      final file = File('${root.path}/bili-app-settings.json');
      await file.writeAsString('{"glassQuality":"unknown"}');
      expect(await first.getGlassQuality(), isNull);
    },
  );

  testWidgets('glass dialog returns its typed action value', (tester) async {
    bool? result;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppVisualTokens.lightTheme(),
        home: Builder(
          builder: (context) => FilledButton(
            onPressed: () async {
              result = await showBiliGlassDialog<bool>(
                context: context,
                title: '确认',
                message: '继续操作？',
                actions: const [
                  BiliGlassDialogAction(label: '取消', value: false),
                  BiliGlassDialogAction(
                    label: '继续',
                    value: true,
                    isPrimary: true,
                  ),
                ],
              );
            },
            child: const Text('打开'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('打开'));
    await tester.pump(const Duration(milliseconds: 240));
    expect(find.byType(GlassDialog), findsOneWidget);

    await tester.tap(
      find.descendant(of: find.byType(GlassDialog), matching: find.text('继续')),
    );
    await tester.pump(const Duration(milliseconds: 240));

    expect(result, isTrue);
  });

  testWidgets('glass sheet constrains tall content and returns a value', (
    tester,
  ) async {
    String? result;
    await tester.binding.setSurfaceSize(const Size(390, 640));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        theme: AppVisualTokens.lightTheme(),
        home: Builder(
          builder: (context) => FilledButton(
            onPressed: () async {
              result = await showBiliGlassSheet<String>(
                context: context,
                maxContentHeightFactor: 0.5,
                builder: (sheetContext) => SizedBox(
                  height: 1000,
                  child: Align(
                    alignment: Alignment.topCenter,
                    child: TextButton(
                      onPressed: () => Navigator.of(sheetContext).pop('done'),
                      child: const Text('完成'),
                    ),
                  ),
                ),
              );
            },
            child: const Text('打开'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('打开'));
    await tester.pump(const Duration(milliseconds: 240));
    expect(find.byType(GlassSheet), findsOneWidget);
    expect(tester.takeException(), isNull);
    expect(
      tester.getSize(find.byType(GlassSheet)).height,
      lessThanOrEqualTo(360),
    );

    await tester.tap(find.text('完成'));
    await tester.pump(const Duration(milliseconds: 240));
    expect(result, 'done');
  });

  testWidgets('reduced motion resolves shared transitions to zero', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(disableAnimations: true),
          child: Builder(
            builder: (context) => Text(
              '${AppVisualTokens.motionDuration(context, AppVisualTokens.overlayDuration).inMilliseconds}',
            ),
          ),
        ),
      ),
    );

    expect(find.text('0'), findsOneWidget);
  });

  testWidgets('section tabs match bottom glass with a neutral selection', (
    tester,
  ) async {
    var selectedIndex = 0;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppVisualTokens.lightTheme(),
        home: Scaffold(
          body: AppGlassSectionTabs(
            selectedIndex: selectedIndex,
            onSelected: (index) => selectedIndex = index,
            items: const [
              AppGlassNavigationItem(
                label: '关注',
                icon: Icons.people_alt_outlined,
              ),
              AppGlassNavigationItem(
                label: '历史播放',
                icon: Icons.history_rounded,
              ),
              AppGlassNavigationItem(
                label: '稍后再看',
                icon: Icons.watch_later_outlined,
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pump();

    final tabs = tester.widget<GlassTabBar>(find.byType(GlassTabBar));
    expect(tabs.quality, GlassQuality.premium);
    expect(tabs.indicatorColor, AppVisualTokens.neutralSelection);
    expect(tabs.selectedIconColor, AppVisualTokens.textPrimary);
    expect(tabs.selectedLabelColor, AppVisualTokens.textPrimary);
    expect(tabs.magnification, 1.12);
    expect(tabs.innerBlur, 0.5);
    expect(tabs.glowOpacity, 0.38);
    expect(tabs.pressScale, AppVisualTokens.pressedScale);

    await tester.tap(find.text('历史播放').first);
    await tester.pump();
    expect(selectedIndex, 1);
  });

  testWidgets('TV selectable keeps focus and selection as separate states', (
    tester,
  ) async {
    final firstNode = FocusNode(debugLabel: 'first');
    final secondNode = FocusNode(debugLabel: 'second');
    var activations = 0;
    addTearDown(firstNode.dispose);
    addTearDown(secondNode.dispose);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppVisualTokens.darkTheme(),
        home: TvDirectionalFocusScope(
          child: Row(
            children: [
              TvGlassSelectable(
                focusNode: firstNode,
                autofocus: true,
                debugLabel: 'first',
                onTap: () => activations += 1,
                builder: (context, state) => Text(state.name),
              ),
              const SizedBox(width: 24),
              TvGlassSelectable(
                focusNode: secondNode,
                selected: true,
                debugLabel: 'second',
                onTap: () => activations += 1,
                builder: (context, state) => Text(state.name),
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    expect(firstNode.hasFocus, isTrue);
    expect(find.text('focused'), findsOneWidget);
    expect(find.text('selected'), findsOneWidget);
    expect(
      find.byKey(const ValueKey<String>('tv-glass-focus-first')),
      findsOneWidget,
    );
    final focusedSurface = tester.widget<AnimatedContainer>(
      find.byKey(const ValueKey<String>('tv-glass-selectable-state-first')),
    );
    final selectedSurface = tester.widget<AnimatedContainer>(
      find.byKey(const ValueKey<String>('tv-glass-selectable-state-second')),
    );
    expect((focusedSurface.decoration! as BoxDecoration).color!.a, 0);
    expect((selectedSurface.decoration! as BoxDecoration).color!.a, 0);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump(const Duration(milliseconds: 200));
    expect(secondNode.hasFocus, isTrue);
    expect(find.text('focused'), findsOneWidget);
    expect(find.text('idle'), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(activations, 1);
  });

  testWidgets('top bar frosts the whole surface after scrolling', (
    tester,
  ) async {
    final controller = ScrollController();
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppVisualTokens.lightTheme(),
        home: Scaffold(
          body: Stack(
            children: [
              ListView.builder(
                controller: controller,
                itemExtent: 60,
                itemCount: 30,
                itemBuilder: (context, index) => Text('row $index'),
              ),
              AppFrostedScrollAppBar(
                scrollController: controller,
                child: const GlassAppBar(title: Text('Vesper')),
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pump();

    BoxDecoration surfaceDecoration() {
      final surface = tester.widget<DecoratedBox>(
        find.byKey(AppFrostedScrollAppBar.surfaceKey),
      );
      return surface.decoration as BoxDecoration;
    }

    expect(surfaceDecoration().color!.a, 0);

    await tester.drag(find.byType(ListView), const Offset(0, -120));
    await tester.pump();

    expect(surfaceDecoration().color!.a, greaterThan(0.8));
    expect(find.byType(BackdropFilter), findsOneWidget);
  });

  testWidgets('only one focused content glass overlay is mounted', (
    tester,
  ) async {
    final firstNode = FocusNode(debugLabel: 'content-first');
    final secondNode = FocusNode(debugLabel: 'content-second');
    addTearDown(firstNode.dispose);
    addTearDown(secondNode.dispose);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppVisualTokens.darkTheme(),
        home: TvDirectionalFocusScope(
          child: Overlay.wrap(
            child: Row(
              children: [
                SizedBox(
                  width: 180,
                  height: 120,
                  child: TvFocusableSurface(
                    focusNode: firstNode,
                    autofocus: true,
                    onTap: _noop,
                    builder: (context, focused) => const Text('first'),
                  ),
                ),
                const SizedBox(width: 24),
                SizedBox(
                  width: 180,
                  height: 120,
                  child: TvFocusableSurface(
                    focusNode: secondNode,
                    onTap: _noop,
                    builder: (context, focused) => const Text('second'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    expect(
      find.byKey(const ValueKey<String>('tv-content-glass-overlay')),
      findsOneWidget,
    );

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump(const Duration(milliseconds: 200));
    expect(secondNode.hasFocus, isTrue);
    expect(
      find.byKey(const ValueKey<String>('tv-content-glass-overlay')),
      findsOneWidget,
    );
  });

  testWidgets('shared controls fit all target viewport constraints', (
    tester,
  ) async {
    const sizes = <Size>[
      Size(360, 640),
      Size(390, 844),
      Size(1024, 1366),
      Size(1280, 720),
      Size(1920, 1080),
      Size(3840, 2160),
    ];
    addTearDown(() => tester.binding.setSurfaceSize(null));

    for (final size in sizes) {
      await tester.binding.setSurfaceSize(size);
      await tester.pumpWidget(
        MaterialApp(
          theme: AppVisualTokens.lightTheme(),
          home: const Scaffold(
            body: SafeArea(
              child: Align(
                alignment: Alignment.topCenter,
                child: Padding(
                  padding: EdgeInsets.all(16),
                  child: AppGlassButton(
                    label: '下载到本地',
                    icon: Icons.download_rounded,
                    onPressed: _noop,
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      expect(tester.takeException(), isNull, reason: 'viewport: $size');
      expect(find.text('下载到本地'), findsOneWidget);
    }
  });
}

void _noop() {}

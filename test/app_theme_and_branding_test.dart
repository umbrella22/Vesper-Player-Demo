import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';
import 'package:material_ui/material_ui.dart';
import 'package:vesper_media/app/app.dart';
import 'package:vesper_media/app/design/app_glass_controls.dart';
import 'package:vesper_media/app/design/app_theme_controller.dart';
import 'package:vesper_media/media/design/app_visual_theme.dart';
import 'package:vesper_media/app/services/app_settings_store.dart';
import 'package:vesper_media/app/system_presentation.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('app theme preferences', () {
    late Directory root;
    late AppSettingsStore settings;

    setUp(() {
      root = Directory(
        '${Directory.systemTemp.path}/vesper-theme-${DateTime.now().microsecondsSinceEpoch}',
      );
      settings = AppSettingsStore(baseDirectory: root);
    });

    tearDown(() async {
      if (await root.exists()) {
        await root.delete(recursive: true);
      }
    });

    test('persists all three values and falls back to system', () async {
      expect(await settings.getThemePreference(), AppThemePreference.system);

      for (final preference in AppThemePreference.values) {
        await settings.setThemePreference(preference);
        expect(await settings.getThemePreference(), preference);
      }

      final file = File('${root.path}/vesper-app-settings.json');
      await file.writeAsString('{"themePreference":"future-theme"}');
      expect(await settings.getThemePreference(), AppThemePreference.system);
    });

    test(
      'corrupt settings fall back and the next write repairs the file',
      () async {
        await root.create(recursive: true);
        final file = File('${root.path}/vesper-app-settings.json');
        await file.writeAsString('{"forceTvMode":');

        final snapshot = await settings.loadSnapshot();

        expect(snapshot.forceTvMode, isFalse);
        expect(snapshot.glassQuality, isNull);
        expect(snapshot.themePreference, AppThemePreference.system);
        expect(
          snapshot.danmakuSettings,
          AppSettingsSnapshot.defaults.danmakuSettings,
        );

        await settings.setForceTvMode(true);

        final repaired = jsonDecode(await file.readAsString()) as Map;
        expect(repaired['forceTvMode'], isTrue);
      },
    );

    test(
      'invalid force TV representation falls back without throwing',
      () async {
        await root.create(recursive: true);
        final file = File('${root.path}/vesper-app-settings.json');
        await file.writeAsString('{"forceTvMode":"true"}');

        expect((await settings.loadSnapshot()).forceTvMode, isFalse);
      },
    );

    test('controller maps preferences and persists changes', () async {
      final controller = AppThemeController(settings: settings);
      addTearDown(controller.dispose);

      expect(controller.preference, AppThemePreference.system);
      expect(controller.themeMode, ThemeMode.system);

      await controller.setPreference(AppThemePreference.light);
      expect(controller.themeMode, ThemeMode.light);
      expect(await settings.getThemePreference(), AppThemePreference.light);

      await controller.setPreference(AppThemePreference.dark);
      expect(controller.themeMode, ThemeMode.dark);
      expect(await settings.getThemePreference(), AppThemePreference.dark);
    });

    test('light, dark, and TV themes retain their intended surfaces', () {
      final light = AppVisualTokens.mobileLightTheme();
      final dark = AppVisualTokens.mobileDarkTheme();
      final tv = AppVisualTokens.tvTheme();

      expect(light.scaffoldBackgroundColor, const Color(0xFFF4F6F8));
      expect(dark.scaffoldBackgroundColor, const Color(0xFF111318));
      expect(tv.brightness, Brightness.dark);
      expect(tv.scaffoldBackgroundColor, const Color(0xFF111318));
      expect(light.colorScheme.primary, const Color(0xFF409EFF));
      expect(dark.colorScheme.primary, const Color(0xFF409EFF));
    });
  });

  test('system bars follow the resolved app brightness', () {
    final light = appSystemUiStyleForBrightness(Brightness.light);
    final dark = appSystemUiStyleForBrightness(Brightness.dark);

    expect(light.statusBarColor, Colors.transparent);
    expect(light.systemNavigationBarColor, Colors.transparent);
    expect(light.statusBarIconBrightness, Brightness.dark);
    expect(light.systemNavigationBarIconBrightness, Brightness.dark);
    expect(dark.statusBarIconBrightness, Brightness.light);
    expect(dark.systemNavigationBarIconBrightness, Brightness.light);
    expect(dark, biliTvSystemUiStyle);
  });

  testWidgets(
    'high contrast navigation replaces glass with an opaque surface',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppVisualTokens.mobileLightHighContrastTheme(),
          home: MediaQuery(
            data: const MediaQueryData(highContrast: true),
            child: Scaffold(
              body: AppGlassBottomNavigation(
                selectedIndex: 0,
                onSelected: (_) {},
                items: const [
                  AppGlassNavigationItem(
                    label: '首页',
                    icon: Icons.home_outlined,
                  ),
                  AppGlassNavigationItem(
                    label: '我的',
                    icon: Icons.person_outline_rounded,
                  ),
                ],
              ),
            ),
          ),
        ),
      );

      expect(find.byType(GlassTabBar), findsNothing);
      final opaqueSurfaces = tester
          .widgetList<Material>(find.byType(Material))
          .where((material) => material.color == Colors.white);
      expect(opaqueSurfaces, isNotEmpty);
      expect(
        tester
            .widgetList<Semantics>(find.byType(Semantics))
            .any((semantics) => semantics.properties.selected == true),
        isTrue,
      );
    },
  );

  testWidgets(
    'high contrast navigation supports minimize and two-stage search',
    (tester) async {
      final queryController = TextEditingController();
      final focusNode = FocusNode();
      final scrollController = ScrollController();
      final minimizeController = GlassTabBarMinimizeController(
        behavior: GlassBarMinimizeBehavior.onScrollDown,
      );
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox.shrink());
        queryController.dispose();
        focusNode.dispose();
        scrollController.dispose();
        minimizeController.dispose();
      });
      var searchActive = false;

      await tester.binding.setSurfaceSize(const Size(320, 600));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        MaterialApp(
          theme: AppVisualTokens.mobileLightHighContrastTheme(),
          home: MediaQuery(
            data: const MediaQueryData(highContrast: true),
            child: StatefulBuilder(
              builder: (context, setState) {
                void setSearchActive(bool active) {
                  setState(() {
                    searchActive = active;
                    if (!active) {
                      queryController.clear();
                    }
                  });
                }

                return Scaffold(
                  body: Column(
                    children: [
                      Expanded(
                        child: ListView.builder(
                          controller: scrollController,
                          itemExtent: 48,
                          itemCount: 40,
                          itemBuilder: (_, index) => Text('项目 $index'),
                        ),
                      ),
                      AppGlassBottomNavigation(
                        selectedIndex: 0,
                        onSelected: (_) {},
                        minimizeController: minimizeController,
                        scrollController: scrollController,
                        search: AppGlassNavigationSearchConfig(
                          controller: queryController,
                          focusNode: focusNode,
                          isActive: searchActive,
                          isLoading: false,
                          onActiveChanged: setSearchActive,
                          onChanged: (_) => setState(() {}),
                          onSubmitted: (_) {},
                          onClear: () {
                            queryController.clear();
                            setState(() {});
                          },
                        ),
                        items: const [
                          AppGlassNavigationItem(
                            label: '首页',
                            icon: Icons.home_outlined,
                            activeIcon: Icons.home_rounded,
                          ),
                          AppGlassNavigationItem(
                            label: '我的',
                            icon: Icons.person_outline_rounded,
                            activeIcon: Icons.person_rounded,
                          ),
                        ],
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ),
      );

      final searchButton = find.byKey(AppGlassBottomNavigation.searchButtonKey);
      expect(find.byType(GlassTabBar), findsNothing);
      expect(
        tester.getSize(searchButton),
        const Size.square(AppGlassBottomNavigation.barHeight),
      );
      for (final label in const ['首页', '我的']) {
        final tab = find.ancestor(
          of: find.text(label),
          matching: find.byType(InkWell),
        );
        expect(
          tester.getSize(tab).width,
          AppGlassBottomNavigation.tabItemWidth,
        );
      }

      await tester.drag(find.byType(ListView), const Offset(0, -100));
      await tester.pump(const Duration(milliseconds: 200));
      expect(minimizeController.minimized, isTrue);
      expect(searchButton, findsOneWidget);

      minimizeController.expand();
      await tester.pump();
      final searchScale = find.descendant(
        of: searchButton,
        matching: find.byType(AnimatedScale),
      );
      final searchGesture = await tester.startGesture(
        tester.getCenter(searchButton),
      );
      await tester.pump();
      expect(tester.widget<AnimatedScale>(searchScale).scale, 0.96);
      await searchGesture.up();
      await tester.pump();

      final searchField = find.byKey(AppGlassBottomNavigation.searchFieldKey);
      expect(searchField, findsOneWidget);
      expect(focusNode.hasFocus, isFalse);
      expect(tester.getSize(searchField).height, greaterThanOrEqualTo(44));

      await tester.tap(searchField);
      await tester.enterText(searchField, 'flutter');
      await tester.pump();

      final dismissButton = find.byKey(
        AppGlassBottomNavigation.searchDismissButtonKey,
      );
      expect(focusNode.hasFocus, isTrue);
      expect(dismissButton, findsOneWidget);
      expect(
        tester.getSize(dismissButton).shortestSide,
        greaterThanOrEqualTo(44),
      );
      expect(
        find.byKey(AppGlassBottomNavigation.searchClearButtonKey),
        findsOneWidget,
      );

      await tester.tap(dismissButton);
      await tester.pump();

      expect(searchActive, isTrue);
      expect(focusNode.hasFocus, isFalse);
      expect(queryController.text, 'flutter');

      await tester.tap(
        find.byKey(AppGlassBottomNavigation.searchExitButtonKey),
      );
      await tester.pump();
      expect(searchActive, isFalse);
      expect(queryController.text, isEmpty);
    },
  );

  testWidgets('scroll minimization survives runtime contrast changes', (
    tester,
  ) async {
    final scrollController = ScrollController();
    final minimizeController = GlassTabBarMinimizeController(
      behavior: GlassBarMinimizeBehavior.onScrollDown,
    );
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      scrollController.dispose();
      minimizeController.dispose();
    });
    var highContrast = true;
    late StateSetter updateHost;

    await tester.pumpWidget(
      MaterialApp(
        theme: AppVisualTokens.mobileLightTheme(),
        home: StatefulBuilder(
          builder: (context, setState) {
            updateHost = setState;
            return MediaQuery(
              data: MediaQuery.of(context).copyWith(highContrast: highContrast),
              child: Scaffold(
                body: Column(
                  children: [
                    Expanded(
                      child: ListView.builder(
                        controller: scrollController,
                        itemExtent: 48,
                        itemCount: 100,
                        itemBuilder: (_, index) => Text('项目 $index'),
                      ),
                    ),
                    AppGlassBottomNavigation(
                      selectedIndex: 0,
                      onSelected: (_) {},
                      minimizeController: minimizeController,
                      scrollController: scrollController,
                      items: const [
                        AppGlassNavigationItem(
                          label: '首页',
                          icon: Icons.home_outlined,
                        ),
                        AppGlassNavigationItem(
                          label: '我的',
                          icon: Icons.person_outline_rounded,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );

    Future<void> expectMinimizesAfterDrag() async {
      await tester.drag(find.byType(ListView), const Offset(0, -100));
      await tester.pump(const Duration(milliseconds: 200));
      expect(minimizeController.minimized, isTrue);
      minimizeController.expand();
      await tester.pump();
    }

    await expectMinimizesAfterDrag();

    updateHost(() => highContrast = false);
    await tester.pump();
    await tester.pump();
    expect(find.byType(GlassTabBar), findsOneWidget);
    await expectMinimizesAfterDrag();

    updateHost(() => highContrast = true);
    await tester.pump();
    await tester.pump();
    expect(find.byType(GlassTabBar), findsNothing);
    await expectMinimizesAfterDrag();
  });

  testWidgets('bottom navigation honors reduced motion', (tester) async {
    final queryController = TextEditingController();
    final focusNode = FocusNode();
    addTearDown(() {
      queryController.dispose();
      focusNode.dispose();
    });

    await tester.pumpWidget(
      MaterialApp(
        theme: AppVisualTokens.mobileLightTheme(),
        home: MediaQuery(
          data: const MediaQueryData(disableAnimations: true),
          child: Scaffold(
            body: AppGlassBottomNavigation(
              selectedIndex: 0,
              onSelected: (_) {},
              search: AppGlassNavigationSearchConfig(
                controller: queryController,
                focusNode: focusNode,
                isActive: false,
                isLoading: false,
                onActiveChanged: (_) {},
                onChanged: (_) {},
                onSubmitted: (_) {},
                onClear: () {},
              ),
              items: const [
                AppGlassNavigationItem(label: '首页', icon: Icons.home_outlined),
                AppGlassNavigationItem(
                  label: '我的',
                  icon: Icons.person_outline_rounded,
                ),
              ],
            ),
          ),
        ),
      ),
    );

    expect(tester.widget<GlassTabBar>(find.byType(GlassTabBar)).pressScale, 1);
  });

  group('Vesper native branding contracts', () {
    test('Dart, Android, and iOS identifiers stay aligned', () async {
      final pubspec = await File('pubspec.yaml').readAsString();
      final androidGradle = await File(
        'android/app/build.gradle.kts',
      ).readAsString();
      final androidManifest = await File(
        'android/app/src/main/AndroidManifest.xml',
      ).readAsString();
      final iosProject = await File(
        'ios/Runner.xcodeproj/project.pbxproj',
      ).readAsString();
      final iosInfo = await File('ios/Runner/Info.plist').readAsString();

      expect(pubspec, startsWith('name: vesper_media\n'));
      expect(androidGradle, contains('namespace = "dev.ikaros.vesper_player"'));
      expect(
        androidGradle,
        contains('applicationId = "dev.ikaros.vesper_player"'),
      );
      expect(androidManifest, contains('android:label="Vesper"'));
      expect(androidManifest, contains('android:banner="@drawable/tv_banner"'));
      expect(
        iosProject,
        contains('PRODUCT_BUNDLE_IDENTIFIER = dev.ikaros.vesperPlayer;'),
      );
      expect(iosInfo, contains('<string>Vesper</string>'));
      expect(iosInfo, contains('<string>vesper_media</string>'));
      for (final package in const <String>[
        'vesper_player',
        'vesper_player_ui',
        'vesper_player_external_playback',
        'vesper_player_source_normalizer_ffmpeg',
        'vesper_player_remux_ffmpeg',
      ]) {
        expect(
          pubspec,
          contains(
            RegExp(
              '^  $package: \\^?\\d+\\.\\d+\\.\\d+'
              '(?:-[0-9A-Za-z.-]+)?\\s*\$',
              multiLine: true,
            ),
          ),
          reason: '$package uses a scalar hosted version constraint',
        );
      }
      expect(pubspec, isNot(contains('dependency_overrides:')));
      expect(iosProject, isNot(contains('third_party/vesper-player-sdk')));
      expect(File('.gitmodules').existsSync(), isFalse);
      expect(Directory('third_party/vesper-player-sdk').existsSync(), isFalse);
    });

    test('MethodChannel names match every native host implementation', () async {
      final androidHost = await File(
        'android/app/src/main/kotlin/dev/ikaros/vesper_player/MainActivity.kt',
      ).readAsString();
      final iosHost = await File('ios/Runner/AppDelegate.swift').readAsString();
      final channelContracts = <String, List<String>>{
        'platform': <String>[
          'lib/bili/common/services/bili_platform_info.dart',
        ],
        'device_controls': <String>[
          'lib/bili/common/services/bili_device_controls.dart',
        ],
        'storage_space': <String>[
          'lib/download/services/offline_device_storage.dart',
        ],
        'media_export': <String>[
          'lib/download/services/offline_media_exporter.dart',
        ],
      };

      for (final contract in channelContracts.entries) {
        final channel = 'dev.ikaros.vesper_player/${contract.key}';
        expect(androidHost, contains(channel), reason: 'Android: $channel');
        for (final dartPath in contract.value) {
          expect(
            await File(dartPath).readAsString(),
            contains(channel),
            reason: 'Dart: $channel',
          );
        }
      }

      for (final sharedChannel in const <String>[
        'storage_space',
        'media_export',
      ]) {
        expect(
          iosHost,
          contains('dev.ikaros.vesper_player/$sharedChannel'),
          reason: 'iOS: $sharedChannel',
        );
      }
    });

    test(
      'visible project copy no longer advertises the obsolete product',
      () async {
        final readme = await File('README.md').readAsString();
        final app = await File('lib/app/app.dart').readAsString();
        final host = VesperAppHost(homeBuilder: (_) => const SizedBox.shrink());

        expect(readme, startsWith('# Vesper\n'));
        expect(readme, isNot(contains('视频平台国际版风格')));
        expect(readme, isNot(contains('Bilibili Player')));
        expect(host.appTitle, 'Vesper');
        expect(app, contains('title: widget.host.appTitle'));
        expect(app, isNot(contains("title: 'Bilibili Player'")));
      },
    );
  });
}

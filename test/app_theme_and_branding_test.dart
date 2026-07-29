import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';
import 'package:material_ui/material_ui.dart';
import 'package:vesper_media/app/design/app_glass_controls.dart';
import 'package:vesper_media/app/design/app_theme_controller.dart';
import 'package:vesper_media/app/design/app_visual_theme.dart';
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
        'download_plugin': <String>[
          'lib/download/services/download_plugin_resolver.dart',
        ],
        'player_plugins': <String>['lib/player/player_sdk_options.dart'],
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
        'download_plugin',
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

        expect(readme, startsWith('# Vesper\n'));
        expect(readme, isNot(contains('视频平台国际版风格')));
        expect(readme, isNot(contains('Bilibili Player')));
        expect(app, contains("title: 'Vesper'"));
        expect(app, isNot(contains("title: 'Bilibili Player'")));
      },
    );
  });
}

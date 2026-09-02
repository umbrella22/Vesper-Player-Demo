import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:vesper_media/app/services/app_settings_store.dart';
import 'package:vesper_media/app/services/danmaku_settings_controller.dart';
import 'package:vesper_media/danmaku/danmaku.dart';
import 'package:vesper_media/danmaku/widgets/bili_danmaku_settings_panel.dart';
import 'package:vesper_media/media/design/app_visual_theme.dart';
import 'package:vesper_media/media/media.dart';

Directory _temporarySettingsDirectory(String name) {
  return Directory(
    '${Directory.systemTemp.path}/$name-${DateTime.now().microsecondsSinceEpoch}',
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('弹幕设置持久化', () {
    test('完整往返并保留关键词和 sender hash 原字符串', () async {
      final root = _temporarySettingsDirectory('danmaku-settings-roundtrip');
      final store = AppSettingsStore(baseDirectory: root);
      addTearDown(() async {
        if (await root.exists()) {
          await root.delete(recursive: true);
        }
      });
      const expected = BiliDanmakuSettings(
        overlay: MediaDanmakuOverlaySettings(
          enabled: false,
          opacity: 0.4,
          density: 0.6,
          fontScale: 1.3,
          displayArea: 0.5,
          showScroll: false,
          showTop: false,
          showBottom: false,
          showReverse: false,
          showCaption: false,
          showAdvanced: false,
          showColor: false,
          blockedKeywords: <String>[' Foo ', '弹 幕', 'Ａ', ' '],
        ),
        sourceFilter: BiliDanmakuSourceFilterSettings(
          minimumWeight: 7,
          blockedSenderHashes: <String>[' Hash ', 'ABC', '用户哈希'],
        ),
      );

      await store.setDanmakuSettings(expected);
      final restored = await store.getDanmakuSettings();

      expect(restored, expected);
      expect(restored.overlay.blockedKeywords, <String>[
        ' Foo ',
        '弹 幕',
        'Ａ',
        ' ',
      ]);
      expect(restored.sourceFilter.blockedSenderHashes, <String>[
        ' Hash ',
        'ABC',
        '用户哈希',
      ]);
    });

    test('错误类型和越界数值逐字段回退，合法原字符串不受影响', () async {
      final root = _temporarySettingsDirectory('danmaku-settings-invalid');
      addTearDown(() async {
        if (await root.exists()) {
          await root.delete(recursive: true);
        }
      });
      await root.create(recursive: true);
      final file = File('${root.path}/vesper-app-settings.json');
      await file.writeAsString(
        jsonEncode(<String, Object?>{
          'danmaku': <String, Object?>{
            'enabled': 'false',
            'opacity': 2,
            'density': '0.5',
            'fontScale': 0.5,
            'displayArea': 0.1,
            'showScroll': 1,
            'showTop': false,
            'showBottom': null,
            'showReverse': true,
            'showCaption': 'true',
            'showAdvanced': false,
            'showColor': true,
            'blockedKeywords': <Object?>['Valid ', 7, '', ' '],
            'minimumWeight': 3.5,
            'blockedSenderHashes': 'hash',
          },
        }),
      );

      final restored = await AppSettingsStore(
        baseDirectory: root,
      ).getDanmakuSettings();
      const defaults = BiliDanmakuSettings();

      expect(restored.overlay.enabled, defaults.overlay.enabled);
      expect(restored.overlay.opacity, defaults.overlay.opacity);
      expect(restored.overlay.density, defaults.overlay.density);
      expect(restored.overlay.fontScale, defaults.overlay.fontScale);
      expect(restored.overlay.displayArea, defaults.overlay.displayArea);
      expect(restored.overlay.showScroll, defaults.overlay.showScroll);
      expect(restored.overlay.showTop, isFalse);
      expect(restored.overlay.showBottom, defaults.overlay.showBottom);
      expect(restored.overlay.showReverse, isTrue);
      expect(restored.overlay.showCaption, defaults.overlay.showCaption);
      expect(restored.overlay.showAdvanced, isFalse);
      expect(restored.overlay.showColor, isTrue);
      expect(restored.overlay.blockedKeywords, <String>['Valid ', ' ']);
      expect(
        restored.sourceFilter.minimumWeight,
        defaults.sourceFilter.minimumWeight,
      );
      expect(restored.sourceFilter.blockedSenderHashes, isEmpty);
    });

    test('controller 冻结列表并同步发布完整、overlay 与源过滤状态', () async {
      final mutableKeywords = <String>['first'];
      final mutableHashes = <String>['hash'];
      final controller = DanmakuSettingsController(
        initialSettings: BiliDanmakuSettings(
          overlay: MediaDanmakuOverlaySettings(
            blockedKeywords: mutableKeywords,
          ),
          sourceFilter: BiliDanmakuSourceFilterSettings(
            blockedSenderHashes: mutableHashes,
          ),
        ),
      );
      addTearDown(controller.dispose);
      var completeNotifications = 0;
      var overlayNotifications = 0;
      var sourceNotifications = 0;
      controller.listenable.addListener(() => completeNotifications += 1);
      controller.overlayListenable.addListener(() => overlayNotifications += 1);
      controller.sourceFilterListenable.addListener(
        () => sourceNotifications += 1,
      );

      mutableKeywords.add('mutated');
      mutableHashes.add('mutated');
      expect(controller.value.overlay.blockedKeywords, <String>['first']);
      expect(controller.value.sourceFilter.blockedSenderHashes, <String>[
        'hash',
      ]);

      final saved = await controller.setValue(
        const BiliDanmakuSettings(
          overlay: MediaDanmakuOverlaySettings(
            opacity: 0.5,
            blockedKeywords: <String>[' Next '],
          ),
          sourceFilter: BiliDanmakuSourceFilterSettings(
            minimumWeight: 4,
            blockedSenderHashes: <String>['Next Hash'],
          ),
        ),
      );

      expect(saved, isTrue);
      expect(completeNotifications, 1);
      expect(overlayNotifications, 1);
      expect(sourceNotifications, 1);
      expect(
        () => controller.value.overlay.blockedKeywords.add('late mutation'),
        throwsUnsupportedError,
      );
      expect(
        () => controller.value.sourceFilter.blockedSenderHashes.add('late'),
        throwsUnsupportedError,
      );
    });
  });

  testWidgets('手机设置面板提供完整过滤项并在滑块松手时提交', (tester) async {
    final notifier = ValueNotifier<BiliDanmakuSettings>(
      const BiliDanmakuSettings(),
    );
    addTearDown(notifier.dispose);
    final changes = <BiliDanmakuSettings>[];

    await tester.binding.setSurfaceSize(const Size(430, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        theme: AppVisualTokens.mobileLightTheme(),
        home: Scaffold(
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: BiliDanmakuSettingsPanel(
              settings: notifier,
              onChanged: (value) {
                changes.add(value);
                notifier.value = value;
              },
            ),
          ),
        ),
      ),
    );

    for (final label in <String>[
      '显示弹幕',
      '滚动',
      '顶部',
      '底部',
      '逆向',
      '字幕',
      '高级',
      '彩色',
      '显示区域',
      '不透明度',
      '同屏密度',
      '字号',
      '云屏蔽等级',
      '关键词',
      '屏蔽用户 Hash',
    ]) {
      expect(find.text(label), findsOneWidget, reason: label);
    }

    await tester.tap(find.text('高级'));
    await tester.pump();
    expect(notifier.value.overlay.showAdvanced, isFalse);
    final advancedInkWell = find.ancestor(
      of: find.text('高级'),
      matching: find.byType(InkWell),
    );
    final advancedHitArea = tester.getSize(advancedInkWell);
    expect(advancedHitArea.width, greaterThanOrEqualTo(40));
    expect(advancedHitArea.height, greaterThanOrEqualTo(40));

    final opacitySlider = find.byType(Slider).first;
    await tester.ensureVisible(opacitySlider);
    await tester.pumpAndSettle();
    final sliderRect = tester.getRect(opacitySlider);
    final gesture = await tester.startGesture(
      Offset(sliderRect.left + sliderRect.width * 0.82, sliderRect.center.dy),
    );
    await gesture.moveTo(
      Offset(sliderRect.left + sliderRect.width * 0.3, sliderRect.center.dy),
    );
    await tester.pump();

    final draftOpacity = tester.widget<Slider>(opacitySlider).value;
    expect(draftOpacity, lessThan(0.82));
    expect(notifier.value.overlay.opacity, 0.82);

    await gesture.up();
    await tester.pump();
    expect(notifier.value.overlay.opacity, closeTo(draftOpacity, 0.001));

    final keywordField = find.byKey(
      const ValueKey<String>('danmaku-keyword-filter'),
    );
    final senderField = find.byKey(
      const ValueKey<String>('danmaku-sender-filter'),
    );
    await tester.ensureVisible(keywordField);
    await tester.enterText(keywordField, ' Foo \nfoo\n弹 幕');
    await tester.ensureVisible(senderField);
    await tester.enterText(senderField, ' Hash \nABC\n用户哈希');
    await tester.pump(const Duration(milliseconds: 400));

    expect(notifier.value.overlay.blockedKeywords, <String>[
      ' Foo ',
      'foo',
      '弹 幕',
    ]);
    expect(notifier.value.sourceFilter.blockedSenderHashes, <String>[
      ' Hash ',
      'ABC',
      '用户哈希',
    ]);
    expect(changes, isNotEmpty);
  });
}

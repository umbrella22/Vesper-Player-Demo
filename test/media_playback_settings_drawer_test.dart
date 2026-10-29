import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:vesper_media/danmaku/danmaku.dart';
import 'package:vesper_media/danmaku/widgets/bili_danmaku_settings_panel.dart';
import 'package:vesper_media/media/design/app_visual_theme.dart';
import 'package:vesper_media/media/media.dart';
import 'package:vesper_player/vesper_player.dart';

const _drawerKey = ValueKey('test-settings-drawer');
final _captureKey = GlobalKey();

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    final fontPath = Platform.environment['DRAWER_PREVIEW_FONT'];
    if (fontPath == null) return;
    final font = ByteData.sublistView(await File(fontPath).readAsBytes());
    await (FontLoader('Roboto')..addFont(Future.value(font))).load();
    await (FontLoader(
      'RemixIcon',
    )..addFont(rootBundle.load('asset/icons/remixicon.ttf'))).load();
    await (FontLoader(
      'MaterialIcons',
    )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
  });

  testWidgets(
    'quality opens at the right edge, pins its header and dismisses outside',
    (tester) async {
      await _openDrawer(tester, _qualityPanel());
      final drawer = tester.getRect(find.byKey(_drawerKey));
      expect(drawer.right, 960);
      expect(drawer.width, closeTo(960 * 0.35, 0.01));
      expect(
        Theme.of(tester.element(find.text('清晰度'))).brightness,
        Brightness.dark,
      );
      expect(find.text('（当前 1080P 高清）'), findsOneWidget);
      expect(find.text('播放策略'), findsNothing);
      await _capture(tester, 'quality');

      final header = tester.getTopLeft(find.text('清晰度'));
      await tester.drag(
        find.byKey(const ValueKey('quality-settings-scroll')),
        const Offset(0, -260),
      );
      await tester.pumpAndSettle();
      expect(tester.getTopLeft(find.text('清晰度')), header);
      await tester.tapAt(const Offset(120, 180));
      await tester.pumpAndSettle();
      expect(find.byKey(_drawerKey), findsNothing);
    },
  );

  testWidgets(
    'quality waits for success, keeps failed selections open, and disables unavailable rows',
    (tester) async {
      var result = Completer<bool>();
      final selections = <String?>[];
      await _openDrawer(
        tester,
        _qualityPanel(
          onSelect: (id) {
            selections.add(id);
            return result.future;
          },
          unavailable4k: true,
        ),
      );
      await tester.tap(find.byKey(const ValueKey('tuning-quality-120')));
      await tester.pump();
      expect(selections, isEmpty);

      final option = find.byKey(const ValueKey('tuning-quality-80'));
      await tester.ensureVisible(option);
      await tester.tap(option);
      await tester.pump();
      expect(find.byKey(_drawerKey), findsOneWidget);
      await tester.tap(option);
      expect(selections, ['80']);
      result.complete(false);
      await tester.pumpAndSettle();
      expect(find.byKey(_drawerKey), findsOneWidget);
      result = Completer<bool>();
      await tester.tap(option);
      result.complete(true);
      await tester.pumpAndSettle();
      expect(selections, ['80', '80']);
      expect(find.byKey(_drawerKey), findsNothing);
    },
  );

  testWidgets(
    'advanced settings stay in the drawer and return to the top of quality',
    (tester) async {
      await _openDrawer(tester, _qualityPanel());
      final originalRect = tester.getRect(find.byKey(_drawerKey));
      await tester.tap(
        find.byKey(const ValueKey('open-advanced-playback-settings')),
      );
      await tester.pumpAndSettle();
      expect(find.text('播放策略'), findsOneWidget);
      expect(find.text('字幕'), findsOneWidget);
      expect(tester.getRect(find.byKey(_drawerKey)), originalRect);
      await tester.drag(
        find.byKey(const ValueKey('advanced-settings-scroll')),
        const Offset(0, -280),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('返回清晰度'));
      await tester.pumpAndSettle();
      expect(find.text('自动').hitTestable(), findsOneWidget);
      await tester.drag(find.text('清晰度'), const Offset(140, 0));
      await tester.pumpAndSettle();
      expect(find.byKey(_drawerKey), findsNothing);
    },
  );

  testWidgets('late quality completion cannot close another route', (
    tester,
  ) async {
    final result = Completer<bool>();
    await _openDrawer(tester, _qualityPanel(onSelect: (_) => result.future));
    await tester.tap(find.byKey(const ValueKey('tuning-quality-auto')));
    await tester.pump();
    await tester.tap(find.byTooltip('关闭设置'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('打开'));
    await tester.pumpAndSettle();
    result.complete(true);
    await tester.pumpAndSettle();
    expect(find.byKey(_drawerKey), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'danmaku edits persist and a rightward slider drag does not dismiss',
    (tester) async {
      final settings = ValueNotifier(const BiliDanmakuSettings());
      addTearDown(settings.dispose);
      await _openDrawer(
        tester,
        BiliDanmakuSettingsPanel(
          settings: settings,
          onChanged: (value) => settings.value = value,
        ),
      );
      await _capture(tester, 'danmaku');
      await tester.tap(find.text('1/2'));
      await tester.pump();
      expect(settings.value.overlay.displayArea, 0.5);

      final opacity = find.byKey(const ValueKey('danmaku-slider-不透明度'));
      final rect = tester.getRect(opacity);
      final before = settings.value.overlay.opacity;
      final gesture = await tester.startGesture(
        Offset(rect.left + rect.width * 0.3, rect.center.dy),
      );
      await gesture.moveTo(
        Offset(rect.left + rect.width * 0.7, rect.center.dy),
      );
      await tester.pump();
      expect(settings.value.overlay.opacity, before);
      final draft = tester.widget<Slider>(opacity).value;
      await gesture.up();
      await tester.pumpAndSettle();
      expect(settings.value.overlay.opacity, draft);
      expect(find.byKey(_drawerKey), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'collapsed filters reveal above the keyboard and preserve uncommitted text on close',
    (tester) async {
      final settings = ValueNotifier(const BiliDanmakuSettings());
      addTearDown(settings.dispose);
      await _openDrawer(
        tester,
        BiliDanmakuSettingsPanel(
          settings: settings,
          onChanged: (value) => settings.value = value,
        ),
      );
      expect(find.text('关键词'), findsNothing);
      final header = tester.getTopLeft(find.text('弹幕设置'));
      await tester.ensureVisible(find.text('弹幕类型'));
      await tester.tap(find.text('弹幕类型'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('高级'));
      await tester.tap(find.text('高级'));
      await tester.pump();
      expect(settings.value.overlay.showAdvanced, isFalse);
      await tester.ensureVisible(find.text('屏蔽规则'));
      await tester.tap(find.text('屏蔽规则'));
      await tester.pumpAndSettle();
      expect(find.text('云屏蔽等级'), findsOneWidget);
      final keywords = find.byKey(const ValueKey('danmaku-keyword-filter'));
      await tester.ensureVisible(keywords);
      await tester.enterText(keywords, ' Foo \n弹 幕');
      tester.view.viewInsets = const FakeViewPadding(bottom: 180);
      await tester.pumpAndSettle();
      expect(tester.getRect(keywords).bottom, lessThanOrEqualTo(254));
      expect(tester.getTopLeft(find.text('弹幕设置')), header);
      await tester.enterText(keywords, ' Foo \n弹 幕\n新草稿');
      await tester.tap(find.byTooltip('关闭设置'));
      await tester.pumpAndSettle();
      expect(settings.value.overlay.blockedKeywords, [' Foo ', '弹 幕', '新草稿']);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'short screens with safe insets and enlarged text remain scrollable',
    (tester) async {
      await _openDrawer(
        tester,
        _qualityPanel(),
        size: const Size(740, 320),
        textScale: 1.4,
      );
      final drawer = find.byKey(_drawerKey);
      expect(tester.getRect(drawer).right, 740);
      expect(find.byTooltip('关闭设置').hitTestable(), findsOneWidget);
      await tester.ensureVisible(find.text('480P 标清'));
      await tester.pumpAndSettle();
      expect(find.text('480P 标清').hitTestable(), findsOneWidget);
      expect(find.byTooltip('关闭设置').hitTestable(), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  // 最小高度比内容高时，多余空间必须上下平分：曾经全部堆在底部，看起来
  // 像选项按钮多了一段 padding（分辨率 / 播放策略 / 倍速同款按钮都受影响）。
  for (final immersive in [false, true]) {
    testWidgets(
      '选项按钮文字在最小高度内垂直居中：immersive=$immersive',
      (tester) async {
        final button = TuningOptionButton(
          label: '1080P',
          selected: false,
          onTap: () {},
        );
        await tester.pumpWidget(
          MaterialApp(
            home: Material(
              child: Center(
                child: immersive
                    ? MediaPlaybackDrawerScope(child: button)
                    : button,
              ),
            ),
          ),
        );
        final buttonRect = tester.getRect(find.byType(TuningOptionButton));
        final textRect = tester.getRect(find.text('1080P'));
        expect(buttonRect.height, immersive ? 44 : 40);
        expect(textRect.center.dy, closeTo(buttonRect.center.dy, 0.5));
      },
    );
  }
}

Future<void> _openDrawer(
  WidgetTester tester,
  Widget content, {
  Size size = const Size(960, 434),
  double textScale = 1,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetViewInsets);
  final background = Platform.environment['DRAWER_PREVIEW_BACKGROUND'];
  final backgroundImage = background == null
      ? null
      : await tester.runAsync(() async {
          final codec = await ui.instantiateImageCodec(
            await File(background).readAsBytes(),
          );
          final frame = await codec.getNextFrame();
          codec.dispose();
          return frame.image;
        });
  if (backgroundImage != null) addTearDown(backgroundImage.dispose);
  await tester.pumpWidget(
    RepaintBoundary(
      key: _captureKey,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: AppVisualTokens.mobileLightTheme(),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: TextScaler.linear(textScale),
            padding: const EdgeInsets.only(right: 12),
          ),
          child: child!,
        ),
        home: Scaffold(
          backgroundColor: const Color(0xFF13263C),
          body: Stack(
            fit: StackFit.expand,
            children: [
              if (backgroundImage != null)
                RawImage(image: backgroundImage, fit: BoxFit.cover),
              Center(
                child: Opacity(
                  opacity: background == null ? 1 : 0,
                  child: Builder(
                    builder: (context) => TextButton(
                      onPressed: () => showMediaPlaybackSideDrawer<void>(
                        context,
                        surfaceKey: _drawerKey,
                        scrollable: false,
                        builder: (_) => content,
                      ),
                      child: const Text('打开'),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('打开'));
  await tester.pumpAndSettle();
}

MediaPlaybackTuningPanel _qualityPanel({
  Future<bool> Function(String?)? onSelect,
  bool unavailable4k = false,
}) => MediaPlaybackTuningPanel(
  snapshot: const VesperPlayerSnapshot.initial(),
  qualityOptions: [
    for (final item in const [
      ('120', '4K 超清'),
      ('116', '1080P 60帧'),
      ('80', '1080P 高清'),
      ('64', '720P 准高清'),
      ('32', '480P 标清'),
    ])
      MediaQualitySelectionOption(
        option: MediaQualityOption(
          id: item.$1,
          label: item.$2,
          tracks: const [],
        ),
        availability: unavailable4k && item.$1 == '120'
            ? MediaQualityAvailability.unavailable
            : MediaQualityAvailability.available,
        candidateTracks: const [],
      ),
  ],
  qualitySupportingTextFor: (option) => option.canSelect ? null : '当前设备不支持',
  selectedQualityOptionId: null,
  currentQualityLabel: '1080P 高清',
  codecOptions: const [
    TuningCodecOption(id: 'avc', label: 'AVC', enabled: true),
  ],
  selectedCodecIdentity: null,
  playbackRates: const [0.5, 0.75, 1, 1.25, 1.5, 2],
  subtitleTracks: const [],
  subtitleSelection: const VesperTrackSelection.auto(),
  subtitleSelectionEnabled: true,
  subtitleEmptyMessage: null,
  playbackStateLabel: '播放中',
  timelineLabel: '00:30 / 03:00',
  transportLabel: null,
  resolvedUri: null,
  onSelectQuality: onSelect ?? (_) async => true,
  onSelectCodec: (_) {},
  onSetRate: (_) {},
  onSelectSubtitle: (_) {},
);

Future<void> _capture(WidgetTester tester, String name) async {
  final output = Platform.environment['DRAWER_PREVIEW_OUTPUT'];
  if (output == null) return;
  await tester.runAsync(
    () => Future<void>.delayed(const Duration(milliseconds: 80)),
  );
  await tester.pump();
  await tester.runAsync(() async {
    final boundary =
        _captureKey.currentContext!.findRenderObject()!
            as RenderRepaintBoundary;
    final image = await boundary.toImage(pixelRatio: 2);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    await Directory(output).create(recursive: true);
    await File(
      '$output/$name-flutter.png',
    ).writeAsBytes(bytes!.buffer.asUint8List());
    image.dispose();
  });
}

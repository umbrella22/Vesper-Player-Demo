import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qr/qr.dart';
import 'package:vesper_media/bili/common/models/bili_models.dart';
import 'package:vesper_media/bili/common/widgets/bili_qr_code_view.dart';
import 'package:vesper_media/common/widgets/app_qr_code_view.dart';

QrImage _imageFor(String data) => QrImage(
  QrCode(
    payload: QrPayload.fromString(data),
    errorCorrectLevel: QrErrorCorrectLevel.medium,
  ),
);

void main() {
  group('二维码模块几何', () {
    test('短内容使用最小版本，模块数为 4n+17', () {
      final painter = AppQrCodePainter(image: _imageFor('A'));
      expect(painter.moduleCount, 21);
      expect(painter.moduleCount % 4, 1);
    });

    test('边长取整、原点对齐整像素并居中', () {
      final painter = AppQrCodePainter(image: _imageFor('A'));
      // 210/21 = 10 → 模块 10px，符号正好铺满。
      final layout = painter.layoutFor(const Size(210, 210));
      expect(layout.moduleSize, 10);
      expect(layout.side, 210);
      expect(layout.origin, Offset.zero);
      expect(layout.origin.dx, layout.origin.dx.roundToDouble());
      expect(layout.origin.dy, layout.origin.dy.roundToDouble());
      expect(layout.isValid, isTrue);
    });

    test('非正方形按短边取整并在两个方向居中', () {
      final painter = AppQrCodePainter(image: _imageFor('A'));
      // 短边 100/21 = 4.76 → 模块 4px，符号 84px，横向余 126/2 = 63。
      final layout = painter.layoutFor(const Size(210, 100));
      expect(layout.moduleSize, 4);
      expect(layout.side, 84);
      expect(layout.origin, const Offset(63, 8));
    });

    test('显式 inset 从可用边长中扣除', () {
      final painter = AppQrCodePainter(image: _imageFor('A'), inset: 10);
      // (210 - 20)/21 = 9.04 → 模块 9px，符号 189px，居中余 10.5 → 取整 11。
      final layout = painter.layoutFor(const Size(210, 210));
      expect(layout.moduleSize, 9);
      expect(layout.side, 189);
      expect(layout.origin, const Offset(11, 11));
    });

    test('容器小于模块数时不产生 0 或负数模块', () {
      final painter = AppQrCodePainter(image: _imageFor('A'));
      final layout = painter.layoutFor(const Size(15, 15));
      expect(layout.isValid, isFalse);
      expect(layout.moduleSize, 0);
    });
  });

  group('二维码矩阵', () {
    test('三个定位图案位于左上、左下、右上', () {
      final painter = AppQrCodePainter(image: _imageFor('A'));
      final last = painter.moduleCount - 1;
      // 定位图案是 7x7：外环深色、次环浅色、中心 3x3 深色。
      expect(painter.isDark(0, 0), isTrue);
      expect(painter.isDark(1, 1), isFalse);
      expect(painter.isDark(3, 3), isTrue);
      expect(painter.isDark(0, 6), isTrue);
      expect(painter.isDark(6, 0), isTrue);
      // 左下与右上：以末行/末列为基准，验证行列未颠倒。
      expect(painter.isDark(last, 0), isTrue);
      expect(painter.isDark(last - 1, 1), isFalse);
      expect(painter.isDark(0, last), isTrue);
      expect(painter.isDark(1, last - 1), isFalse);
    });
  });

  group('AppQrCodeView', () {
    testWidgets('在正方形约束内铺满并交给 painter', (tester) async {
      await tester.pumpWidget(
        const Center(
          child: SizedBox(
            width: 210,
            height: 210,
            child: AppQrCodeView(data: 'https://vesper.local/login'),
          ),
        ),
      );
      final paint = find.byType(CustomPaint);
      expect(paint, findsOneWidget);
      expect(tester.getSize(paint), const Size(210, 210));
      final painter =
          tester.widget<CustomPaint>(paint).painter as AppQrCodePainter;
      expect(painter.moduleCount, greaterThanOrEqualTo(21));
      expect(painter.layoutFor(const Size(210, 210)).isValid, isTrue);
    });

    testWidgets('空内容渲染为空方块且不抛错', (tester) async {
      await tester.pumpWidget(
        const Center(
          child: SizedBox(
            width: 120,
            height: 120,
            child: AppQrCodeView(data: ''),
          ),
        ),
      );
      expect(find.byType(CustomPaint), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('超出容量不抛错', (tester) async {
      await tester.pumpWidget(
        Center(
          child: SizedBox(
            width: 120,
            height: 120,
            child: AppQrCodeView(
              data: 'x' * 5000,
              errorCorrectLevel: QrErrorCorrectLevel.high,
            ),
          ),
        ),
      );
      expect(tester.takeException(), isNull);
      expect(find.byType(CustomPaint), findsNothing);
    });
  });

  group('BiliQrCodeView', () {
    testWidgets('加载中显示进度、无票显示占位图标', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Center(
            child: SizedBox(
              width: 160,
              height: 160,
              child: BiliQrCodeView(ticket: null, isLoading: true),
            ),
          ),
        ),
      );
      expect(find.byType(CircularProgressIndicator), findsOneWidget);

      await tester.pumpWidget(
        const MaterialApp(
          home: Center(
            child: SizedBox(
              width: 160,
              height: 160,
              child: BiliQrCodeView(ticket: null, isLoading: false),
            ),
          ),
        ),
      );
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.byType(AppQrCodeView), findsNothing);
    });

    testWidgets('有票时交给 AppQrCodeView 渲染', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Center(
            child: SizedBox(
              width: 160,
              height: 160,
              child: BiliQrCodeView(
                ticket: BiliQrLoginTicket(
                  url: 'https://passport.bilibili.com/h5-app/passport/login/scan?qrcode_key=abc',
                  qrcodeKey: 'abc',
                ),
                isLoading: false,
              ),
            ),
          ),
        ),
      );
      expect(find.byType(AppQrCodeView), findsOneWidget);
      // MaterialApp 自带一个 CustomPaint，这里只看二维码内部的绘制层。
      final paint = find.descendant(
        of: find.byType(AppQrCodeView),
        matching: find.byType(CustomPaint),
      );
      expect(paint, findsOneWidget);
      expect(
        tester.widget<CustomPaint>(paint).painter,
        isA<AppQrCodePainter>(),
      );
    });
  });
}

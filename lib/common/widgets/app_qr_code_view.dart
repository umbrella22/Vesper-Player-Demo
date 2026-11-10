import 'package:flutter/widgets.dart';
import 'package:qr/qr.dart';

/// 二维码渲染：用 `qr`（qr.dart）生成模块矩阵，自己按整像素绘制。
///
/// 取代此前依赖的 `qr_flutter`：那个包把 `qr` 锁在 3.x 且已停止维护，导致
/// 我们拿不到 4.x 的修复。这里只实现代码实际需要的形态——方形模块 + 方形
/// 定位图案 + 纯色填充；环形/圆角/嵌入 logo 这类样式不提供。
///
/// 绘制前把模块边长取整、原点对齐到整像素，避免半像素模糊导致扫码失败；
/// 模块数固定，因此符号尺寸随容器向下取整，剩余空间自动成为四周留白。
///
/// 静区（quiet zone）由调用方的白底内边距提供。默认 [inset] 为 0：整数
/// 模块本身已经吃不满容器，再叠加固定留白会把小尺寸下的模块压到 2px。
/// 确实需要额外留白时再传 [inset]。
class AppQrCodeView extends StatefulWidget {
  const AppQrCodeView({
    super.key,
    required this.data,
    this.color = const Color(0xFF111A2B),
    this.background = const Color(0xFFFFFFFF),
    this.inset = 0,
    this.errorCorrectLevel = QrErrorCorrectLevel.medium,
  });

  /// 编码内容（如登录链接）。为空时渲染空方块。
  final String data;

  /// 模块颜色。
  final Color color;

  /// 符号区域的底色；透明传 `Color(0x00000000)`。
  final Color background;

  /// 符号与控件边缘之间的额外透明留白；静区一般交给父级白底负责。
  final double inset;

  final QrErrorCorrectLevel errorCorrectLevel;

  @override
  State<AppQrCodeView> createState() => _AppQrCodeViewState();
}

class _AppQrCodeViewState extends State<AppQrCodeView> {
  QrImage? _image;

  @override
  void initState() {
    super.initState();
    _encode();
  }

  @override
  void didUpdateWidget(covariant AppQrCodeView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.data != widget.data ||
        oldWidget.errorCorrectLevel != widget.errorCorrectLevel) {
      _encode();
    }
  }

  void _encode() {
    // 内容为空或超出容量时不抛错，退化成空方块；调用方负责占位样式。
    if (widget.data.isEmpty) {
      _image = null;
      return;
    }
    try {
      _image = QrImage(
        QrCode(
          payload: QrPayload.fromString(widget.data),
          errorCorrectLevel: widget.errorCorrectLevel,
        ),
      );
    } on InputTooLongException {
      _image = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final image = _image;
    if (image == null) {
      return const SizedBox.shrink();
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        final side = constraints.biggest.shortestSide;
        if (!side.isFinite || side <= 0) {
          return const SizedBox.shrink();
        }
        return SizedBox.square(
          dimension: side,
          child: CustomPaint(
            painter: AppQrCodePainter(
              image: image,
              color: widget.color,
              background: widget.background,
              inset: widget.inset,
            ),
          ),
        );
      },
    );
  }
}

/// 单个模块的像素几何：整像素边长 + 整像素原点，居中摆放。
@immutable
final class QrCodeLayout {
  const QrCodeLayout({
    required this.moduleSize,
    required this.origin,
    required this.side,
  });

  final double moduleSize;
  final Offset origin;
  final double side;

  bool get isValid => moduleSize >= 1;
}

/// 二维码 painter。公开仅为让 widget 测试断言模块几何与矩阵读取方向。
class AppQrCodePainter extends CustomPainter {
  AppQrCodePainter({
    required this.image,
    this.color = const Color(0xFF111A2B),
    this.background = const Color(0xFFFFFFFF),
    this.inset = 0,
  });

  final QrImage image;
  final Color color;
  final Color background;
  final double inset;

  int get moduleCount => image.moduleCount;

  /// 读取第 [row] 行第 [col] 列模块（左上角为 0,0）。
  bool isDark(int row, int col) => image.isDark(row, col);

  QrCodeLayout layoutFor(Size size) {
    final available = size.shortestSide - inset * 2;
    if (available <= 0) {
      return const QrCodeLayout(
        moduleSize: 0,
        origin: Offset.zero,
        side: 0,
      );
    }
    final moduleSize = (available / image.moduleCount).floorToDouble();
    final side = moduleSize * image.moduleCount;
    return QrCodeLayout(
      moduleSize: moduleSize,
      origin: Offset(
        ((size.width - side) / 2).roundToDouble(),
        ((size.height - side) / 2).roundToDouble(),
      ),
      side: side,
    );
  }

  @override
  void paint(Canvas canvas, Size size) {
    final layout = layoutFor(size);
    if (!layout.isValid) {
      return;
    }
    if (background.a > 0) {
      canvas.drawRect(
        Rect.fromLTWH(layout.origin.dx, layout.origin.dy, layout.side, layout.side),
        Paint()..color = background,
      );
    }
    // 关闭抗锯齿：模块边缘落在整像素上，避免扫描器看到模糊边界。
    final paint = Paint()
      ..color = color
      ..isAntiAlias = false;
    for (var row = 0; row < image.moduleCount; row++) {
      for (var col = 0; col < image.moduleCount; col++) {
        if (!image.isDark(row, col)) {
          continue;
        }
        canvas.drawRect(
          Rect.fromLTWH(
            layout.origin.dx + col * layout.moduleSize,
            layout.origin.dy + row * layout.moduleSize,
            layout.moduleSize,
            layout.moduleSize,
          ),
          paint,
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant AppQrCodePainter oldDelegate) {
    return !identical(oldDelegate.image, image) ||
        oldDelegate.color != color ||
        oldDelegate.background != background ||
        oldDelegate.inset != inset;
  }
}

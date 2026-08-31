/// Shared responsive layout metrics for standard TV video-card grids.
abstract final class BiliTvVideoGridLayout {
  static const double minimumMaxCrossAxisExtent = 184;
  static const double maximumMaxCrossAxisExtent = 320;
  static const double coverDecodeLogicalWidth = maximumMaxCrossAxisExtent;
  static const double growthStartWidth = 1100;
  static const double growthEndWidth = 2600;
  static const double mainAxisSpacing = 14;
  static const double crossAxisSpacing = 16;
  static const double childAspectRatio = 1.14;
  static const double focusInset = 32;

  static double maxCrossAxisExtentFor(double crossAxisExtent) {
    assert(crossAxisExtent >= 0);
    final progress =
        ((crossAxisExtent - growthStartWidth) /
                (growthEndWidth - growthStartWidth))
            .clamp(0.0, 1.0);
    return minimumMaxCrossAxisExtent +
        (maximumMaxCrossAxisExtent - minimumMaxCrossAxisExtent) * progress;
  }

  static double tileWidthFor(
    double crossAxisExtent, {
    double maxCrossAxisExtent = minimumMaxCrossAxisExtent,
  }) {
    assert(crossAxisExtent >= 0);
    assert(maxCrossAxisExtent > 0);
    final calculatedCrossAxisCount =
        (crossAxisExtent / (maxCrossAxisExtent + crossAxisSpacing)).ceil();
    final crossAxisCount = calculatedCrossAxisCount < 1
        ? 1
        : calculatedCrossAxisCount;
    final calculatedUsableExtent =
        crossAxisExtent - crossAxisSpacing * (crossAxisCount - 1);
    final usableExtent = calculatedUsableExtent < 0
        ? 0.0
        : calculatedUsableExtent;
    return usableExtent / crossAxisCount;
  }

  static int coverCacheWidth({
    required double tileWidth,
    required double devicePixelRatio,
  }) {
    assert(tileWidth >= 0);
    assert(devicePixelRatio > 0);
    return (tileWidth * devicePixelRatio).ceil().clamp(160, 720).toInt();
  }
}

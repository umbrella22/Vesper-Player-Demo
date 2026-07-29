import 'package:vesper_media/bili/app_mode/pages/bili_hub_page.dart';
import 'package:vesper_media/bili/tv_mode/pages/bili_tv_home_page.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Bili home layout helpers', () {
    test('cover cache width follows the rendered tile pixel width', () {
      expect(biliHomeCoverCacheWidth(tileWidth: 180, devicePixelRatio: 3), 540);
      expect(
        biliHomeCoverCacheWidth(tileWidth: 266.25, devicePixelRatio: 2),
        533,
      );
    });

    test('cover cache width stays within decode bounds', () {
      expect(biliHomeCoverCacheWidth(tileWidth: 100, devicePixelRatio: 1), 160);
      expect(biliHomeCoverCacheWidth(tileWidth: 400, devicePixelRatio: 3), 720);
    });
  });

  group('Bili TV home layout helpers', () {
    test('tile width follows the max extent grid layout', () {
      expect(biliTvVideoGridTileWidthForCrossAxisExtent(184), 184);
      expect(biliTvVideoGridTileWidthForCrossAxisExtent(384), 184);
    });

    test('cover cache width follows DPR and decode bounds', () {
      expect(biliTvCoverCacheWidth(tileWidth: 176, devicePixelRatio: 3), 528);
      expect(biliTvCoverCacheWidth(tileWidth: 100, devicePixelRatio: 1), 160);
      expect(biliTvCoverCacheWidth(tileWidth: 400, devicePixelRatio: 3), 720);
    });
  });
}

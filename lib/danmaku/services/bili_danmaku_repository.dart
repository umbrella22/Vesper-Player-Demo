import 'package:flutter/foundation.dart';

import '../../bili/common/services/bili_client.dart';
import '../models/danmaku_models.dart';
import 'bili_danmaku_parser.dart';
import 'bili_danmaku_segment_parser.dart';
import 'bili_danmaku_view_parser.dart';

abstract interface class BiliDanmakuRepository {
  Future<List<BiliDanmakuEntry>> loadSegment({
    required String bvid,
    required int cid,
    required int aid,
    required int segmentIndex,
  });

  Future<List<BiliDanmakuEntry>> loadLegacyEntries({
    required String bvid,
    required int cid,
  });
}

/// Optional repository capability for mode-8/mode-9 special packages listed
/// by `DmWebViewReply.specialDms`.
abstract interface class BiliSpecialDanmakuRepository {
  Future<List<BiliDanmakuEntry>> loadSpecialEntries({
    required String bvid,
    required int cid,
    required int aid,
  });
}

final class BiliNetworkDanmakuRepository
    implements BiliDanmakuRepository, BiliSpecialDanmakuRepository {
  BiliNetworkDanmakuRepository(this._client);

  final BiliClient _client;

  @override
  Future<List<BiliDanmakuEntry>> loadSegment({
    required String bvid,
    required int cid,
    required int aid,
    required int segmentIndex,
  }) async {
    final bytes = await _client.fetchDanmakuSegment(
      bvid: bvid,
      cid: cid,
      aid: aid,
      segmentIndex: segmentIndex,
    );
    return compute(_parseSegmentInBackground, bytes);
  }

  @override
  Future<List<BiliDanmakuEntry>> loadLegacyEntries({
    required String bvid,
    required int cid,
  }) async {
    final xml = await _client.fetchDanmakuXml(bvid: bvid, cid: cid);
    return compute(_parseXmlInBackground, xml);
  }

  @override
  Future<List<BiliDanmakuEntry>> loadSpecialEntries({
    required String bvid,
    required int cid,
    required int aid,
  }) async {
    final viewBytes = await _client.fetchDanmakuView(
      bvid: bvid,
      cid: cid,
      aid: aid,
    );
    final view = await compute(_parseViewInBackground, viewBytes);
    final packages = await Future.wait(
      view.specialResourceUrls.map(
        (url) async => compute(
          _parseSegmentInBackground,
          await _client.fetchDanmakuSpecialResource(
            bvid: bvid,
            resourceUrl: url,
          ),
        ),
      ),
    );
    return List<BiliDanmakuEntry>.unmodifiable(
      packages.expand((entries) => entries),
    );
  }
}

List<BiliDanmakuEntry> _parseSegmentInBackground(List<int> bytes) {
  return const BiliDanmakuSegmentParser().parse(bytes);
}

List<BiliDanmakuEntry> _parseXmlInBackground(String xml) {
  return const BiliDanmakuParser().parse(xml);
}

BiliDanmakuView _parseViewInBackground(List<int> bytes) {
  return const BiliDanmakuViewParser().parse(bytes);
}

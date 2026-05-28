import '../../bili/common/services/bili_client.dart';
import '../models/danmaku_models.dart';
import 'bili_danmaku_parser.dart';

final class BiliDanmakuRepository {
  BiliDanmakuRepository({BiliClient? client, BiliDanmakuParser? parser})
    : _client = client ?? BiliClient.instance,
      _parser = parser ?? const BiliDanmakuParser();

  final BiliClient _client;
  final BiliDanmakuParser _parser;

  Future<List<BiliDanmakuEntry>> loadEntries({
    required String bvid,
    required int cid,
  }) async {
    final xml = await _client.fetchDanmakuXml(bvid: bvid, cid: cid);
    return _parser.parse(xml);
  }
}

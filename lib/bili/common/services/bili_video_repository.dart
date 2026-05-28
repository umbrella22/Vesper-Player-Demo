import '../models/bili_models.dart';
import 'bili_client.dart';

class BiliVideoRepository {
  BiliVideoRepository({BiliClient? client})
      : _client = client ?? BiliClient.instance;

  final BiliClient _client;
  final Map<String, BiliVideoDetail> _detailCache = <String, BiliVideoDetail>{};

  Future<BiliVideoDetail> fetchVideoDetail(String bvid) async {
    final cached = _detailCache[bvid];
    if (cached != null) {
      return cached;
    }

    final detail = await _client.fetchVideoDetail(bvid);
    _detailCache[bvid] = detail;
    return detail;
  }

  Future<BiliVideoDetail> refreshVideoDetail(String bvid) async {
    final detail = await _client.fetchVideoDetail(bvid);
    _detailCache[bvid] = detail;
    return detail;
  }

  void clearCache() {
    _detailCache.clear();
  }
}

import '../models/bili_models.dart';

/// 为“听视频”选择低带宽、跨平台兼容的标准 AAC 音轨。
final class BiliListenAudioSelector {
  const BiliListenAudioSelector();

  static const List<int> _preferredQualityIds = <int>[30280, 30232, 30216];
  static const Set<int> _specialAudioIds = <int>{30250, 30251, 30255};

  BiliDashStream? select(List<BiliDashStream> streams) {
    final candidates = streams.where(_isStandardAac).toList(growable: false);
    if (candidates.isEmpty) {
      return null;
    }
    candidates.sort((left, right) {
      final qualityCompare = _qualityPriority(
        left.id,
      ).compareTo(_qualityPriority(right.id));
      if (qualityCompare != 0) {
        return qualityCompare;
      }
      final bandwidthCompare = right.bandwidth.compareTo(left.bandwidth);
      if (bandwidthCompare != 0) {
        return bandwidthCompare;
      }
      return (left.representationId ?? '').compareTo(
        right.representationId ?? '',
      );
    });
    return candidates.first;
  }

  bool _isStandardAac(BiliDashStream stream) {
    if (!stream.isAudio || _specialAudioIds.contains(stream.id)) {
      return false;
    }
    return stream.codecs.toLowerCase().contains('mp4a');
  }

  int _qualityPriority(int qualityId) {
    final index = _preferredQualityIds.indexOf(qualityId);
    return index < 0 ? _preferredQualityIds.length : index;
  }
}

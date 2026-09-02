import 'package:material_ui/material_ui.dart';
import 'package:vesper_media/media/media.dart';

enum BiliDanmakuMode {
  scroll,
  bottom,
  top,
  reverse,
  advanced,
  code,
  bas,
  unsupported;

  static BiliDanmakuMode fromCode(int code) {
    return switch (code) {
      1 || 2 || 3 => BiliDanmakuMode.scroll,
      4 => BiliDanmakuMode.bottom,
      5 => BiliDanmakuMode.top,
      6 => BiliDanmakuMode.reverse,
      7 => BiliDanmakuMode.advanced,
      8 => BiliDanmakuMode.code,
      9 => BiliDanmakuMode.bas,
      _ => BiliDanmakuMode.unsupported,
    };
  }

  bool get isStandard => switch (this) {
    BiliDanmakuMode.scroll ||
    BiliDanmakuMode.bottom ||
    BiliDanmakuMode.top ||
    BiliDanmakuMode.reverse => true,
    BiliDanmakuMode.advanced ||
    BiliDanmakuMode.code ||
    BiliDanmakuMode.bas ||
    BiliDanmakuMode.unsupported => false,
  };
}

final class BiliDanmakuEntry {
  const BiliDanmakuEntry({
    required this.appearAtMs,
    required this.mode,
    required this.fontSize,
    required this.colorValue,
    required this.text,
    required this.rowId,
    required this.weight,
    required this.pool,
    this.senderHash = '',
  });

  final int appearAtMs;
  final BiliDanmakuMode mode;
  final double fontSize;
  final int colorValue;
  final String text;
  final String rowId;

  /// 服务端智能屏蔽权重。`null` 表示源格式没有提供或无法解码该字段，
  /// 不能将其解释为服务端明确给出的最低权重 0。
  final int? weight;

  /// Bilibili 弹幕池：0 普通、1 字幕、2 特殊。
  final int pool;

  /// 发送者 mid 的服务端哈希。身份值保持原样，仅用于精确屏蔽匹配。
  final String senderHash;

  Color get color {
    final normalized = colorValue.clamp(0, 0xFFFFFF).toInt();
    return Color(0xFF000000 | normalized);
  }
}

/// `/x/v2/dm/web/view` 中本轮需要的元数据。
final class BiliDanmakuView {
  const BiliDanmakuView({
    required this.state,
    required this.segmentPageSizeMs,
    required this.totalSegments,
    required this.specialResourceUrls,
  });

  final int state;
  final int segmentPageSizeMs;
  final int totalSegments;
  final List<String> specialResourceUrls;
}

/// Bilibili 协议层拥有的过滤条件。`weight` 和发送者 hash 不进入通用媒体
/// 事件，避免平台字段成为跨平台领域规则。
final class BiliDanmakuSourceFilterSettings {
  const BiliDanmakuSourceFilterSettings({
    this.minimumWeight = 0,
    this.blockedSenderHashes = const <String>[],
  });

  final int minimumWeight;
  final List<String> blockedSenderHashes;

  bool allows(BiliDanmakuEntry entry) {
    final weight = entry.weight;
    if (weight != null && weight < minimumWeight) {
      return false;
    }
    return entry.senderHash.isEmpty ||
        !blockedSenderHashes.contains(entry.senderHash);
  }

  BiliDanmakuSourceFilterSettings copyWith({
    int? minimumWeight,
    List<String>? blockedSenderHashes,
  }) {
    return BiliDanmakuSourceFilterSettings(
      minimumWeight: minimumWeight ?? this.minimumWeight,
      blockedSenderHashes: blockedSenderHashes ?? this.blockedSenderHashes,
    );
  }

  @override
  bool operator ==(Object other) {
    return other is BiliDanmakuSourceFilterSettings &&
        other.minimumWeight == minimumWeight &&
        _sameStrings(other.blockedSenderHashes, blockedSenderHashes);
  }

  @override
  int get hashCode =>
      Object.hash(minimumWeight, Object.hashAll(blockedSenderHashes));
}

/// 应用持久化的一组弹幕设置。通用显示规则和 B 站源过滤规则分别归属各自层。
final class BiliDanmakuSettings {
  const BiliDanmakuSettings({
    this.overlay = const MediaDanmakuOverlaySettings(),
    this.sourceFilter = const BiliDanmakuSourceFilterSettings(),
  });

  final MediaDanmakuOverlaySettings overlay;
  final BiliDanmakuSourceFilterSettings sourceFilter;

  BiliDanmakuSettings copyWith({
    MediaDanmakuOverlaySettings? overlay,
    BiliDanmakuSourceFilterSettings? sourceFilter,
  }) {
    return BiliDanmakuSettings(
      overlay: overlay ?? this.overlay,
      sourceFilter: sourceFilter ?? this.sourceFilter,
    );
  }

  @override
  bool operator ==(Object other) {
    return other is BiliDanmakuSettings &&
        other.overlay == overlay &&
        other.sourceFilter == sourceFilter;
  }

  @override
  int get hashCode => Object.hash(overlay, sourceFilter);
}

bool _sameStrings(List<String> left, List<String> right) {
  if (identical(left, right)) {
    return true;
  }
  if (left.length != right.length) {
    return false;
  }
  for (var index = 0; index < left.length; index += 1) {
    if (left[index] != right[index]) {
      return false;
    }
  }
  return true;
}

/// 兼容别名：弹幕 overlay 设置已泛化为 [MediaDanmakuOverlaySettings]（lib/media）。
typedef DanmakuOverlaySettings = MediaDanmakuOverlaySettings;

// 项目组件基座是 vendored 的 material_ui（页面与 part 共用同一套组件），
// 不直接 import flutter/material，避免 Material/InkWell 等重名冲突。
import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:vesper_media/media/capabilities/media_engagement.dart';
import 'package:vesper_media/media/design/app_visual_theme.dart';
import 'package:vesper_player_ui/vesper_player_ui.dart' as vesper_ui;

/// 设备控制（亮度/音量）的通用接口，由宿主平台实现。
///
/// 原 `_BiliStageDeviceControls`（bili 侧）实现本接口，
/// 播放页壳不再直接依赖平台设备控制服务。
abstract interface class MediaPlayerDeviceControls
    implements vesper_ui.VesperPlayerDeviceControls {}

class TuningOptionButton extends StatelessWidget {
  const TuningOptionButton({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
    this.enabled = true,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final visualTheme = AppVisualTheme.of(context);
    final color = enabled
        ? selected
              ? AppVisualTokens.primaryBlue
              : visualTheme.textPrimary
        : visualTheme.textTertiary;
    return Material(
      color: selected
          ? Color.alphaBlend(
              AppVisualTokens.primaryBlue.withValues(alpha: 0.12),
              visualTheme.surfaceRaised,
            )
          : visualTheme.surfaceRaised,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: enabled ? onTap : null,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: color,
              fontWeight: selected ? FontWeight.w900 : FontWeight.w700,
              fontSize: 14,
              height: 1.15,
            ),
          ),
        ),
      ),
    );
  }
}

class CacheEntryButton extends StatelessWidget {
  const CacheEntryButton({super.key, required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final visualTheme = AppVisualTheme.of(context);
    return Material(
      color: visualTheme.surfaceRaised,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
          child: Row(
            children: [
              const Icon(
                Icons.download_for_offline_outlined,
                size: 20,
                color: AppVisualTokens.primaryBlue,
              ),
              const SizedBox(width: 9),
              Expanded(
                child: Text(
                  '缓存',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: visualTheme.textPrimary,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              Icon(
                Icons.chevron_right_rounded,
                size: 22,
                color: visualTheme.textTertiary,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class PanelHeading extends StatelessWidget {
  const PanelHeading({super.key, required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final visualTheme = AppVisualTheme.of(context);
    return Text(
      title,
      style: theme.textTheme.titleLarge?.copyWith(
        color: visualTheme.textPrimary,
        fontWeight: FontWeight.w800,
      ),
    );
  }
}

/// 内容 tab（简介/评论）壳：tab 文案与尾部 widget 由宿主提供。
class PlaybackContextTabs extends StatelessWidget {
  const PlaybackContextTabs({
    super.key,
    required this.controller,
    required this.introLabel,
    this.commentsLabel,
    this.trailing,
  });

  final TabController controller;
  final String introLabel;

  /// 评论 tab 文案；平台未声明评论面板时为 null，不渲染评论 tab。
  final String? commentsLabel;

  /// 尾部附加内容（如弹幕入口胶囊），平台不提供时为空。
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final visualTheme = AppVisualTheme.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: visualTheme.divider)),
      ),
      child: SizedBox(
        height: 40,
        child: Row(
          children: [
            Expanded(
              child: TabBar(
                controller: controller,
                isScrollable: true,
                tabAlignment: TabAlignment.start,
                dividerColor: Colors.transparent,
                indicatorColor: AppVisualTokens.primaryBlue,
                indicatorSize: TabBarIndicatorSize.label,
                indicatorWeight: 3,
                labelColor: AppVisualTokens.primaryBlue,
                unselectedLabelColor: visualTheme.textSecondary,
                labelPadding: const EdgeInsets.symmetric(horizontal: 12),
                splashBorderRadius: BorderRadius.circular(8),
                labelStyle: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w900,
                  height: 1.1,
                ),
                unselectedLabelStyle: Theme.of(context).textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.w900, height: 1.1),
                tabs: [
                  PlaybackTab(
                    key: const ValueKey<String>('playback-intro-tab'),
                    label: introLabel,
                  ),
                  if (commentsLabel != null)
                    PlaybackTab(
                      key: const ValueKey<String>('playback-comments-tab'),
                      label: commentsLabel!,
                    ),
                ],
              ),
            ),
            ?trailing,
          ],
        ),
      ),
    );
  }
}

class PlaybackTab extends StatelessWidget {
  const PlaybackTab({super.key, required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 40,
      child: Center(
        child: Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
        ),
      ),
    );
  }
}

class CollapsedPlaybackBar extends StatelessWidget {
  const CollapsedPlaybackBar({
    super.key,
    required this.title,
    required this.isPlaying,
    required this.onBack,
    required this.onHome,
    required this.onPlayPause,
    required this.onMore,
  });

  final String title;
  final bool isPlaying;
  final VoidCallback onBack;
  final VoidCallback onHome;
  final VoidCallback onPlayPause;
  final VoidCallback onMore;

  @override
  Widget build(BuildContext context) {
    final visualTheme = AppVisualTheme.of(context);
    return DecoratedBox(
      key: const ValueKey<String>('playback-collapsed-bar'),
      decoration: BoxDecoration(
        color: visualTheme.surface,
        border: Border(bottom: BorderSide(color: visualTheme.divider)),
        boxShadow: [
          BoxShadow(
            color: visualTheme.shadow,
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: SafeArea(
        bottom: false,
        child: SizedBox(
          height: 64,
          child: Row(
            children: [
              CollapsedBarIcon(icon: Icons.arrow_back_rounded, onTap: onBack),
              CollapsedBarIcon(icon: Icons.home_outlined, onTap: onHome),
              const Spacer(),
              Material(
                color: Colors.transparent,
                child: InkWell(
                  borderRadius: BorderRadius.circular(999),
                  onTap: onPlayPause,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 8,
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          isPlaying
                              ? Icons.pause_rounded
                              : Icons.play_arrow_rounded,
                          color: AppVisualTokens.primaryBlue,
                          size: 34,
                        ),
                        const SizedBox(width: 5),
                        Text(
                          isPlaying ? '正在播放' : '继续播放',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: visualTheme.textPrimary,
                            fontSize: 18,
                            fontWeight: FontWeight.w900,
                            height: 1.1,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const Spacer(),
              CollapsedBarIcon(icon: Icons.more_vert_rounded, onTap: onMore),
            ],
          ),
        ),
      ),
    );
  }
}

class CollapsedBarIcon extends StatelessWidget {
  const CollapsedBarIcon({super.key, required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final visualTheme = AppVisualTheme.of(context);
    return IconButton(
      onPressed: onTap,
      constraints: const BoxConstraints(minWidth: 52, minHeight: 52),
      icon: Icon(icon, color: visualTheme.textPrimary, size: 30),
    );
  }
}

class PlaybackBottomSheetScaffold extends StatelessWidget {
  const PlaybackBottomSheetScaffold({
    super.key,
    required this.title,
    required this.child,
  });

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final visualTheme = AppVisualTheme.of(context);
    final height = MediaQuery.sizeOf(context).height * 0.82;
    return SizedBox(
      height: height,
      child: Column(
        children: [
          SizedBox(
            height: 54,
            child: Row(
              children: [
                const SizedBox(width: 18),
                Expanded(
                  child: Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: visualTheme.textPrimary,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.of(context).pop(),
                  constraints: const BoxConstraints(
                    minWidth: 48,
                    minHeight: 48,
                  ),
                  icon: Icon(
                    Icons.close_rounded,
                    size: 30,
                    color: visualTheme.textTertiary,
                  ),
                ),
                const SizedBox(width: 4),
              ],
            ),
          ),
          Divider(height: 1, color: visualTheme.divider),
          Expanded(
            child: SingleChildScrollView(
              physics: const BouncingScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(18, 18, 18, 24),
              child: child,
            ),
          ),
        ],
      ),
    );
  }
}

/// Layout variants for the platform-declared action bar.
enum MediaEngagementBarLayout { wrap, compactIconRow }

/// 通用互动动作栏：按 [MediaEngagementActionSpec] 声明渲染动作按钮。
///
/// 壳对动作零分支——图标按动作语义映射，文案/计数/选中/busy/执行全部
/// 来自适配器快照；[onMessage] 展示 perform() 返回的提示语。
class MediaEngagementBar extends StatelessWidget {
  const MediaEngagementBar({
    super.key,
    required this.actions,
    required this.onMessage,
    this.layout = MediaEngagementBarLayout.wrap,
  });

  final List<MediaEngagementActionSpec> actions;
  final void Function(String message) onMessage;
  final MediaEngagementBarLayout layout;

  @override
  Widget build(BuildContext context) {
    if (actions.isEmpty) {
      return const SizedBox.shrink();
    }
    if (layout == MediaEngagementBarLayout.compactIconRow &&
        actions.length <= 5) {
      return Row(
        children: [
          for (final action in actions)
            Expanded(
              child: _MediaEngagementActionButton(
                action: action,
                onMessage: onMessage,
                compact: true,
              ),
            ),
        ],
      );
    }
    return Wrap(
      spacing: 6,
      runSpacing: 10,
      children: [
        for (final action in actions)
          _MediaEngagementActionButton(action: action, onMessage: onMessage),
      ],
    );
  }
}

class _MediaEngagementActionButton extends StatefulWidget {
  const _MediaEngagementActionButton({
    required this.action,
    required this.onMessage,
    this.compact = false,
  });

  final MediaEngagementActionSpec action;
  final void Function(String message) onMessage;
  final bool compact;

  @override
  State<_MediaEngagementActionButton> createState() =>
      _MediaEngagementActionButtonState();
}

class _MediaEngagementActionButtonState
    extends State<_MediaEngagementActionButton> {
  bool _performing = false;

  IconData get _icon => switch (widget.action.id) {
    MediaEngagementActionId.like =>
      widget.action.selected
          ? Icons.thumb_up_alt_rounded
          : Icons.thumb_up_alt_outlined,
    MediaEngagementActionId.coin => Icons.paid_outlined,
    MediaEngagementActionId.favorite =>
      widget.action.selected ? Icons.star_rounded : Icons.star_outline_rounded,
    MediaEngagementActionId.share => Icons.share_outlined,
    MediaEngagementActionId.follow =>
      widget.action.selected
          ? Icons.person_add_alt_1_rounded
          : Icons.person_add_alt_1_outlined,
    MediaEngagementActionId.watchLater =>
      widget.action.selected
          ? Icons.bookmark_rounded
          : Icons.bookmark_border_rounded,
  };

  Future<void> _handleTap() async {
    if (_performing || widget.action.busy) {
      return;
    }
    setState(() {
      _performing = true;
    });
    try {
      final message = await widget.action.perform();
      if (mounted && message != null) {
        widget.onMessage(message);
      }
    } finally {
      if (mounted) {
        setState(() {
          _performing = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final visualTheme = AppVisualTheme.of(context);
    final action = widget.action;
    final disabled = _performing || action.busy;
    final countText =
        action.countLabel ?? (action.count == null ? null : '${action.count}');
    final foreground = action.selected
        ? AppVisualTokens.primaryBlue
        : visualTheme.textPrimary;
    final semanticsLabel = countText == null
        ? action.label
        : '${action.label} $countText';
    return Tooltip(
      message: action.label,
      excludeFromSemantics: true,
      child: Semantics(
        button: true,
        enabled: !disabled,
        selected: action.selected,
        label: semanticsLabel,
        onTap: disabled ? null : () => unawaited(_handleTap()),
        excludeSemantics: true,
        child: Opacity(
          opacity: disabled ? 0.55 : 1,
          child: Material(
            color: widget.compact
                ? action.selected
                      ? AppVisualTokens.primaryBlue.withValues(alpha: 0.10)
                      : Colors.transparent
                : action.selected
                ? AppVisualTokens.primaryBlue.withValues(alpha: 0.10)
                : visualTheme.surfaceRaised,
            borderRadius: BorderRadius.circular(10),
            child: InkWell(
              key: ValueKey<String>('engagement-${action.id.name}'),
              borderRadius: BorderRadius.circular(10),
              onTap: disabled ? null : () => unawaited(_handleTap()),
              child: widget.compact
                  ? _buildCompactContent(
                      context,
                      foreground: foreground,
                      countText: countText,
                    )
                  : _buildLabelledContent(
                      context,
                      foreground: foreground,
                      countText: countText,
                    ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCompactContent(
    BuildContext context, {
    required Color foreground,
    required String? countText,
  }) {
    final visualTheme = AppVisualTheme.of(context);
    return SizedBox(
      height: 56,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 6),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(_icon, size: 22, color: foreground),
            if (countText != null) ...[
              const SizedBox(height: 3),
              Text(
                countText,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: widget.action.selected
                      ? foreground
                      : visualTheme.textTertiary,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  fontFeatures: const <FontFeature>[
                    FontFeature.tabularFigures(),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildLabelledContent(
    BuildContext context, {
    required Color foreground,
    required String? countText,
  }) {
    final visualTheme = AppVisualTheme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(_icon, size: 18, color: foreground),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              widget.action.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: foreground,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          if (countText != null) ...[
            const SizedBox(width: 4),
            Flexible(
              child: Text(
                countText,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: visualTheme.textTertiary,
                  fontWeight: FontWeight.w600,
                  fontFeatures: const <FontFeature>[
                    FontFeature.tabularFigures(),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

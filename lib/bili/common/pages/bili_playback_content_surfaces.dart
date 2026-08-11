// Bilibili 播放内容面板（简介/评论/相关视频）—— [MediaContentSurfaces] 参考实现。
//
// 面板渲染所需状态来自 [BiliPlaybackViewModel]；壳侧资源（滚动控制器、
// 折叠联动、评论回复开关同步、时间跳转、新播放页跳转）经
// [MediaPlaybackContentHost] 注入。评论回复面板开关由本文件自持。
import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:material_ui/material_ui.dart';
import 'package:signals/signals_flutter.dart';
import 'package:vesper_media/media/design/app_visual_theme.dart';
import 'package:vesper_media/bili/common/services/bili_api_core.dart';
import 'package:vesper_media/bili/common/services/bili_media_mapper.dart';
import 'package:vesper_media/bili/common/services/bili_text.dart';
import 'package:vesper_media/media/media.dart';
import 'package:vesper_media/media/player/media_glass_sheet.dart';

import '../models/bili_models.dart';
import '../view_models/bili_playback_view_model.dart';

/// 参考实现：B 站内容面板（简介/评论/相关视频）。
final class BiliPlaybackContentSurfaces implements MediaContentSurfaces {
  BiliPlaybackContentSurfaces({
    required this.viewModel,
    required this.detail,
    required this.host,
  }) {
    // 评论列表滚动到底部时的加载更多（壳的滚动监听触发）。
    host.onLoadMoreComments = viewModel.loadMoreComments;
    host.onLoadMoreCommentReplies = viewModel.loadMoreCommentReplies;
  }

  final BiliPlaybackViewModel viewModel;
  final BiliVideoDetail detail;
  final MediaPlaybackContentHost host;

  @override
  String get introTabLabel => '简介';

  @override
  String? get commentsTabLabel => '评论';

  @override
  Widget buildIntroSurface(
    BuildContext context,
    MediaPlaybackTarget target,
    MediaSurfaceHost surfaceHost,
  ) {
    return _IntroSurface(surfaces: this);
  }

  @override
  Widget? buildCommentsSurface(
    BuildContext context,
    MediaPlaybackTarget target,
  ) {
    return _CommentsSurface(surfaces: this);
  }

  Future<void> _showPageSelectionSheet(BuildContext context) async {
    final pages = detail.pages;
    if (pages.length <= 1) {
      return;
    }
    final isPgc = detail.ownerMid <= 0 && detail.ownerName == '番剧';
    await showMediaGlassSheet<void>(
      context: context,
      maxContentHeightFactor: 0.82,
      contentPadding: EdgeInsets.zero,
      builder: (context) {
        return PlaybackBottomSheetScaffold(
          title: isPgc
              ? '剧集 · 共 ${pages.length} 话/集'
              : '合集 · 共 ${pages.length} 个分 P',
          child: EpisodePreviewList(
            pages: pages,
            selectedPage: viewModel.selectedPage,
            coverUrl: detail.coverUrl,
            onTap: (page) async {
              Navigator.of(context).pop();
              await viewModel.switchPage(page);
            },
            isPgc: isPgc,
          ),
        );
      },
    );
  }

  Future<void> _openRelatedVideo(BuildContext context, BiliFeedVideo video) {
    return _openRelatedVideoFromBvid(context, video.bvid);
  }

  Future<void> _openRelatedVideoFromBvid(
    BuildContext context,
    String bvid,
  ) async {
    try {
      final relatedDetail = await viewModel.client.fetchVideoDetail(bvid);
      if (!context.mounted) {
        return;
      }
      final nextPage = relatedDetail.pages.isEmpty
          ? null
          : relatedDetail.pages.first;
      if (nextPage == null) {
        _showSnackBar(context, '这个视频没有可播放分 P。');
        return;
      }
      host.surfaceHost.pushPlayback(
        BiliMediaMapper.toGenericDetail(relatedDetail),
        BiliMediaMapper.toGenericEntry(nextPage),
      );
    } catch (error) {
      if (context.mounted) {
        _showSnackBar(context, '打开相关视频失败：${biliErrorMessage(error)}');
      }
    }
  }
}

class _IntroSurface extends StatefulWidget {
  const _IntroSurface({required this.surfaces});

  final BiliPlaybackContentSurfaces surfaces;

  @override
  State<_IntroSurface> createState() => _IntroSurfaceState();
}

class _IntroSurfaceState extends State<_IntroSurface> {
  bool _introExpanded = false;
  String? _openingRelatedBvid;

  @override
  Widget build(BuildContext context) {
    // VM 信号读取必须发生在 SignalBuilder 的 builder 调用栈内才会被追踪，
    // 因此放在 build 内部的 leaf SignalBuilder 里。
    return SignalBuilder(builder: (context) => _buildIntroBody(context));
  }

  Widget _buildIntroBody(BuildContext context) {
    final s = widget.surfaces;
    final vm = s.viewModel;
    final detail = s.detail;
    final isPgc = detail.ownerMid <= 0 && detail.ownerName == '番剧';
    final pages = detail.pages;
    final selectedPage = vm.selectedPage;

    final topChildren = <Widget>[
      if (!isPgc) ...[
        _OwnerSummary(
          name: detail.ownerName,
          avatarUrl: detail.ownerAvatarUrl,
          subtitle: vm.ownerSubtitle,
          isFollowing: vm.engagement?.isFollowingOwner ?? false,
          isBusy: vm.pendingEngagementAction == BiliEngagementAction.follow,
          onFollow: () => _runAction(context, vm.toggleFollow),
        ),
        const SizedBox(height: 18),
      ],
      _PlaybackIntroSummary(
        title: detail.title,
        description: detail.description.trim(),
        expanded: _introExpanded,
        onToggleExpanded: () {
          setState(() {
            _introExpanded = !_introExpanded;
          });
        },
        metadata: _PlaybackMetaLine(
          entries: [
            if (detail.playCountLabel != '--')
              _PlaybackMetaEntry(
                icon: Icons.play_circle_outline_rounded,
                label: '${detail.playCountLabel}播放',
              ),
            if (detail.danmakuCountLabel != '--')
              _PlaybackMetaEntry(
                icon: Icons.subtitles_outlined,
                label: detail.danmakuCountLabel,
              ),
            if (detail.publishedAtLabel != null)
              _PlaybackMetaEntry(
                icon: Icons.schedule_rounded,
                label: detail.publishedAtLabel!,
              ),
            _PlaybackMetaEntry(
              icon: Icons.confirmation_number_outlined,
              label: selectedPage.bvid ?? detail.bvid,
            ),
          ],
        ),
      ),
      SignalBuilder(
        builder: (context) {
          final capability = vm.playbackViewModel.adapter.engagement;
          if (capability == null ||
              capability.actions.isEmpty ||
              capability.placement != MediaEngagementPlacement.intro) {
            return const SizedBox.shrink();
          }
          return Padding(
            key: const ValueKey<String>('bili-intro-engagement-bar'),
            padding: const EdgeInsets.only(top: 22),
            child: MediaEngagementBar(
              actions: capability.actions,
              onMessage: (message) => _showSnackBar(context, message),
              layout: MediaEngagementBarLayout.compactIconRow,
            ),
          );
        },
      ),
      if (pages.length > 1) ...[
        const SizedBox(height: 18),
        _PageSelectionButton(
          title: isPgc
              ? '剧集 · 共 ${pages.length} 话/集'
              : '合集 · 共 ${pages.length} 个分 P',
          selectedLabel: isPgc
              ? '第 ${selectedPage.pageNumber} 话 · ${selectedPage.title}'
              : 'P${selectedPage.pageNumber} · ${selectedPage.title}',
          coverUrl: selectedPage.coverUrl ?? detail.coverUrl,
          durationLabel: biliFormatDurationSeconds(
            selectedPage.durationSeconds,
          ),
          onTap: () => unawaited(s._showPageSelectionSheet(context)),
        ),
      ],
      const SizedBox(height: 18),
      _PlaybackSectionHeader(
        title: '相关推荐',
        action: vm.relatedVideosError == null
            ? null
            : TextButton.icon(
                onPressed: () => unawaited(vm.loadRelatedVideos()),
                icon: const Icon(Icons.refresh_rounded, size: 18),
                label: const Text('重试'),
                style: TextButton.styleFrom(
                  minimumSize: const Size(58, 40),
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  foregroundColor: AppVisualTokens.primaryBlue,
                  textStyle: const TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
      ),
      const SizedBox(height: 12),
    ];

    return NotificationListener<ScrollNotification>(
      onNotification: s.host.onContentScroll,
      child: CustomScrollView(
        key: const PageStorageKey<String>('playback-related'),
        controller: s.host.relatedScrollController,
        physics: const BouncingScrollPhysics(
          parent: AlwaysScrollableScrollPhysics(),
        ),
        slivers: [
          SliverPadding(
            padding: const EdgeInsets.only(top: 14),
            sliver: SliverList(delegate: SliverChildListDelegate(topChildren)),
          ),
          SliverPadding(
            padding: const EdgeInsets.only(bottom: 18),
            sliver: _RelatedVideoSliverList(
              items: vm.relatedVideos,
              loading: vm.relatedVideosLoading,
              errorMessage: vm.relatedVideosError,
              openingBvid: _openingRelatedBvid,
              onTap: (video) {
                setState(() {
                  _openingRelatedBvid = video.bvid;
                });
                unawaited(
                  s._openRelatedVideo(context, video).whenComplete(() {
                    if (mounted) {
                      setState(() {
                        _openingRelatedBvid = null;
                      });
                    }
                  }),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _CommentsSurface extends StatefulWidget {
  const _CommentsSurface({required this.surfaces});

  final BiliPlaybackContentSurfaces surfaces;

  @override
  State<_CommentsSurface> createState() => _CommentsSurfaceState();
}

class _CommentsSurfaceState extends State<_CommentsSurface> {
  BiliVideoComment? _openedCommentReplies;

  @override
  Widget build(BuildContext context) {
    // VM 信号读取必须发生在 SignalBuilder 的 builder 调用栈内才会被追踪。
    return SignalBuilder(builder: (context) => _buildCommentsBody(context));
  }

  void _openReplies(BiliVideoComment comment) {
    final s = widget.surfaces;
    s.host.commentComposerFocusNode.unfocus();
    setState(() {
      _openedCommentReplies = comment;
    });
    s.host.onCommentRepliesVisibilityChanged(true);
    unawaited(s.viewModel.loadCommentReplies(comment));
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && s.host.commentRepliesScrollController.hasClients) {
        s.host.commentRepliesScrollController.jumpTo(0);
      }
    });
  }

  void _closeReplies() {
    final s = widget.surfaces;
    if (_openedCommentReplies == null) {
      return;
    }
    setState(() {
      _openedCommentReplies = null;
    });
    s.host.onCommentRepliesVisibilityChanged(false);
    s.viewModel.clearCommentReplies();
  }

  Widget _buildCommentsBody(BuildContext context) {
    final s = widget.surfaces;
    final vm = s.viewModel;
    final openedCommentReplies = _openedCommentReplies;
    if (openedCommentReplies != null) {
      return NotificationListener<ScrollNotification>(
        onNotification: s.host.onContentScroll,
        child: _CommentReplyPanel(
          comment: openedCommentReplies,
          replies: vm.commentReplies,
          totalCount: vm.commentRepliesTotalCount,
          loading: vm.commentRepliesLoading,
          loadingMore: vm.commentRepliesLoadingMore,
          hasMore: vm.commentRepliesHasMore,
          errorMessage: vm.commentRepliesError,
          controller: s.host.commentRepliesScrollController,
          onClose: _closeReplies,
          onLoadMore: vm.loadMoreCommentReplies,
          onRetry: () => vm.retryCommentReplies(openedCommentReplies),
          onSeekToTime: (seconds) {
            _closeReplies();
            unawaited(s.host.onSeekToTime(seconds));
          },
        ),
      );
    }

    final bottomPadding = 118 + MediaQuery.viewPaddingOf(context).bottom;
    return Stack(
      children: [
        NotificationListener<ScrollNotification>(
          onNotification: s.host.onContentScroll,
          child: ListView(
            key: const PageStorageKey<String>('playback-comments'),
            controller: s.host.commentsScrollController,
            physics: const BouncingScrollPhysics(
              parent: AlwaysScrollableScrollPhysics(),
            ),
            padding: EdgeInsets.only(top: 14, bottom: bottomPadding),
            children: [
              _CommentThreadList(
                comments: vm.comments,
                loading: vm.commentsLoading,
                loadingMore: vm.commentsLoadingMore,
                hasMore: vm.commentsHasMore,
                errorMessage: vm.commentsError,
                onReload: vm.loadComments,
                onLoadMore: vm.loadMoreComments,
                onSeekToTime: (seconds) =>
                    unawaited(s.host.onSeekToTime(seconds)),
                onOpenReplies: _openReplies,
              ),
            ],
          ),
        ),
        Align(
          alignment: Alignment.bottomCenter,
          child: _CommentComposerBar(
            controller: s.host.commentComposerController,
            focusNode: s.host.commentComposerFocusNode,
            submitting: vm.commentSubmitting,
            onSubmitted: (message) =>
                unawaited(_submitComment(context, message)),
          ),
        ),
      ],
    );
  }

  Future<void> _submitComment(BuildContext context, String rawMessage) async {
    final s = widget.surfaces;
    final vm = s.viewModel;
    final message = rawMessage.trim();
    if (message.isEmpty) {
      _showSnackBar(context, '评论内容不能为空');
      return;
    }
    final result = await vm.submitComment(message);
    if (!context.mounted || result == null) {
      return;
    }
    if (result == '已发送评论') {
      s.host.commentComposerController.clear();
      s.host.commentComposerFocusNode.unfocus();
      if (s.host.commentsScrollController.hasClients) {
        unawaited(
          s.host.commentsScrollController.animateTo(
            0,
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOutCubic,
          ),
        );
      }
    }
    _showSnackBar(context, result);
  }
}

Future<void> _runAction(
  BuildContext context,
  Future<String?> Function() operation,
) async {
  final message = await operation();
  if (message != null && context.mounted) {
    _showSnackBar(context, message);
  }
}

void _showSnackBar(BuildContext context, String message) {
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
}

// ---- 展示组件（B 站内容槽） ----

class DanmakuEntryPill extends StatelessWidget {
  const DanmakuEntryPill({super.key, required this.danmakuCountLabel});

  final String danmakuCountLabel;

  @override
  Widget build(BuildContext context) {
    final visualTheme = AppVisualTheme.of(context);
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 20, maxWidth: 140),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: visualTheme.surfaceRaised,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: visualTheme.divider),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 8, 10, 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: Text(
                  danmakuCountLabel == '--' ? '弹幕' : '弹幕 $danmakuCountLabel',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: visualTheme.textTertiary,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Icon(
                Icons.chat_bubble_outline_rounded,
                size: 14,
                color: visualTheme.textSecondary,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

final class _PlaybackMetaEntry {
  const _PlaybackMetaEntry({required this.icon, required this.label});

  final IconData icon;
  final String label;
}

class _PlaybackMetaLine extends StatelessWidget {
  const _PlaybackMetaLine({required this.entries});

  final List<_PlaybackMetaEntry> entries;

  @override
  Widget build(BuildContext context) {
    final visibleEntries = entries
        .where((entry) => entry.label.trim().isNotEmpty && entry.label != '--')
        .toList(growable: false);
    return Wrap(
      spacing: 10,
      runSpacing: 7,
      children: [
        for (final entry in visibleEntries)
          _PlaybackMetaChip(icon: entry.icon, label: entry.label),
      ],
    );
  }
}

class _PlaybackMetaChip extends StatelessWidget {
  const _PlaybackMetaChip({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final visualTheme = AppVisualTheme.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 16, color: visualTheme.textTertiary),
        const SizedBox(width: 4),
        Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            color: visualTheme.textTertiary,
            fontWeight: FontWeight.w700,
            fontFeatures: const [ui.FontFeature.tabularFigures()],
          ),
        ),
      ],
    );
  }
}

class _PlaybackIntroSummary extends StatelessWidget {
  const _PlaybackIntroSummary({
    required this.title,
    required this.description,
    required this.expanded,
    required this.onToggleExpanded,
    required this.metadata,
  });

  final String title;
  final String description;
  final bool expanded;
  final VoidCallback onToggleExpanded;
  final Widget metadata;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final visualTheme = AppVisualTheme.of(context);
    final titleStyle = theme.textTheme.titleLarge?.copyWith(
      color: visualTheme.textPrimary,
      fontWeight: FontWeight.w900,
      height: 1.18,
    );
    final descriptionStyle = theme.textTheme.bodyMedium?.copyWith(
      color: visualTheme.textSecondary,
      height: 1.62,
      fontWeight: FontWeight.w500,
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        final textDirection = Directionality.of(context);
        final textScaler = MediaQuery.textScalerOf(context);
        final locale = Localizations.maybeLocaleOf(context);
        final descriptionPainter = TextPainter(
          text: TextSpan(text: description, style: descriptionStyle),
          maxLines: 3,
          textDirection: textDirection,
          textScaler: textScaler,
          locale: locale,
        )..layout(maxWidth: constraints.maxWidth);
        final showsExpandButton =
            description.isNotEmpty && descriptionPainter.didExceedMaxLines;
        descriptionPainter.dispose();
        final effectiveExpanded = showsExpandButton && expanded;
        final titleLinePainter = TextPainter(
          text: TextSpan(text: 'M', style: titleStyle),
          maxLines: 1,
          textDirection: textDirection,
          textScaler: textScaler,
          locale: locale,
        )..layout();
        final titleFirstLineHeight = titleLinePainter.preferredLineHeight;
        titleLinePainter.dispose();

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(
                    title,
                    key: const ValueKey<String>('playback-intro-title'),
                    maxLines: effectiveExpanded ? 4 : 2,
                    overflow: TextOverflow.ellipsis,
                    style: titleStyle,
                  ),
                ),
                if (showsExpandButton)
                  _IntroExpandButton(
                    key: const ValueKey<String>('playback-intro-expand'),
                    expanded: effectiveExpanded,
                    firstLineHeight: titleFirstLineHeight,
                    onTap: onToggleExpanded,
                  ),
              ],
            ),
            const SizedBox(height: 9),
            metadata,
            if (description.isNotEmpty) ...[
              const SizedBox(height: 13),
              AnimatedSize(
                duration: const Duration(milliseconds: 180),
                curve: Curves.easeOutCubic,
                alignment: Alignment.topCenter,
                child: Text(
                  description,
                  key: const ValueKey<String>('playback-intro-description'),
                  maxLines: showsExpandButton && !effectiveExpanded ? 3 : null,
                  overflow: showsExpandButton && !effectiveExpanded
                      ? TextOverflow.ellipsis
                      : TextOverflow.visible,
                  style: descriptionStyle,
                ),
              ),
            ],
          ],
        );
      },
    );
  }
}

class _IntroExpandButton extends StatelessWidget {
  const _IntroExpandButton({
    super.key,
    required this.expanded,
    required this.firstLineHeight,
    required this.onTap,
  });

  final bool expanded;
  final double firstLineHeight;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final visualTheme = AppVisualTheme.of(context);
    return Transform.translate(
      offset: Offset(0, (firstLineHeight - 40) / 2),
      child: IconButton(
        onPressed: onTap,
        constraints: const BoxConstraints.tightFor(width: 40, height: 40),
        padding: EdgeInsets.zero,
        alignment: Alignment.center,
        icon: AnimatedRotation(
          turns: expanded ? 0.5 : 0,
          duration: const Duration(milliseconds: 160),
          curve: Curves.easeOutCubic,
          child: Icon(
            Icons.keyboard_arrow_down_rounded,
            color: visualTheme.textTertiary,
            size: 28,
          ),
        ),
        tooltip: expanded ? '收起简介' : '展开简介',
      ),
    );
  }
}

class _PlaybackSectionHeader extends StatelessWidget {
  const _PlaybackSectionHeader({required this.title, this.action});

  final String title;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final visualTheme = AppVisualTheme.of(context);
    return Row(
      children: [
        Expanded(
          child: Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              color: visualTheme.textPrimary,
              fontWeight: FontWeight.w900,
              height: 1.15,
            ),
          ),
        ),
        ?action,
      ],
    );
  }
}

class _PageSelectionButton extends StatelessWidget {
  const _PageSelectionButton({
    required this.title,
    required this.selectedLabel,
    required this.coverUrl,
    required this.durationLabel,
    required this.onTap,
  });

  final String title;
  final String selectedLabel;
  final String coverUrl;
  final String durationLabel;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final visualTheme = AppVisualTheme.of(context);
    final cacheWidth = (96 * MediaQuery.devicePixelRatioOf(context))
        .round()
        .clamp(160, 360)
        .toInt();
    return Material(
      color: visualTheme.surfaceRaised,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(7),
                child: SizedBox(
                  width: 96,
                  height: 54,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      DecoratedBox(
                        decoration: BoxDecoration(
                          color: visualTheme.surfaceMuted,
                        ),
                        child: coverUrl.isEmpty
                            ? Icon(
                                Icons.video_library_outlined,
                                color: visualTheme.textTertiary,
                              )
                            : Image.network(
                                coverUrl,
                                fit: BoxFit.cover,
                                cacheWidth: cacheWidth,
                                errorBuilder: (_, _, _) => Icon(
                                  Icons.broken_image_outlined,
                                  color: visualTheme.textTertiary,
                                ),
                              ),
                      ),
                      DecoratedBox(
                        decoration: BoxDecoration(
                          border: Border.fromBorderSide(
                            BorderSide(color: visualTheme.imageOutline),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: visualTheme.textTertiary,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      selectedLabel,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: visualTheme.textPrimary,
                        fontWeight: FontWeight.w900,
                        height: 1.2,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      durationLabel,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: visualTheme.textTertiary,
                        fontWeight: FontWeight.w700,
                        fontFeatures: const [ui.FontFeature.tabularFigures()],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Icon(
                Icons.keyboard_arrow_up_rounded,
                size: 28,
                color: visualTheme.textTertiary,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _OwnerSummary extends StatelessWidget {
  const _OwnerSummary({
    required this.name,
    required this.avatarUrl,
    required this.subtitle,
    required this.isFollowing,
    required this.isBusy,
    required this.onFollow,
  });

  final String name;
  final String avatarUrl;
  final String subtitle;
  final bool isFollowing;
  final bool isBusy;
  final VoidCallback onFollow;

  @override
  Widget build(BuildContext context) {
    final visualTheme = AppVisualTheme.of(context);
    final imageProvider = avatarUrl.isEmpty
        ? null
        : ResizeImage.resizeIfNeeded(96, 96, NetworkImage(avatarUrl));
    return Row(
      children: [
        CircleAvatar(
          radius: 22,
          backgroundColor: AppVisualTokens.primaryBlue,
          backgroundImage: imageProvider,
          child: imageProvider == null
              ? Text(
                  name.isEmpty ? 'UP' : name.characters.first,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                  ),
                )
              : null,
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: visualTheme.textPrimary,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                subtitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: visualTheme.textTertiary,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 12),
        FilledButton(
          onPressed: isBusy ? null : onFollow,
          style: FilledButton.styleFrom(
            minimumSize: const Size(78, 34),
            padding: const EdgeInsets.symmetric(horizontal: 14),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(999),
            ),
          ),
          child: isBusy
              ? Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                    const SizedBox(width: 6),
                    Text(isFollowing ? '已关注' : '关注'),
                  ],
                )
              : Text(isFollowing ? '已关注' : '关注'),
        ),
      ],
    );
  }
}

class EpisodePreviewList extends StatelessWidget {
  const EpisodePreviewList({
    super.key,
    required this.pages,
    required this.selectedPage,
    required this.coverUrl,
    required this.onTap,
    this.isPgc = false,
  });

  final List<BiliVideoPageEntry> pages;
  final BiliVideoPageEntry selectedPage;
  final String coverUrl;
  final Future<void> Function(BiliVideoPageEntry) onTap;
  final bool isPgc;

  @override
  Widget build(BuildContext context) {
    if (pages.isEmpty) {
      return const SizedBox.shrink();
    }
    return Column(
      children: [
        for (final page in pages) ...[
          _EpisodePreviewTile(
            page: page,
            selected: page.cid == selectedPage.cid,
            coverUrl: coverUrl,
            isPgc: isPgc,
            onTap: () => unawaited(onTap(page)),
          ),
          if (page != pages.last) const SizedBox(height: 18),
        ],
      ],
    );
  }
}

class _EpisodePreviewTile extends StatelessWidget {
  const _EpisodePreviewTile({
    required this.page,
    required this.selected,
    required this.coverUrl,
    required this.isPgc,
    required this.onTap,
  });

  final BiliVideoPageEntry page;
  final bool selected;
  final String coverUrl;
  final bool isPgc;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final visualTheme = AppVisualTheme.of(context);
    final titleColor = selected
        ? AppVisualTokens.primaryBlue
        : visualTheme.textPrimary;
    final label = isPgc ? '第 ${page.pageNumber} 话' : 'P${page.pageNumber}';
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: selected ? null : onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: SizedBox(
                  width: 174,
                  height: 104,
                  child: (page.coverUrl ?? coverUrl).isEmpty
                      ? ColoredBox(color: visualTheme.surfaceRaised)
                      : Image.network(
                          page.coverUrl ?? coverUrl,
                          fit: BoxFit.cover,
                          errorBuilder: (_, _, _) =>
                              ColoredBox(color: visualTheme.surfaceRaised),
                        ),
                ),
              ),
              const SizedBox(width: 22),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: titleColor,
                        fontSize: 12,
                        fontWeight: FontWeight.w900,
                        height: 1.15,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      page.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: titleColor,
                        fontWeight: FontWeight.w900,
                        height: 1.25,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      biliFormatDurationSeconds(page.durationSeconds),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: visualTheme.textTertiary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RelatedVideoSliverList extends StatelessWidget {
  const _RelatedVideoSliverList({
    required this.items,
    required this.loading,
    required this.errorMessage,
    required this.openingBvid,
    required this.onTap,
  });

  final List<BiliFeedVideo> items;
  final bool loading;
  final String? errorMessage;
  final String? openingBvid;
  final ValueChanged<BiliFeedVideo> onTap;

  @override
  Widget build(BuildContext context) {
    final visualTheme = AppVisualTheme.of(context);
    if (items.isEmpty && loading) {
      return const SliverToBoxAdapter(
        child: Padding(
          padding: EdgeInsets.symmetric(vertical: 18),
          child: Center(child: CircularProgressIndicator(strokeWidth: 2.4)),
        ),
      );
    }
    if (items.isEmpty && errorMessage != null) {
      return SliverToBoxAdapter(
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: Color.alphaBlend(
              visualTheme.destructive.withValues(alpha: 0.12),
              visualTheme.surfaceRaised,
            ),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Text(
              errorMessage!,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: visualTheme.destructive,
                height: 1.45,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
      );
    }
    if (items.isEmpty) {
      return SliverToBoxAdapter(
        child: Text(
          '暂无相关视频',
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            color: visualTheme.textTertiary,
            fontWeight: FontWeight.w700,
          ),
        ),
      );
    }

    final relatedChildCount = items.length * 2 - 1;
    return SliverList(
      delegate: SliverChildBuilderDelegate((context, index) {
        if (index >= relatedChildCount) {
          return const Padding(
            padding: EdgeInsets.only(top: 14),
            child: Center(
              child: SizedBox.square(
                dimension: 22,
                child: CircularProgressIndicator(strokeWidth: 2.2),
              ),
            ),
          );
        }
        if (index.isOdd) {
          return Divider(
            height: 18,
            thickness: 0.7,
            color: visualTheme.divider,
          );
        }
        final item = items[index ~/ 2];
        return _RelatedVideoTile(
          item: item,
          opening: openingBvid == item.bvid,
          onTap: () => onTap(item),
        );
      }, childCount: relatedChildCount + (loading ? 1 : 0)),
    );
  }
}

class _RelatedVideoTile extends StatelessWidget {
  const _RelatedVideoTile({
    required this.item,
    required this.opening,
    required this.onTap,
  });

  final BiliFeedVideo item;
  final bool opening;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final visualTheme = AppVisualTheme.of(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final coverWidth = constraints.maxWidth < 390 ? 132.0 : 150.0;
        final coverHeight = (coverWidth * 9 / 16).clamp(86.0, 96.0);
        final cacheWidth = (coverWidth * MediaQuery.devicePixelRatioOf(context))
            .round()
            .clamp(220, 560)
            .toInt();
        return Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: opening ? null : onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(7),
                    child: SizedBox(
                      width: coverWidth,
                      height: coverHeight,
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          DecoratedBox(
                            decoration: BoxDecoration(
                              color: visualTheme.surfaceRaised,
                            ),
                            child: item.coverUrl.isEmpty
                                ? Icon(
                                    Icons.video_library_outlined,
                                    color: visualTheme.textTertiary,
                                  )
                                : Image.network(
                                    item.coverUrl,
                                    fit: BoxFit.cover,
                                    cacheWidth: cacheWidth,
                                    errorBuilder: (_, _, _) => Icon(
                                      Icons.broken_image_outlined,
                                      color: visualTheme.textTertiary,
                                    ),
                                  ),
                          ),
                          DecoratedBox(
                            decoration: BoxDecoration(
                              border: Border.fromBorderSide(
                                BorderSide(color: visualTheme.imageOutline),
                              ),
                            ),
                          ),
                          Positioned(
                            right: 5,
                            bottom: 4,
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                color: const Color(0xB3000000),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 5,
                                  vertical: 2,
                                ),
                                child: Text(
                                  item.durationLabel,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w800,
                                    height: 1.05,
                                    fontFeatures: [
                                      ui.FontFeature.tabularFigures(),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ),
                          if (opening)
                            const ColoredBox(
                              color: Color(0x66000000),
                              child: Center(
                                child: SizedBox.square(
                                  dimension: 22,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2.4,
                                    color: Colors.white,
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: SizedBox(
                      height: coverHeight,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            item.title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.titleMedium?.copyWith(
                              color: visualTheme.textPrimary,
                              fontWeight: FontWeight.w900,
                              height: 1.25,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            item.author,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: visualTheme.textTertiary,
                              fontWeight: FontWeight.w700,
                              height: 1.1,
                            ),
                          ),
                          const Spacer(),
                          Row(
                            children: [
                              Icon(
                                Icons.play_circle_outline_rounded,
                                size: 15,
                                color: visualTheme.textTertiary,
                              ),
                              const SizedBox(width: 3),
                              Flexible(
                                child: Text(
                                  item.playCountLabel,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: visualTheme.textTertiary,
                                    fontWeight: FontWeight.w700,
                                    fontFeatures: const [
                                      ui.FontFeature.tabularFigures(),
                                    ],
                                  ),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Icon(
                                Icons.subtitles_outlined,
                                size: 15,
                                color: visualTheme.textTertiary,
                              ),
                              const SizedBox(width: 3),
                              Flexible(
                                child: Text(
                                  item.danmakuCountLabel,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: visualTheme.textTertiary,
                                    fontWeight: FontWeight.w700,
                                    fontFeatures: const [
                                      ui.FontFeature.tabularFigures(),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _CommentThreadList extends StatelessWidget {
  const _CommentThreadList({
    required this.comments,
    required this.loading,
    required this.loadingMore,
    required this.hasMore,
    required this.errorMessage,
    required this.onReload,
    required this.onLoadMore,
    required this.onSeekToTime,
    required this.onOpenReplies,
  });

  final List<BiliVideoComment> comments;
  final bool loading;
  final bool loadingMore;
  final bool hasMore;
  final String? errorMessage;
  final Future<void> Function() onReload;
  final Future<void> Function() onLoadMore;
  final ValueChanged<int> onSeekToTime;
  final ValueChanged<BiliVideoComment> onOpenReplies;

  @override
  Widget build(BuildContext context) {
    final visualTheme = AppVisualTheme.of(context);
    if (comments.isEmpty && loading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 28),
        child: Center(child: CircularProgressIndicator(strokeWidth: 2.4)),
      );
    }
    if (comments.isEmpty && errorMessage != null) {
      return PlaybackInlineError(
        title: '评论加载失败',
        message: errorMessage!,
        actionLabel: '重新加载',
        onPressed: onReload,
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                '热门评论',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: visualTheme.textPrimary,
                  fontWeight: FontWeight.w900,
                  height: 1.15,
                ),
              ),
            ),
            Icon(Icons.sort_rounded, size: 20, color: visualTheme.textTertiary),
            const SizedBox(width: 5),
            Text(
              '按热度',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: visualTheme.textTertiary,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        if (comments.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 18),
            child: Text(
              '暂无评论',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: visualTheme.textTertiary,
                fontWeight: FontWeight.w700,
              ),
            ),
          )
        else ...[
          for (final comment in comments) ...[
            _CommentTile(
              comment: comment,
              onSeekToTime: onSeekToTime,
              onOpenReplies: onOpenReplies,
            ),
            if (comment != comments.last)
              Divider(height: 28, thickness: 0.7, color: visualTheme.divider),
          ],
          if (loadingMore) ...[
            const SizedBox(height: 14),
            const Center(
              child: SizedBox.square(
                dimension: 22,
                child: CircularProgressIndicator(strokeWidth: 2.2),
              ),
            ),
          ] else if (errorMessage != null) ...[
            const SizedBox(height: 14),
            Center(
              child: TextButton.icon(
                onPressed: () => unawaited(onLoadMore()),
                icon: const Icon(Icons.refresh_rounded, size: 18),
                label: const Text('加载更多失败，点此重试'),
                style: TextButton.styleFrom(
                  foregroundColor: AppVisualTokens.primaryBlue,
                  textStyle: const TextStyle(fontWeight: FontWeight.w900),
                ),
              ),
            ),
          ] else if (!hasMore) ...[
            const SizedBox(height: 18),
            Center(
              child: Text(
                '没有更多评论了',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: visualTheme.textTertiary,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ],
        ],
      ],
    );
  }
}

class _CommentTile extends StatelessWidget {
  const _CommentTile({
    required this.comment,
    required this.onSeekToTime,
    required this.onOpenReplies,
    this.showRepliesPreview = true,
  });

  final BiliVideoComment comment;
  final ValueChanged<int> onSeekToTime;
  final ValueChanged<BiliVideoComment> onOpenReplies;
  final bool showRepliesPreview;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final visualTheme = AppVisualTheme.of(context);
    final imageProvider = comment.authorAvatarUrl.isEmpty
        ? null
        : ResizeImage.resizeIfNeeded(
            96,
            96,
            NetworkImage(comment.authorAvatarUrl),
          );
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        CircleAvatar(
          radius: 19,
          backgroundColor: Color.alphaBlend(
            AppVisualTokens.primaryBlue.withValues(alpha: 0.12),
            visualTheme.surfaceRaised,
          ),
          backgroundImage: imageProvider,
          child: imageProvider == null
              ? Text(
                  comment.authorName.isEmpty
                      ? '?'
                      : comment.authorName.characters.first,
                  style: TextStyle(
                    color: AppVisualTokens.primaryBlue,
                    fontSize: 15,
                    fontWeight: FontWeight.w900,
                  ),
                )
              : null,
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 6,
                runSpacing: 4,
                children: [
                  Text(
                    comment.authorName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: visualTheme.textSecondary,
                      fontWeight: FontWeight.w900,
                      height: 1.18,
                    ),
                  ),
                  if (comment.authorLevelLabel != null)
                    _CommentLevelBadge(label: comment.authorLevelLabel!),
                ],
              ),
              if (comment.createdAtLabel.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(
                  comment.createdAtLabel,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: visualTheme.textTertiary,
                    fontWeight: FontWeight.w700,
                    height: 1.1,
                  ),
                ),
              ],
              const SizedBox(height: 10),
              _CommentMessageText(
                message: comment.message,
                timeLinks: comment.timeLinks,
                onSeekToTime: onSeekToTime,
                style: theme.textTheme.titleMedium?.copyWith(
                  color: visualTheme.textPrimary,
                  fontWeight: FontWeight.w800,
                  height: 1.5,
                ),
              ),
              _CommentExtraTimeLinks(
                links: comment.timeLinks,
                onSeekToTime: onSeekToTime,
              ),
              if (comment.pictures.isNotEmpty) ...[
                const SizedBox(height: 12),
                _CommentPictureGrid(pictures: comment.pictures),
              ],
              const SizedBox(height: 10),
              _CommentActionRow(comment: comment),
              if (showRepliesPreview && comment.replies.isNotEmpty) ...[
                const SizedBox(height: 12),
                _CommentReplyPreview(
                  comment: comment,
                  onSeekToTime: onSeekToTime,
                  onOpenReplies: () => onOpenReplies(comment),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _CommentLevelBadge extends StatelessWidget {
  const _CommentLevelBadge({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final visualTheme = AppVisualTheme.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Color.alphaBlend(
          AppVisualTokens.biliSourcePink.withValues(alpha: 0.12),
          visualTheme.surfaceRaised,
        ),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
        child: Text(
          label,
          style: const TextStyle(
            color: AppVisualTokens.biliSourcePink,
            fontSize: 10,
            fontWeight: FontWeight.w900,
            height: 1.15,
            fontFeatures: [ui.FontFeature.tabularFigures()],
          ),
        ),
      ),
    );
  }
}

class _CommentMessageText extends StatefulWidget {
  const _CommentMessageText({
    required this.message,
    required this.timeLinks,
    required this.onSeekToTime,
    this.style,
  });

  final String message;
  final List<BiliCommentTimeLink> timeLinks;
  final ValueChanged<int> onSeekToTime;
  final TextStyle? style;

  @override
  State<_CommentMessageText> createState() => _CommentMessageTextState();
}

class _CommentMessageTextState extends State<_CommentMessageText> {
  final List<TapGestureRecognizer> _recognizers = <TapGestureRecognizer>[];

  @override
  void initState() {
    super.initState();
    _syncRecognizers();
  }

  @override
  void didUpdateWidget(_CommentMessageText oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.timeLinks != widget.timeLinks ||
        oldWidget.onSeekToTime != widget.onSeekToTime) {
      _syncRecognizers();
    }
  }

  @override
  void dispose() {
    _disposeRecognizers();
    super.dispose();
  }

  void _disposeRecognizers() {
    for (final recognizer in _recognizers) {
      recognizer.dispose();
    }
    _recognizers.clear();
  }

  void _syncRecognizers() {
    _disposeRecognizers();
    for (final link in widget.timeLinks.where(_hasInlineRange)) {
      _recognizers.add(
        TapGestureRecognizer()..onTap = () => widget.onSeekToTime(link.seconds),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final visualTheme = AppVisualTheme.of(context);
    final style =
        widget.style ??
        Theme.of(context).textTheme.bodyMedium?.copyWith(
          color: visualTheme.textPrimary,
          height: 1.5,
        );
    final linkStyle = style?.copyWith(
      color: AppVisualTokens.primaryBlue,
      fontWeight: FontWeight.w900,
      decoration: TextDecoration.none,
    );
    final spans = <InlineSpan>[];
    var cursor = 0;
    var recognizerIndex = 0;
    for (final link in widget.timeLinks.where(_hasInlineRange)) {
      final start = link.start!;
      final end = link.end!;
      if (start < cursor || start > widget.message.length) {
        continue;
      }
      if (cursor < start) {
        spans.add(TextSpan(text: widget.message.substring(cursor, start)));
      }
      spans.add(
        TextSpan(
          text: widget.message.substring(start, end),
          style: linkStyle,
          recognizer: _recognizers[recognizerIndex],
        ),
      );
      recognizerIndex += 1;
      cursor = end;
    }
    if (cursor < widget.message.length) {
      spans.add(TextSpan(text: widget.message.substring(cursor)));
    }

    return RichText(
      text: TextSpan(style: style, children: spans),
      textScaler: MediaQuery.textScalerOf(context),
    );
  }
}

bool _hasInlineRange(BiliCommentTimeLink link) =>
    link.start != null && link.end != null && link.start! < link.end!;

class _CommentExtraTimeLinks extends StatelessWidget {
  const _CommentExtraTimeLinks({
    required this.links,
    required this.onSeekToTime,
  });

  final List<BiliCommentTimeLink> links;
  final ValueChanged<int> onSeekToTime;

  @override
  Widget build(BuildContext context) {
    final extraLinks = links
        .where((link) => !_hasInlineRange(link))
        .toList(growable: false);
    if (extraLinks.isEmpty) {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final link in extraLinks)
            _CommentTimeChip(
              link: link,
              onTap: () => onSeekToTime(link.seconds),
            ),
        ],
      ),
    );
  }
}

class _CommentTimeChip extends StatelessWidget {
  const _CommentTimeChip({required this.link, required this.onTap});

  final BiliCommentTimeLink link;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final visualTheme = AppVisualTheme.of(context);
    return Material(
      color: Color.alphaBlend(
        AppVisualTokens.primaryBlue.withValues(alpha: 0.12),
        visualTheme.surfaceRaised,
      ),
      borderRadius: BorderRadius.circular(999),
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.play_arrow_rounded,
                size: 16,
                color: AppVisualTokens.primaryBlue,
              ),
              const SizedBox(width: 3),
              Text(
                link.label,
                style: const TextStyle(
                  color: AppVisualTokens.primaryBlue,
                  fontSize: 12,
                  fontWeight: FontWeight.w900,
                  height: 1.1,
                  fontFeatures: [ui.FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CommentPictureGrid extends StatelessWidget {
  const _CommentPictureGrid({required this.pictures});

  final List<BiliCommentPicture> pictures;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (pictures.length == 1) {
          final picture = pictures.first;
          final width = constraints.maxWidth.clamp(180.0, 420.0).toDouble();
          final aspectRatio = _pictureAspectRatio(picture).clamp(0.72, 1.78);
          return Align(
            alignment: Alignment.centerLeft,
            child: SizedBox(
              width: width,
              child: AspectRatio(
                aspectRatio: aspectRatio,
                child: _CommentPicture(picture: picture),
              ),
            ),
          );
        }

        final itemWidth = ((constraints.maxWidth - 16) / 3)
            .clamp(76.0, 118.0)
            .toDouble();
        return Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final picture in pictures.take(9))
              SizedBox.square(
                dimension: itemWidth,
                child: _CommentPicture(picture: picture),
              ),
          ],
        );
      },
    );
  }

  double _pictureAspectRatio(BiliCommentPicture picture) {
    final width = picture.width;
    final height = picture.height;
    if (width == null || height == null || width <= 0 || height <= 0) {
      return 16 / 9;
    }
    return width / height;
  }
}

class _CommentPicture extends StatelessWidget {
  const _CommentPicture({required this.picture});

  final BiliCommentPicture picture;

  @override
  Widget build(BuildContext context) {
    final visualTheme = AppVisualTheme.of(context);
    final cacheWidth = (MediaQuery.devicePixelRatioOf(context) * 420)
        .round()
        .clamp(280, 960)
        .toInt();
    return ClipRRect(
      borderRadius: BorderRadius.circular(7),
      child: Stack(
        fit: StackFit.expand,
        children: [
          DecoratedBox(
            decoration: BoxDecoration(color: visualTheme.surfaceRaised),
            child: Image.network(
              picture.url,
              fit: BoxFit.cover,
              cacheWidth: cacheWidth,
              errorBuilder: (_, _, _) => Icon(
                Icons.broken_image_outlined,
                color: visualTheme.textTertiary,
              ),
            ),
          ),
          DecoratedBox(
            decoration: BoxDecoration(
              border: Border.fromBorderSide(
                BorderSide(color: visualTheme.imageOutline),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CommentActionRow extends StatelessWidget {
  const _CommentActionRow({required this.comment});

  final BiliVideoComment comment;

  @override
  Widget build(BuildContext context) {
    final visualTheme = AppVisualTheme.of(context);
    return Row(
      children: [
        _CommentPassiveAction(
          icon: comment.liked
              ? Icons.thumb_up_rounded
              : Icons.thumb_up_alt_outlined,
          label: comment.likeCountLabel,
          selected: comment.liked,
        ),
        const SizedBox(width: 14),
        const _CommentPassiveAction(
          icon: Icons.thumb_down_alt_outlined,
          label: '',
        ),
        const SizedBox(width: 14),
        const _CommentPassiveAction(icon: Icons.ios_share_rounded, label: ''),
        const SizedBox(width: 14),
        const _CommentPassiveAction(
          icon: Icons.mode_comment_outlined,
          label: '',
        ),
        const Spacer(),
        Icon(
          Icons.more_vert_rounded,
          size: 20,
          color: visualTheme.textTertiary,
        ),
      ],
    );
  }
}

class _CommentPassiveAction extends StatelessWidget {
  const _CommentPassiveAction({
    required this.icon,
    required this.label,
    this.selected = false,
  });

  final IconData icon;
  final String label;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final visualTheme = AppVisualTheme.of(context);
    final color = selected
        ? AppVisualTokens.primaryBlue
        : visualTheme.textSecondary;
    return SizedBox(
      height: 40,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 21, color: color),
          if (label.isNotEmpty) ...[
            const SizedBox(width: 5),
            Text(
              label,
              style: TextStyle(
                color: color,
                fontSize: 13,
                fontWeight: FontWeight.w800,
                fontFeatures: const [ui.FontFeature.tabularFigures()],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _CommentReplyPreview extends StatelessWidget {
  const _CommentReplyPreview({
    required this.comment,
    required this.onSeekToTime,
    required this.onOpenReplies,
  });

  final BiliVideoComment comment;
  final ValueChanged<int> onSeekToTime;
  final VoidCallback onOpenReplies;

  @override
  Widget build(BuildContext context) {
    final visualTheme = AppVisualTheme.of(context);
    final replies = comment.replies.take(2).toList(growable: false);
    final total = comment.replyCount > replies.length
        ? comment.replyCount
        : comment.replies.length;
    return SizedBox(
      width: double.infinity,
      child: Material(
        color: visualTheme.surfaceMuted,
        borderRadius: BorderRadius.circular(7),
        child: InkWell(
          borderRadius: BorderRadius.circular(7),
          onTap: onOpenReplies,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 11, 12, 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final reply in replies) ...[
                  _NestedReplyLine(reply: reply, onSeekToTime: onSeekToTime),
                  if (reply != replies.last) const SizedBox(height: 8),
                ],
                if (total > replies.length) ...[
                  const SizedBox(height: 9),
                  Text(
                    '共$total条回复 >',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: AppVisualTokens.primaryBlue,
                      fontWeight: FontWeight.w900,
                      height: 1.2,
                      fontFeatures: const [ui.FontFeature.tabularFigures()],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _NestedReplyLine extends StatelessWidget {
  const _NestedReplyLine({required this.reply, required this.onSeekToTime});

  final BiliVideoComment reply;
  final ValueChanged<int> onSeekToTime;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final visualTheme = AppVisualTheme.of(context);
    return Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Text(
          '${reply.authorName}: ',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: AppVisualTokens.primaryBlue,
            fontWeight: FontWeight.w900,
            height: 1.45,
          ),
        ),
        _CommentMessageText(
          message: reply.message,
          timeLinks: reply.timeLinks,
          onSeekToTime: onSeekToTime,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: visualTheme.textPrimary,
            fontWeight: FontWeight.w700,
            height: 1.45,
          ),
        ),
      ],
    );
  }
}

class _CommentComposerBar extends StatelessWidget {
  const _CommentComposerBar({
    required this.controller,
    required this.focusNode,
    required this.submitting,
    required this.onSubmitted,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final bool submitting;
  final ValueChanged<String> onSubmitted;

  @override
  Widget build(BuildContext context) {
    final visualTheme = AppVisualTheme.of(context);
    return SafeArea(
      top: false,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: visualTheme.surface,
          boxShadow: [
            BoxShadow(
              color: visualTheme.shadow,
              blurRadius: 16,
              offset: Offset(0, -6),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(0, 8, 0, 8),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: controller,
                  focusNode: focusNode,
                  enabled: !submitting,
                  minLines: 1,
                  maxLines: 4,
                  textInputAction: TextInputAction.send,
                  onSubmitted: submitting ? null : onSubmitted,
                  decoration: InputDecoration(
                    hintText: '你猜我的评论区在等谁？',
                    isDense: true,
                    filled: true,
                    fillColor: visualTheme.surfaceRaised,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 18,
                      vertical: 12,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(999),
                      borderSide: BorderSide.none,
                    ),
                    suffixIcon: submitting
                        ? const Padding(
                            padding: EdgeInsets.all(12),
                            child: SizedBox.square(
                              dimension: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                          )
                        : Icon(
                            Icons.sentiment_satisfied_alt_rounded,
                            color: visualTheme.textTertiary,
                          ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              IconButton(
                onPressed: submitting
                    ? null
                    : () => onSubmitted(controller.text),
                constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
                icon: const Icon(
                  Icons.send_rounded,
                  color: AppVisualTokens.primaryBlue,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CommentReplySummary extends StatelessWidget {
  const _CommentReplySummary({required this.totalCount});

  final int totalCount;

  @override
  Widget build(BuildContext context) {
    final visualTheme = AppVisualTheme.of(context);
    return SizedBox(
      width: double.infinity,
      child: DecoratedBox(
        decoration: BoxDecoration(color: visualTheme.surfaceMuted),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  '相关回复共$totalCount条',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: visualTheme.textTertiary,
                    fontWeight: FontWeight.w900,
                    fontFeatures: const [ui.FontFeature.tabularFigures()],
                  ),
                ),
              ),
              Icon(
                Icons.sort_rounded,
                size: 20,
                color: visualTheme.textTertiary,
              ),
              const SizedBox(width: 5),
              Text(
                '按时间',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: visualTheme.textTertiary,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CommentReplyPanel extends StatelessWidget {
  const _CommentReplyPanel({
    required this.comment,
    required this.replies,
    required this.totalCount,
    required this.loading,
    required this.loadingMore,
    required this.hasMore,
    required this.errorMessage,
    required this.controller,
    required this.onClose,
    required this.onLoadMore,
    required this.onRetry,
    required this.onSeekToTime,
  });

  final BiliVideoComment comment;
  final List<BiliVideoComment> replies;
  final int? totalCount;
  final bool loading;
  final bool loadingMore;
  final bool hasMore;
  final String? errorMessage;
  final ScrollController controller;
  final VoidCallback onClose;
  final Future<void> Function() onLoadMore;
  final Future<void> Function() onRetry;
  final ValueChanged<int> onSeekToTime;

  @override
  Widget build(BuildContext context) {
    final visualTheme = AppVisualTheme.of(context);
    return Column(
      children: [
        SizedBox(
          key: const ValueKey<String>('playback-comment-replies-header'),
          height: 54,
          child: Row(
            children: [
              Expanded(
                child: Text(
                  '评论详情',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: visualTheme.textPrimary,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              IconButton(
                onPressed: onClose,
                constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
                tooltip: '关闭评论详情',
                icon: Icon(
                  Icons.close_rounded,
                  size: 28,
                  color: visualTheme.textTertiary,
                ),
              ),
            ],
          ),
        ),
        Divider(height: 1, color: visualTheme.divider),
        Expanded(
          child: ListView.builder(
            key: const PageStorageKey<String>('playback-comment-replies'),
            controller: controller,
            physics: const BouncingScrollPhysics(
              parent: AlwaysScrollableScrollPhysics(),
            ),
            padding: const EdgeInsets.fromLTRB(0, 16, 0, 24),
            itemCount: replies.length + 3,
            itemBuilder: (context, index) {
              if (index == 0) {
                return Padding(
                  padding: const EdgeInsets.only(bottom: 18),
                  child: _CommentTile(
                    comment: comment,
                    onSeekToTime: onSeekToTime,
                    onOpenReplies: (_) {},
                    showRepliesPreview: false,
                  ),
                );
              }
              if (index == 1) {
                final visibleTotal =
                    totalCount ??
                    (comment.replyCount > 0
                        ? comment.replyCount
                        : replies.length);
                return Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: _CommentReplySummary(totalCount: visibleTotal),
                );
              }

              final replyIndex = index - 2;
              if (replyIndex < replies.length) {
                final reply = replies[replyIndex];
                return KeyedSubtree(
                  key: ValueKey<String>('playback-comment-reply-${reply.id}'),
                  child: Column(
                    children: [
                      _CommentTile(
                        comment: reply,
                        onSeekToTime: onSeekToTime,
                        onOpenReplies: (_) {},
                        showRepliesPreview: false,
                      ),
                      if (replyIndex != replies.length - 1)
                        Divider(
                          height: 28,
                          thickness: 0.7,
                          color: visualTheme.divider,
                        ),
                    ],
                  ),
                );
              }

              return _CommentReplyLoadFooter(
                hasReplies: replies.isNotEmpty,
                loading: loading || loadingMore,
                hasMore: hasMore,
                errorMessage: errorMessage,
                onLoadMore: onLoadMore,
                onRetry: onRetry,
              );
            },
          ),
        ),
      ],
    );
  }
}

class _CommentReplyLoadFooter extends StatelessWidget {
  const _CommentReplyLoadFooter({
    required this.hasReplies,
    required this.loading,
    required this.hasMore,
    required this.errorMessage,
    required this.onLoadMore,
    required this.onRetry,
  });

  final bool hasReplies;
  final bool loading;
  final bool hasMore;
  final String? errorMessage;
  final Future<void> Function() onLoadMore;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    final visualTheme = AppVisualTheme.of(context);
    if (loading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 22),
        child: Center(
          child: SizedBox.square(
            dimension: 22,
            child: CircularProgressIndicator(strokeWidth: 2.2),
          ),
        ),
      );
    }
    if (errorMessage case final message?) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 14),
        child: Column(
          children: [
            Text(
              message,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: visualTheme.destructive,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 6),
            TextButton.icon(
              onPressed: () => unawaited(onRetry()),
              icon: const Icon(Icons.refresh_rounded, size: 18),
              label: const Text('重试'),
            ),
          ],
        ),
      );
    }
    if (!hasReplies) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 18),
        child: Center(
          child: Text(
            '暂无相关回复',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: visualTheme.textTertiary,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      );
    }
    if (hasMore) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Center(
          child: TextButton.icon(
            onPressed: () => unawaited(onLoadMore()),
            icon: const Icon(Icons.expand_more_rounded, size: 20),
            label: const Text('加载更多回复'),
          ),
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 18),
      child: Center(
        child: Text(
          '没有更多回复了',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: visualTheme.textTertiary,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
    );
  }
}

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

part 'bili_playback_content_intro.dart';
part 'bili_playback_content_episodes.dart';
part 'bili_playback_content_comments.dart';
part 'bili_playback_content_comment_message.dart';
part 'bili_playback_content_comment_replies.dart';

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

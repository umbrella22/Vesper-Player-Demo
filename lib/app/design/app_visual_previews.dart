import 'package:flutter/widget_previews.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';
import 'package:material_ui/material_ui.dart';
import 'package:qr_flutter/qr_flutter.dart';

import 'package:vesper_media/media/tv/media_tv_focusable.dart';

import 'app_glass_controls.dart';
import 'package:vesper_media/media/design/app_visual_theme.dart';

@Preview(group: 'Vesper Mobile', name: 'Home - light', size: Size(390, 844))
Widget appMobileHomeLightPreview() => _previewApp(
  theme: AppVisualTokens.mobileLightTheme(),
  home: const _MobilePreviewPage(kind: _MobilePreviewKind.home),
);

@Preview(group: 'Vesper Mobile', name: 'Home - dark', size: Size(390, 844))
Widget appMobileHomeDarkPreview() => _previewApp(
  theme: AppVisualTokens.mobileDarkTheme(),
  home: const _MobilePreviewPage(kind: _MobilePreviewKind.home),
);

@Preview(group: 'Vesper Mobile', name: 'Mine - light', size: Size(390, 844))
Widget appMobileMinePreview() => _previewApp(
  theme: AppVisualTokens.mobileLightTheme(),
  home: const _MobilePreviewPage(kind: _MobilePreviewKind.mine),
);

@Preview(group: 'Vesper Mobile', name: 'Settings - dark', size: Size(390, 844))
Widget appMobileSettingsPreview() => _previewApp(
  theme: AppVisualTokens.mobileDarkTheme(),
  home: const _MobilePreviewPage(kind: _MobilePreviewKind.settings),
);

@Preview(group: 'Vesper Mobile', name: 'Playback - light', size: Size(390, 844))
Widget appMobilePlaybackLightPreview() => _previewApp(
  theme: AppVisualTokens.mobileLightTheme(),
  home: const _MobilePlaybackPreview(),
);

@Preview(group: 'Vesper Mobile', name: 'Playback - dark', size: Size(390, 844))
Widget appMobilePlaybackDarkPreview() => _previewApp(
  theme: AppVisualTokens.mobileDarkTheme(),
  home: const _MobilePlaybackPreview(),
);

@Preview(group: 'Vesper Mobile', name: 'Library tabs', size: Size(390, 844))
Widget appMobileLibraryPreview() => _previewApp(
  theme: AppVisualTokens.mobileLightTheme(),
  home: const _MobilePreviewPage(kind: _MobilePreviewKind.library),
);

@Preview(group: 'Vesper Mobile', name: 'QR login', size: Size(390, 844))
Widget appMobileQrLoginPreview() => _previewApp(
  theme: AppVisualTokens.mobileLightTheme(),
  home: const _MobilePreviewPage(kind: _MobilePreviewKind.qr),
);

@Preview(
  group: 'Vesper TV',
  name: 'Home - expanded rail',
  size: Size(1280, 720),
)
Widget appTvExpandedHomePreview() => _previewApp(
  theme: AppVisualTokens.tvTheme(),
  home: const _TvHomePreview(railExpanded: true),
);

@Preview(
  group: 'Vesper TV',
  name: 'Home - collapsed rail',
  size: Size(1280, 720),
)
Widget appTvCollapsedHomePreview() => _previewApp(
  theme: AppVisualTokens.tvTheme(),
  home: const _TvHomePreview(railExpanded: false),
);

@Preview(
  group: 'Vesper TV',
  name: 'Focused content card',
  size: Size(1280, 720),
)
Widget appTvFocusedContentPreview() => _previewApp(
  theme: AppVisualTokens.tvTheme(),
  home: const _TvFocusedContentPreview(),
);

@Preview(group: 'Vesper TV', name: 'Exit dialog', size: Size(1280, 720))
Widget appTvExitDialogPreview() => _previewApp(
  theme: AppVisualTokens.tvTheme(),
  home: const _TvDialogPreview(kind: _TvDialogPreviewKind.exit),
);

@Preview(group: 'Vesper TV', name: 'QR login dialog', size: Size(1280, 720))
Widget appTvQrDialogPreview() => _previewApp(
  theme: AppVisualTokens.tvTheme(),
  home: const _TvDialogPreview(kind: _TvDialogPreviewKind.login),
);

Widget _previewApp({required ThemeData theme, required Widget home}) {
  return MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: theme,
    home: home,
  );
}

class _MobilePlaybackPreview extends StatelessWidget {
  const _MobilePlaybackPreview();

  @override
  Widget build(BuildContext context) {
    final visualTheme = AppVisualTheme.of(context);
    final textTheme = Theme.of(context).textTheme;
    return Scaffold(
      backgroundColor: visualTheme.background,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            ColoredBox(
              color: Colors.black,
              child: AspectRatio(
                aspectRatio: 16 / 9,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    const Center(
                      child: Icon(
                        Icons.play_circle_fill_rounded,
                        color: Color(0xCCFFFFFF),
                        size: 58,
                      ),
                    ),
                    Positioned(
                      left: 8,
                      top: 8,
                      child: IconButton(
                        onPressed: _noop,
                        tooltip: '返回',
                        icon: const Icon(
                          Icons.arrow_back_rounded,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Expanded(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: visualTheme.surface,
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(20),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: visualTheme.shadow,
                      blurRadius: 18,
                      offset: const Offset(0, -4),
                    ),
                  ],
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(
                        height: 46,
                        child: Row(
                          children: [
                            Text(
                              '简介',
                              style: textTheme.titleMedium?.copyWith(
                                color: AppVisualTokens.primaryBlue,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            const SizedBox(width: 24),
                            Text(
                              '评论 1.2万',
                              style: textTheme.titleMedium?.copyWith(
                                color: visualTheme.textSecondary,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const Spacer(),
                            Icon(
                              Icons.chat_bubble_outline_rounded,
                              color: visualTheme.textTertiary,
                              size: 18,
                            ),
                          ],
                        ),
                      ),
                      Divider(height: 1, color: visualTheme.divider),
                      Expanded(
                        child: ListView(
                          padding: const EdgeInsets.only(top: 16, bottom: 28),
                          children: [
                            Row(
                              children: [
                                const CircleAvatar(
                                  radius: 22,
                                  backgroundColor: AppVisualTokens.primaryBlue,
                                  child: Text(
                                    'V',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'Vesper 影像',
                                        style: textTheme.titleMedium?.copyWith(
                                          color: visualTheme.textPrimary,
                                          fontWeight: FontWeight.w800,
                                        ),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        '12.8万粉丝  ·  428个视频',
                                        style: textTheme.bodySmall?.copyWith(
                                          color: visualTheme.textTertiary,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                FilledButton(
                                  onPressed: _noop,
                                  child: const Text('关注'),
                                ),
                              ],
                            ),
                            const SizedBox(height: 18),
                            Text(
                              '在城市的夜色里，重新发现熟悉的声音',
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: textTheme.titleLarge?.copyWith(
                                color: visualTheme.textPrimary,
                                fontWeight: FontWeight.w900,
                                height: 1.18,
                              ),
                            ),
                            const SizedBox(height: 9),
                            Text(
                              '28.6万播放  ·  4,812弹幕  ·  今天 18:30',
                              style: textTheme.bodyMedium?.copyWith(
                                color: visualTheme.textTertiary,
                              ),
                            ),
                            const SizedBox(height: 12),
                            Text(
                              '记录一段城市散步，也记录声音与光线在同一个夜晚发生的变化。',
                              maxLines: 3,
                              overflow: TextOverflow.ellipsis,
                              style: textTheme.bodyMedium?.copyWith(
                                color: visualTheme.textSecondary,
                                height: 1.55,
                              ),
                            ),
                            const SizedBox(height: 18),
                            Row(
                              children: const [
                                Expanded(
                                  child: _PlaybackPreviewAction(
                                    icon: Icons.thumb_up_alt_outlined,
                                    label: '2.8万',
                                  ),
                                ),
                                Expanded(
                                  child: _PlaybackPreviewAction(
                                    icon: Icons.monetization_on_outlined,
                                    label: '1,204',
                                  ),
                                ),
                                Expanded(
                                  child: _PlaybackPreviewAction(
                                    icon: Icons.star_border_rounded,
                                    label: '8,642',
                                  ),
                                ),
                                Expanded(
                                  child: _PlaybackPreviewAction(
                                    icon: Icons.ios_share_rounded,
                                    label: '326',
                                  ),
                                ),
                                Expanded(
                                  child: _PlaybackPreviewAction(
                                    icon: Icons.bookmark_border_rounded,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 22),
                            Text(
                              '相关推荐',
                              style: textTheme.titleMedium?.copyWith(
                                color: visualTheme.textPrimary,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                            const SizedBox(height: 12),
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Container(
                                  width: 142,
                                  height: 82,
                                  decoration: BoxDecoration(
                                    color: visualTheme.surfaceRaised,
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(
                                      color: visualTheme.imageOutline,
                                    ),
                                  ),
                                  child: Icon(
                                    Icons.movie_outlined,
                                    color: visualTheme.textTertiary,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        '夜间城市影像的拍摄与调色记录',
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                        style: textTheme.titleMedium?.copyWith(
                                          color: visualTheme.textPrimary,
                                          fontWeight: FontWeight.w800,
                                        ),
                                      ),
                                      const SizedBox(height: 8),
                                      Text(
                                        'Vesper 影像',
                                        style: textTheme.bodyMedium?.copyWith(
                                          color: visualTheme.textTertiary,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PlaybackPreviewAction extends StatelessWidget {
  const _PlaybackPreviewAction({required this.icon, this.label});

  final IconData icon;
  final String? label;

  @override
  Widget build(BuildContext context) {
    final visualTheme = AppVisualTheme.of(context);
    return SizedBox(
      height: 56,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, color: visualTheme.textSecondary, size: 22),
          if (label != null) ...[
            const SizedBox(height: 3),
            Text(
              label!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: visualTheme.textTertiary,
                fontSize: 11,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

enum _MobilePreviewKind { home, mine, settings, library, qr }

class _MobilePreviewPage extends StatefulWidget {
  const _MobilePreviewPage({required this.kind});

  final _MobilePreviewKind kind;

  @override
  State<_MobilePreviewPage> createState() => _MobilePreviewPageState();
}

class _MobilePreviewPageState extends State<_MobilePreviewPage> {
  int _selectedSection = 1;

  @override
  Widget build(BuildContext context) {
    final visualTheme = AppVisualTheme.of(context);
    final nested =
        widget.kind == _MobilePreviewKind.settings ||
        widget.kind == _MobilePreviewKind.library;
    final selectedBottomIndex = widget.kind == _MobilePreviewKind.mine ? 1 : 0;
    final pageTitle = switch (widget.kind) {
      _MobilePreviewKind.settings => '设置',
      _MobilePreviewKind.library => '我的内容',
      _ => 'Vesper',
    };

    final scaffold = AppGlassScaffold(
      backgroundColor: visualTheme.background,
      extendBody: !nested,
      appBar: GlassAppBar(
        centerTitle: false,
        leading: nested
            ? const IconButton(
                onPressed: _noop,
                icon: Icon(Icons.arrow_back_ios_new_rounded),
              )
            : null,
        title: Text(pageTitle),
        actions: widget.kind == _MobilePreviewKind.home
            ? const [
                IconButton(
                  onPressed: _noop,
                  tooltip: '搜索',
                  icon: Icon(Icons.search_rounded),
                ),
              ]
            : null,
      ),
      bottomBarHeight: nested ? null : AppGlassBottomNavigation.extent,
      bottomBar: nested
          ? null
          : AppGlassBottomNavigation(
              selectedIndex: selectedBottomIndex,
              onSelected: (_) {},
              items: const [
                AppGlassNavigationItem(
                  label: '首页',
                  icon: Icons.home_outlined,
                  activeIcon: Icons.home_rounded,
                ),
                AppGlassNavigationItem(
                  label: '我的',
                  icon: Icons.person_outline_rounded,
                  activeIcon: Icons.person_rounded,
                ),
              ],
            ),
      body: switch (widget.kind) {
        _MobilePreviewKind.home ||
        _MobilePreviewKind.qr => const _MobileHomeContent(),
        _MobilePreviewKind.mine => const _MobileMineContent(),
        _MobilePreviewKind.settings => const _MobileSettingsContent(),
        _MobilePreviewKind.library => _MobileLibraryContent(
          selectedIndex: _selectedSection,
          onSelected: (index) => setState(() => _selectedSection = index),
        ),
      },
    );

    if (widget.kind != _MobilePreviewKind.qr) {
      return scaffold;
    }
    return Stack(children: [scaffold, const _MobileQrOverlay()]);
  }
}

class _MobileHomeContent extends StatelessWidget {
  const _MobileHomeContent();

  @override
  Widget build(BuildContext context) {
    final visualTheme = AppVisualTheme.of(context);
    return ListView(
      padding: EdgeInsets.fromLTRB(
        16,
        16,
        16,
        AppGlassBottomNavigation.contentClearance(context),
      ),
      children: [
        Text(
          '继续观看',
          style: Theme.of(context).textTheme.titleLarge?.copyWith(
            color: visualTheme.textPrimary,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 12),
        Material(
          color: visualTheme.surface,
          borderRadius: BorderRadius.circular(AppVisualTokens.contentRadius),
          clipBehavior: Clip.antiAlias,
          child: SizedBox(
            height: 148,
            child: Row(
              children: [
                Container(
                  width: 136,
                  color: visualTheme.surfaceRaised,
                  alignment: Alignment.center,
                  child: Icon(
                    Icons.play_circle_fill_rounded,
                    color: visualTheme.textTertiary,
                    size: 46,
                  ),
                ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '从上次离开的地方继续',
                          maxLines: 2,
                          style: TextStyle(
                            color: visualTheme.textPrimary,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const Spacer(),
                        Text(
                          '已观看 18:42 / 46:12',
                          style: TextStyle(
                            color: visualTheme.textSecondary,
                            fontSize: 12,
                          ),
                        ),
                        const SizedBox(height: 8),
                        const LinearProgressIndicator(value: 0.41),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 24),
        Text(
          '为你推荐',
          style: Theme.of(context).textTheme.titleLarge?.copyWith(
            color: visualTheme.textPrimary,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 12),
        GridView.count(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisCount: 2,
          crossAxisSpacing: 10,
          mainAxisSpacing: 14,
          childAspectRatio: 0.86,
          children: const [
            _MobileVideoCard(title: '城市漫游与夜色', subtitle: '影像记录'),
            _MobileVideoCard(title: '这一期聊聊声音', subtitle: '创作频道'),
            _MobileVideoCard(title: '周末的料理实验', subtitle: '生活方式'),
            _MobileVideoCard(title: '设计背后的故事', subtitle: '灵感收藏'),
          ],
        ),
      ],
    );
  }
}

class _MobileVideoCard extends StatelessWidget {
  const _MobileVideoCard({required this.title, required this.subtitle});

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final visualTheme = AppVisualTheme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Container(
            decoration: BoxDecoration(
              color: visualTheme.surfaceRaised,
              borderRadius: BorderRadius.circular(
                AppVisualTokens.contentRadius,
              ),
              border: Border.all(color: visualTheme.imageOutline),
            ),
            alignment: Alignment.center,
            child: Icon(
              Icons.movie_outlined,
              color: visualTheme.textTertiary,
              size: 38,
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: visualTheme.textPrimary,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 3),
        Text(
          subtitle,
          maxLines: 1,
          style: TextStyle(color: visualTheme.textSecondary, fontSize: 12),
        ),
      ],
    );
  }
}

class _MobileMineContent extends StatelessWidget {
  const _MobileMineContent();

  @override
  Widget build(BuildContext context) {
    final visualTheme = AppVisualTheme.of(context);
    return ListView(
      padding: EdgeInsets.fromLTRB(
        16,
        20,
        16,
        AppGlassBottomNavigation.contentClearance(context),
      ),
      children: [
        Row(
          children: [
            CircleAvatar(
              radius: 30,
              backgroundColor: visualTheme.surfaceRaised,
              child: const Text(
                '若',
                style: TextStyle(
                  color: AppVisualTokens.primaryBlue,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '若~梦',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'B 币 14.5 · 硬币 1010.5',
                    style: TextStyle(color: visualTheme.textSecondary),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right_rounded, color: visualTheme.textTertiary),
          ],
        ),
        const SizedBox(height: 22),
        const Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            _PreviewStat(value: '68', label: '动态'),
            _PreviewStat(value: '2772', label: '关注'),
            _PreviewStat(value: '1500', label: '粉丝'),
          ],
        ),
        const AppSectionLabel('常用功能'),
        AppGroupedSurface(
          padding: const EdgeInsets.symmetric(vertical: 16),
          children: const [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _PreviewShortcut(icon: Icons.download_rounded, label: '离线缓存'),
                _PreviewShortcut(icon: Icons.history_rounded, label: '历史记录'),
                _PreviewShortcut(
                  icon: Icons.people_outline_rounded,
                  label: '关注列表',
                ),
                _PreviewShortcut(
                  icon: Icons.watch_later_outlined,
                  label: '稍后再看',
                ),
              ],
            ),
          ],
        ),
        const AppSectionLabel('更多服务'),
        const AppGroupedSurface(
          children: [
            AppSettingsRow(icon: Icons.tune_rounded, title: '设置', onTap: _noop),
          ],
        ),
      ],
    );
  }
}

class _PreviewStat extends StatelessWidget {
  const _PreviewStat({required this.value, required this.label});

  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    final visualTheme = AppVisualTheme.of(context);
    return Column(
      children: [
        Text(
          value,
          style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: TextStyle(color: visualTheme.textSecondary, fontSize: 12),
        ),
      ],
    );
  }
}

class _PreviewShortcut extends StatelessWidget {
  const _PreviewShortcut({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final visualTheme = AppVisualTheme.of(context);
    return SizedBox(
      width: 70,
      child: Column(
        children: [
          AppIconTile(icon: icon, color: visualTheme.textPrimary),
          const SizedBox(height: 8),
          Text(
            label,
            maxLines: 1,
            style: TextStyle(color: visualTheme.textSecondary, fontSize: 11),
          ),
        ],
      ),
    );
  }
}

class _MobileSettingsContent extends StatelessWidget {
  const _MobileSettingsContent();

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
      children: const [
        AppSectionLabel('外观'),
        AppGroupedSurface(
          children: [
            AppSettingsRow(
              icon: Icons.brightness_auto_rounded,
              title: '显示主题',
              subtitle: '跟随系统明暗模式',
              trailing: _PreviewTrailingLabel('自动'),
              onTap: _noop,
            ),
            AppSettingsRow(
              icon: Icons.tv_rounded,
              title: '强制 TV 模式',
              subtitle: '在手机和平板使用 TV 界面',
              trailing: Switch(value: true, onChanged: _noopBool),
            ),
          ],
        ),
        AppSectionLabel('账号'),
        AppGroupedSurface(
          children: [
            AppSettingsRow(
              icon: Icons.account_circle_outlined,
              title: 'Bilibili 账号',
              subtitle: '登录状态已保存在本机',
              iconColor: AppVisualTokens.biliSourcePink,
              onTap: _noop,
            ),
          ],
        ),
        AppSectionLabel('关于'),
        AppGroupedSurface(
          children: [
            AppSettingsRow(
              icon: Icons.info_outline_rounded,
              title: 'Vesper',
              subtitle: 'Vesper 媒体客户端',
              trailing: _PreviewTrailingLabel('1.2.0'),
            ),
          ],
        ),
      ],
    );
  }
}

class _PreviewTrailingLabel extends StatelessWidget {
  const _PreviewTrailingLabel(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      style: TextStyle(color: AppVisualTheme.of(context).textSecondary),
    );
  }
}

class _MobileLibraryContent extends StatelessWidget {
  const _MobileLibraryContent({
    required this.selectedIndex,
    required this.onSelected,
  });

  final int selectedIndex;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 10),
          child: AppGlassSectionTabs(
            selectedIndex: selectedIndex,
            onSelected: onSelected,
            items: const [
              AppGlassNavigationItem(
                label: '关注',
                icon: Icons.people_alt_outlined,
              ),
              AppGlassNavigationItem(
                label: '历史播放',
                icon: Icons.history_rounded,
              ),
              AppGlassNavigationItem(
                label: '稍后再看',
                icon: Icons.watch_later_outlined,
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView.separated(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 28),
            itemCount: 6,
            separatorBuilder: (_, _) => const SizedBox(height: 8),
            itemBuilder: (context, index) => _PreviewLibraryRow(index: index),
          ),
        ),
      ],
    );
  }
}

class _PreviewLibraryRow extends StatelessWidget {
  const _PreviewLibraryRow({required this.index});

  final int index;

  @override
  Widget build(BuildContext context) {
    final visualTheme = AppVisualTheme.of(context);
    return Material(
      color: visualTheme.surface,
      borderRadius: BorderRadius.circular(AppVisualTokens.contentRadius),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Row(
          children: [
            Container(
              width: 112,
              height: 68,
              decoration: BoxDecoration(
                color: visualTheme.surfaceRaised,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: visualTheme.imageOutline),
              ),
              child: Icon(
                Icons.movie_outlined,
                color: visualTheme.textTertiary,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '历史内容 ${index + 1}',
                    style: TextStyle(
                      color: visualTheme.textPrimary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '昨天 · 已观看 42%',
                    style: TextStyle(
                      color: visualTheme.textSecondary,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MobileQrOverlay extends StatelessWidget {
  const _MobileQrOverlay();

  @override
  Widget build(BuildContext context) {
    final visualTheme = AppVisualTheme.of(context);
    return Positioned.fill(
      child: ColoredBox(
        color: visualTheme.scrim,
        child: SafeArea(
          child: Align(
            alignment: Alignment.bottomCenter,
            child: GlassContainer(
              useOwnLayer: true,
              quality: GlassQuality.minimal,
              margin: const EdgeInsets.all(12),
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 22),
              shape: const LiquidRoundedSuperellipse(
                borderRadius: AppVisualTokens.sheetRadius,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 210,
                    height: 210,
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: QrImageView(
                      data: 'https://vesper.local/login-preview',
                      backgroundColor: Colors.white,
                      eyeStyle: const QrEyeStyle(
                        eyeShape: QrEyeShape.square,
                        color: Colors.black,
                      ),
                      dataModuleStyle: const QrDataModuleStyle(
                        dataModuleShape: QrDataModuleShape.square,
                        color: Colors.black,
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    '使用 Bilibili 客户端扫码登录',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: visualTheme.textPrimary,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '二维码始终使用纯白实体面板',
                    style: TextStyle(color: visualTheme.textSecondary),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _TvHomePreview extends StatelessWidget {
  const _TvHomePreview({required this.railExpanded});

  final bool railExpanded;

  @override
  Widget build(BuildContext context) {
    final railWidth = railExpanded ? 238.0 : 76.0;
    return Scaffold(
      backgroundColor: AppVisualTokens.tvBackground,
      body: Stack(
        children: [
          const Positioned.fill(child: ColoredBox(color: Color(0xFF25313D))),
          const Positioned.fill(child: ColoredBox(color: Color(0x99000000))),
          Positioned(
            left: railWidth + 56,
            top: 78,
            right: 38,
            bottom: 26,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '继续观看',
                  style: TextStyle(
                    color: AppVisualTokens.primaryBlue,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 10),
                const Text(
                  '六年后，我回来了',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 40,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 6),
                const Text(
                  '荒岛新旅程 · 第 3 话 · 46 分钟',
                  style: TextStyle(color: Color(0xD9FFFFFF), fontSize: 16),
                ),
                const SizedBox(height: 18),
                const Row(
                  children: [
                    _TvAction(label: '继续播放', primary: true),
                    SizedBox(width: 12),
                    _TvAction(label: '详情'),
                  ],
                ),
                const Spacer(),
                const Text(
                  '为你推荐',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 24,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  height: 138,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: 5,
                    separatorBuilder: (_, _) => const SizedBox(width: 14),
                    itemBuilder: (_, index) => _TvShelfCard(index: index),
                  ),
                ),
              ],
            ),
          ),
          Positioned(
            left: 20,
            top: 20,
            bottom: 20,
            width: railWidth,
            child: GlassContainer(
              useOwnLayer: true,
              quality: GlassQuality.minimal,
              padding: EdgeInsets.symmetric(
                horizontal: railExpanded ? 16 : 10,
                vertical: 18,
              ),
              shape: const LiquidRoundedSuperellipse(borderRadius: 18),
              child: _TvRailContents(expanded: railExpanded),
            ),
          ),
        ],
      ),
    );
  }
}

class _TvRailContents extends StatelessWidget {
  const _TvRailContents({required this.expanded});

  final bool expanded;

  @override
  Widget build(BuildContext context) {
    const items = <(IconData, String)>[
      (Icons.home_rounded, '为你推荐'),
      (Icons.grid_view_rounded, '分区'),
      (Icons.search_rounded, '搜索'),
      (Icons.history_rounded, '历史记录'),
      (Icons.person_outline_rounded, '我的'),
      (Icons.settings_outlined, '设置'),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          mainAxisAlignment: expanded
              ? MainAxisAlignment.start
              : MainAxisAlignment.center,
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(9),
              ),
              child: const Icon(
                Icons.play_arrow_rounded,
                color: Color(0xFF111318),
              ),
            ),
            if (expanded) ...[
              const SizedBox(width: 12),
              const Text(
                'VESPER',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: 28),
        for (var index = 0; index < items.length; index++) ...[
          Container(
            height: 48,
            decoration: BoxDecoration(
              color: index == 0 ? const Color(0x29FFFFFF) : Colors.transparent,
              borderRadius: BorderRadius.circular(12),
              border: index == 0
                  ? const Border(
                      left: BorderSide(
                        color: AppVisualTokens.primaryBlue,
                        width: 3,
                      ),
                    )
                  : null,
            ),
            child: Row(
              mainAxisAlignment: expanded
                  ? MainAxisAlignment.start
                  : MainAxisAlignment.center,
              children: [
                if (expanded) const SizedBox(width: 14),
                Icon(items[index].$1, color: const Color(0xE6FFFFFF), size: 22),
                if (expanded) ...[
                  const SizedBox(width: 12),
                  Text(
                    items[index].$2,
                    style: const TextStyle(
                      color: Color(0xE6FFFFFF),
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 6),
        ],
      ],
    );
  }
}

class _TvAction extends StatelessWidget {
  const _TvAction({required this.label, this.primary = false});

  final String label;
  final bool primary;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 46,
      padding: const EdgeInsets.symmetric(horizontal: 24),
      decoration: BoxDecoration(
        color: primary ? AppVisualTokens.primaryBlue : const Color(0x33FFFFFF),
        borderRadius: BorderRadius.circular(12),
        border: primary ? null : Border.all(color: const Color(0x38FFFFFF)),
      ),
      alignment: Alignment.center,
      child: Text(
        label,
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

class _TvShelfCard extends StatelessWidget {
  const _TvShelfCard({required this.index});

  final int index;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 208,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: Color.lerp(
                  const Color(0xFF38434D),
                  const Color(0xFF202830),
                  index / 5,
                ),
                borderRadius: BorderRadius.circular(
                  AppVisualTokens.contentRadius,
                ),
                border: Border.all(color: const Color(0x1FFFFFFF)),
              ),
              child: const Center(
                child: Icon(
                  Icons.movie_outlined,
                  color: Color(0x99FFFFFF),
                  size: 34,
                ),
              ),
            ),
          ),
          const SizedBox(height: 7),
          Text(
            '推荐内容 ${index + 1}',
            maxLines: 1,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _TvFocusedContentPreview extends StatelessWidget {
  const _TvFocusedContentPreview();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppVisualTokens.tvBackground,
      body: Center(
        child: SizedBox(
          width: 360,
          height: 245,
          child: Overlay.wrap(
            child: TvFocusableSurface(
              autofocus: true,
              onTap: _noop,
              debugLabel: 'preview_content_card',
              builder: (context, focused) => Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Container(
                      decoration: BoxDecoration(
                        color: const Color(0xFF303840),
                        borderRadius: BorderRadius.circular(
                          AppVisualTokens.contentRadius,
                        ),
                      ),
                      alignment: Alignment.center,
                      child: const Icon(
                        Icons.movie_outlined,
                        color: Color(0xB3FFFFFF),
                        size: 58,
                      ),
                    ),
                  ),
                  const Padding(
                    padding: EdgeInsets.only(top: 10),
                    child: Text(
                      '聚焦时仅叠加一个玻璃透镜',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

enum _TvDialogPreviewKind { exit, login }

class _TvDialogPreview extends StatelessWidget {
  const _TvDialogPreview({required this.kind});

  final _TvDialogPreviewKind kind;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF25313D),
      body: Stack(
        children: [
          const Positioned.fill(child: ColoredBox(color: Color(0xCC000000))),
          Center(
            child: kind == _TvDialogPreviewKind.exit
                ? const _TvExitPanel()
                : const _TvLoginPanel(),
          ),
        ],
      ),
    );
  }
}

class _TvExitPanel extends StatelessWidget {
  const _TvExitPanel();

  @override
  Widget build(BuildContext context) {
    return GlassContainer(
      useOwnLayer: true,
      quality: GlassQuality.minimal,
      width: 690,
      padding: const EdgeInsets.all(36),
      shape: const LiquidRoundedSuperellipse(borderRadius: 24),
      child: const Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '退出 Vesper？',
            style: TextStyle(
              color: Colors.white,
              fontSize: 30,
              fontWeight: FontWeight.w800,
            ),
          ),
          SizedBox(height: 10),
          Text(
            '当前播放进度会自动保留。',
            style: TextStyle(color: Color(0xB3FFFFFF), fontSize: 17),
          ),
          SizedBox(height: 28),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              _TvDialogButton(label: '退出应用', destructive: true),
              SizedBox(width: 14),
              _TvDialogButton(label: '继续观看', focused: true),
            ],
          ),
        ],
      ),
    );
  }
}

class _TvLoginPanel extends StatelessWidget {
  const _TvLoginPanel();

  @override
  Widget build(BuildContext context) {
    return GlassContainer(
      useOwnLayer: true,
      quality: GlassQuality.minimal,
      width: 930,
      padding: const EdgeInsets.all(34),
      shape: const LiquidRoundedSuperellipse(borderRadius: 24),
      child: Row(
        children: [
          Container(
            width: 292,
            height: 292,
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(18),
            ),
            child: QrImageView(
              data: 'https://vesper.local/tv-login-preview',
              backgroundColor: Colors.white,
            ),
          ),
          const SizedBox(width: 42),
          const Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '登录 Bilibili',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 30,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                SizedBox(height: 14),
                Text(
                  '使用手机客户端扫描左侧二维码。\n确认后，Vesper 会自动恢复当前页面。',
                  style: TextStyle(
                    color: Color(0xB3FFFFFF),
                    fontSize: 17,
                    height: 1.55,
                  ),
                ),
                SizedBox(height: 30),
                Row(
                  children: [
                    _TvDialogButton(label: '刷新二维码', focused: true),
                    SizedBox(width: 14),
                    _TvDialogButton(label: '取消'),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _TvDialogButton extends StatelessWidget {
  const _TvDialogButton({
    required this.label,
    this.focused = false,
    this.destructive = false,
  });

  final String label;
  final bool focused;
  final bool destructive;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 50,
      padding: const EdgeInsets.symmetric(horizontal: 22),
      decoration: BoxDecoration(
        color: focused
            ? const Color(0xFFF4F6FA)
            : destructive
            ? const Color(0x24FF7B83)
            : const Color(0x16FFFFFF),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: focused
              ? const Color(0xB3FFFFFF)
              : destructive
              ? const Color(0x42FF8A83)
              : const Color(0x24FFFFFF),
        ),
      ),
      alignment: Alignment.center,
      child: Text(
        label,
        style: TextStyle(
          color: focused
              ? const Color(0xFF111318)
              : destructive
              ? const Color(0xFFFFA1A7)
              : Colors.white,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

void _noop() {}

void _noopBool(bool _) {}

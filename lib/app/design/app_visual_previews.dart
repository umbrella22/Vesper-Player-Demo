import 'package:flutter/widget_previews.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';
import 'package:material_ui/material_ui.dart';

import 'package:bilibili_player/bili/tv_mode/widgets/tv_focusable.dart';

import 'app_glass_controls.dart';
import 'app_visual_theme.dart';

@Preview(
  group: 'Liquid Glass',
  name: 'Mobile light controls',
  size: Size(390, 844),
)
Widget appMobileGlassPreview() {
  return MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: AppVisualTokens.lightTheme(),
    home: const _MobileGlassPreview(),
  );
}

@Preview(group: 'Liquid Glass', name: 'TV rail states', size: Size(1280, 720))
Widget appTvGlassRailPreview() {
  return MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: AppVisualTokens.darkTheme(),
    home: const _TvGlassRailPreview(),
  );
}

@Preview(
  group: 'Liquid Glass',
  name: 'TV focused content',
  size: Size(1920, 1080),
)
Widget appTvFocusedContentPreview() {
  return MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: AppVisualTokens.darkTheme(),
    home: const _TvFocusedContentPreview(),
  );
}

class _MobileGlassPreview extends StatefulWidget {
  const _MobileGlassPreview();

  @override
  State<_MobileGlassPreview> createState() => _MobileGlassPreviewState();
}

class _MobileGlassPreviewState extends State<_MobileGlassPreview> {
  final ScrollController _scrollController = ScrollController();
  bool _enabled = true;
  int _selectedTab = 0;
  int _selectedSection = 0;

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AppGlassScaffold(
      backgroundColor: AppVisualTokens.mobileBackground,
      extendBody: true,
      bottomBarHeight: AppGlassBottomNavigation.extent,
      appBar: AppFrostedScrollAppBar(
        scrollController: _scrollController,
        child: const GlassAppBar(centerTitle: false, title: Text('Vesper 媒体库')),
      ),
      bottomBar: AppGlassBottomNavigation(
        selectedIndex: _selectedTab,
        onSelected: (index) => setState(() => _selectedTab = index),
        items: const [
          AppGlassNavigationItem(
            label: '首页',
            icon: Icons.home_outlined,
            activeIcon: Icons.home_rounded,
          ),
          AppGlassNavigationItem(
            label: '媒体库',
            icon: Icons.video_library_outlined,
            activeIcon: Icons.video_library_rounded,
          ),
        ],
      ),
      body: ListView(
        controller: _scrollController,
        padding: EdgeInsets.fromLTRB(
          16,
          16,
          16,
          AppGlassBottomNavigation.contentClearance(context),
        ),
        children: [
          GlassContainer(
            useOwnLayer: true,
            quality: GlassQuality.standard,
            shape: const LiquidRoundedSuperellipse(
              borderRadius: AppVisualTokens.controlRadius,
            ),
            child: const TextField(
              decoration: InputDecoration(
                hintText: '搜索视频',
                prefixIcon: Icon(Icons.search_rounded),
                fillColor: Colors.transparent,
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
              ),
            ),
          ),
          const SizedBox(height: 18),
          AppGlassSectionTabs(
            selectedIndex: _selectedSection,
            onSelected: (index) => setState(() => _selectedSection = index),
            items: const [
              AppGlassNavigationItem(
                label: '关注',
                icon: Icons.people_alt_outlined,
                activeIcon: Icons.people_alt_rounded,
              ),
              AppGlassNavigationItem(
                label: '历史播放',
                icon: Icons.history_rounded,
              ),
              AppGlassNavigationItem(
                label: '稍后再看',
                icon: Icons.watch_later_outlined,
                activeIcon: Icons.watch_later_rounded,
              ),
            ],
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              const Expanded(
                child: AppGlassButton(
                  label: '开始播放',
                  icon: Icons.play_arrow_rounded,
                  onPressed: _noop,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: AppGlassButton(
                  label: '不可用',
                  enabled: false,
                  onPressed: _noop,
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
            child: Row(
              children: [
                const Expanded(child: Text('自动播放下一集')),
                GlassSwitch(
                  value: _enabled,
                  onChanged: (value) => setState(() => _enabled = value),
                  activeColor: AppVisualTokens.primaryBlue,
                  useOwnLayer: true,
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          const Card(
            child: ListTile(
              leading: Icon(Icons.video_library_outlined),
              title: Text('内容卡片保持实体表面'),
              subtitle: Text('封面、评论与下载条目不使用玻璃'),
            ),
          ),
          const SizedBox(height: 18),
          GlassDialog(
            title: '清理缓存？',
            message: '此操作不会影响账号数据。',
            quality: GlassQuality.standard,
            actions: const [
              GlassDialogAction(label: '取消', onPressed: _noop),
              GlassDialogAction(
                label: '清理',
                onPressed: _noop,
                isDestructive: true,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _TvGlassRailPreview extends StatelessWidget {
  const _TvGlassRailPreview();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppVisualTokens.tvBackground,
      body: Center(
        child: SizedBox(
          width: 260,
          child: AdaptiveLiquidGlassLayer(
            quality: GlassQuality.standard,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: const [
                _PreviewSelectable(label: '普通', icon: Icons.home_outlined),
                SizedBox(height: 8),
                _PreviewSelectable(
                  label: '已选中',
                  icon: Icons.grid_view_rounded,
                  selected: true,
                ),
                SizedBox(height: 8),
                _PreviewSelectable(
                  label: '当前焦点',
                  icon: Icons.search_rounded,
                  autofocus: true,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _PreviewSelectable extends StatelessWidget {
  const _PreviewSelectable({
    required this.label,
    required this.icon,
    this.selected = false,
    this.autofocus = false,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    return TvGlassSelectable(
      selected: selected,
      autofocus: autofocus,
      useOwnLayer: false,
      debugLabel: 'preview_$label',
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
      onTap: _noop,
      builder: (context, state) => Row(
        children: [
          Container(
            width: 3,
            height: 24,
            color: selected ? AppVisualTokens.primaryBlue : Colors.transparent,
          ),
          const SizedBox(width: 12),
          Icon(icon, color: Colors.white),
          const SizedBox(width: 12),
          Text(
            label,
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
          width: 320,
          height: 220,
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
                      color: const Color(0xFF30343C),
                      alignment: Alignment.center,
                      child: const Icon(
                        Icons.movie_outlined,
                        color: Colors.white70,
                        size: 58,
                      ),
                    ),
                  ),
                  const Padding(
                    padding: EdgeInsets.all(10),
                    child: Text(
                      '聚焦时仅叠加一个玻璃透镜',
                      style: TextStyle(color: Colors.white),
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

void _noop() {}

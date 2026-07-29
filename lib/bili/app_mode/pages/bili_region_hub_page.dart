import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';

import 'package:vesper_media/app/design/app_glass_controls.dart';
import 'package:vesper_media/app/design/app_visual_theme.dart';
import 'package:vesper_media/download/download.dart';
import 'package:vesper_media/bili/common/models/bili_region_models.dart';
import 'package:vesper_media/bili/common/services/bili_client.dart';
import 'package:vesper_media/bili/common/services/bili_history_store.dart';
import 'bili_region_visuals.dart';
import 'bili_region_video_page.dart';

class BiliRegionHubPage extends StatefulWidget {
  const BiliRegionHubPage({
    super.key,
    this.client,
    this.historyStore,
    this.offlineController,
  });

  final BiliClient? client;
  final BiliHistoryStore? historyStore;
  final BiliOfflineDownloadController? offlineController;

  @override
  State<BiliRegionHubPage> createState() => _BiliRegionHubPageState();
}

class _BiliRegionHubPageState extends State<BiliRegionHubPage> {
  late final BiliClient _client;

  @override
  void initState() {
    super.initState();
    _client = widget.client ?? BiliClient.instance;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final visualTheme = AppVisualTheme.of(context);
    final hasSession = _client.hasAuthenticatedSession;
    return AppGlassScaffold(
      backgroundColor: visualTheme.background,
      extendBody: false,
      appBar: GlassAppBar(
        centerTitle: false,
        title: Text(
          '分区',
          style: theme.textTheme.titleLarge?.copyWith(
            color: visualTheme.textPrimary,
            fontWeight: FontWeight.w900,
          ),
        ),
      ),
      body: hasSession ? _buildRegionGrid() : _buildLoginRequired(theme),
    );
  }

  Widget _buildRegionGrid() {
    return LayoutBuilder(
      builder: (context, constraints) {
        return Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 900),
            child: GridView.builder(
              padding: EdgeInsets.fromLTRB(
                16,
                0,
                16,
                12 + MediaQuery.paddingOf(context).bottom,
              ),
              gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: 180,
                mainAxisSpacing: 10,
                crossAxisSpacing: 10,
                childAspectRatio: 1.15,
              ),
              itemCount: biliRegionSections.length,
              itemBuilder: (context, index) {
                final section = biliRegionSections[index];
                return _RegionCard(
                  section: section,
                  onTap: () => _openSection(section),
                );
              },
            ),
          ),
        );
      },
    );
  }

  Widget _buildLoginRequired(ThemeData theme) {
    final visualTheme = AppVisualTheme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.lock_outline_rounded,
              size: 42,
              color: AppVisualTokens.primaryBlue,
            ),
            const SizedBox(height: 12),
            Text(
              '需要登录后查看分区内容',
              textAlign: TextAlign.center,
              style: theme.textTheme.titleMedium?.copyWith(
                color: visualTheme.textPrimary,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '请返回首页完成 Bilibili 登录，再重新进入分类。',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: visualTheme.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _openSection(BiliRegionSection section) async {
    unawaited(
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => BiliRegionVideoPage(
            section: section,
            client: _client,
            historyStore: widget.historyStore,
            offlineController: widget.offlineController,
          ),
        ),
      ),
    );
  }
}

class _RegionCard extends StatelessWidget {
  const _RegionCard({required this.section, required this.onTap});

  final BiliRegionSection section;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final visualTheme = AppVisualTheme.of(context);
    return Material(
      color: visualTheme.surface,
      borderRadius: BorderRadius.circular(AppVisualTokens.contentRadius),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              BiliRegionIcon(section: section, size: 44, iconSize: 24),
              const SizedBox(height: 10),
              Text(
                section.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.titleSmall?.copyWith(
                  color: visualTheme.textPrimary,
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

Color scaffoldBackground(BuildContext context) {
  return AppVisualTheme.of(context).background;
}

import 'dart:async';

import 'package:material_ui/material_ui.dart';

import 'package:bilibili_player/download/download.dart';
import 'package:bilibili_player/bili/common/models/bili_region_models.dart';
import 'package:bilibili_player/bili/common/services/bili_client.dart';
import 'package:bilibili_player/bili/common/services/bili_history_store.dart';
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
    return Scaffold(
      backgroundColor: scaffoldBackground(context),
      appBar: AppBar(
        backgroundColor: scaffoldBackground(context),
        title: Text(
          '分区',
          style: theme.textTheme.titleLarge?.copyWith(
            color: const Color(0xFF20232B),
            fontWeight: FontWeight.w900,
          ),
        ),
      ),
      body: Padding(
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        child: GridView.builder(
          padding: EdgeInsets.only(
            bottom: 12 + MediaQuery.paddingOf(context).bottom,
          ),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 3,
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
    return GestureDetector(
      onTap: onTap,
      child: DecoratedBox(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.all(Radius.circular(18)),
        ),
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
                  color: const Color(0xFF20232B),
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
  final brightness = Theme.of(context).brightness;
  return brightness == Brightness.dark
      ? const Color(0xFF1A1C21)
      : const Color(0xFFF3F6FB);
}

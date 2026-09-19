import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:signals/signals_flutter.dart';

import 'package:vesper_media/app/design/app_glass_controls.dart';
import 'package:vesper_media/bili/common/models/bili_models.dart';
import 'package:vesper_media/bili/common/services/bili_client.dart';
import 'package:vesper_media/media/design/app_visual_theme.dart';

/// 概览中的收藏夹卡片。仅在卡片进入列表构建范围时读取首条收藏的封面。
class BiliFavoriteFolderCard extends StatefulWidget {
  const BiliFavoriteFolderCard({
    super.key,
    required this.client,
    required this.folder,
    required this.reloadToken,
    required this.onTap,
  });

  final BiliClient client;
  final BiliFavoriteFolder folder;
  final Object reloadToken;
  final VoidCallback onTap;

  @override
  State<BiliFavoriteFolderCard> createState() => _BiliFavoriteFolderCardState();
}

class _BiliFavoriteFolderCardState extends State<BiliFavoriteFolderCard> {
  final _coverUrl = signal('');
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    unawaited(_loadCover());
  }

  @override
  void didUpdateWidget(covariant BiliFavoriteFolderCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.client != widget.client ||
        oldWidget.folder.id != widget.folder.id ||
        oldWidget.reloadToken != widget.reloadToken) {
      unawaited(_loadCover());
    }
  }

  Future<void> _loadCover() async {
    final generation = ++_generation;
    final client = widget.client;
    final sessionRevision = client.sessionRevision;
    _coverUrl.value = '';
    if (!client.hasAuthenticatedSession || widget.folder.mediaCount == 0) {
      return;
    }
    try {
      final page = await client.fetchFavoriteItems(
        folderId: widget.folder.id,
        pageSize: 1,
      );
      if (!mounted ||
          generation != _generation ||
          !client.hasAuthenticatedSession ||
          sessionRevision != client.sessionRevision) {
        return;
      }
      _coverUrl.value = page.items.firstOrNull?.coverUrl ?? '';
    } catch (_) {
      // 封面失败保留占位；收藏夹仍可打开，下次刷新时重新获取。
    }
  }

  @override
  void dispose() {
    _coverUrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final visualTheme = AppVisualTheme.of(context);
    const radius = BorderRadius.all(Radius.circular(20));
    final placeholder = ColoredBox(
      color: visualTheme.surfaceRaised,
      child: Icon(Icons.folder_outlined, color: visualTheme.textTertiary),
    );
    return AppPressScale(
      child: Semantics(
        button: true,
        child: Material(
          color: visualTheme.surface,
          borderRadius: radius,
          child: InkWell(
            onTap: widget.onTap,
            borderRadius: radius,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final coverWidth = (constraints.maxWidth * 0.36).clamp(
                    88.0,
                    160.0,
                  );
                  return Row(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: SizedBox(
                          width: coverWidth,
                          height: coverWidth * 9 / 16,
                          child: Stack(
                            fit: StackFit.expand,
                            children: [
                              SignalBuilder(
                                builder: (context) => _coverUrl.value.isEmpty
                                    ? placeholder
                                    : Image.network(
                                        _coverUrl.value,
                                        fit: BoxFit.cover,
                                        excludeFromSemantics: true,
                                        errorBuilder: (_, _, _) => placeholder,
                                      ),
                              ),
                              DecoratedBox(
                                decoration: BoxDecoration(
                                  border: Border.all(
                                    color: visualTheme.imageOutline,
                                  ),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              widget.folder.title,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.titleMedium
                                  ?.copyWith(
                                    color: visualTheme.textPrimary,
                                    fontWeight: FontWeight.w700,
                                  ),
                            ),
                            const SizedBox(height: 12),
                            Text(
                              widget.folder.mediaCount == null
                                  ? '查看内容'
                                  : '${widget.folder.mediaCount} 个内容',
                              style: Theme.of(context).textTheme.bodySmall
                                  ?.copyWith(color: visualTheme.textSecondary),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      Icon(
                        Icons.chevron_right_rounded,
                        size: 20,
                        color: visualTheme.textTertiary,
                      ),
                    ],
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }
}

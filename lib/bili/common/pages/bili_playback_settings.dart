part of 'bili_playback_page.dart';

extension _BiliPlaybackSettingsSurface on _BiliPlaybackPageState {
  Future<void> _showSettingsSurface(
    VesperPlayerController controller, {
    required bool isPortrait,
  }) {
    if (isPortrait) {
      return _showSettingsSheet(controller);
    }
    return _showSettingsDrawer(controller);
  }

  Future<void> _showSettingsDrawer(VesperPlayerController controller) {
    return showGeneralDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
      barrierColor: Colors.black.withValues(alpha: 0.40),
      transitionDuration: const Duration(milliseconds: 220),
      pageBuilder: (dialogContext, _, _) {
        final drawerWidth = (MediaQuery.sizeOf(dialogContext).width * 0.42)
            .clamp(
              MediaQuery.sizeOf(dialogContext).width * 0.28,
              MediaQuery.sizeOf(dialogContext).width * 0.42,
            )
            .toDouble();
        return Align(
          alignment: Alignment.centerLeft,
          child: Material(
            color: const Color(0xFFF4F4F8),
            borderRadius: const BorderRadius.horizontal(
              right: Radius.circular(22),
            ),
            clipBehavior: Clip.antiAlias,
            child: SafeArea(
              right: false,
              child: SizedBox(
                width: drawerWidth,
                height: double.infinity,
                child: ValueListenableBuilder<VesperPlayerSnapshot>(
                  valueListenable: controller.snapshotListenable,
                  builder: (context, sheetSnapshot, _) {
                    return SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(20, 18, 20, 22),
                      child: _buildTuningPanel(
                        context,
                        controller,
                        sheetSnapshot,
                      ),
                    );
                  },
                ),
              ),
            ),
          ),
        );
      },
      transitionBuilder: (context, animation, secondaryAnimation, child) {
        final curved = CurvedAnimation(
          parent: animation,
          curve: Curves.easeOutCubic,
          reverseCurve: Curves.easeInCubic,
        );
        return SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(-1, 0),
            end: Offset.zero,
          ).animate(curved),
          child: child,
        );
      },
    );
  }

  Future<void> _showSettingsSheet(VesperPlayerController controller) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: const Color(0xFFF4F4F8),
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.82,
      ),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (sheetContext) {
        return SafeArea(
          child: Padding(
            padding: EdgeInsets.only(
              left: 22,
              right: 22,
              bottom: 22 + MediaQuery.of(sheetContext).viewInsets.bottom,
            ),
            child: ValueListenableBuilder<VesperPlayerSnapshot>(
              valueListenable: controller.snapshotListenable,
              builder: (context, sheetSnapshot, _) {
                return SingleChildScrollView(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(18),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(18),
                      child: _buildTuningPanel(
                        context,
                        controller,
                        sheetSnapshot,
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        );
      },
    );
  }

  Future<void> _openCacheSurfaceFromSettings(
    BuildContext surfaceContext,
  ) async {
    final size = MediaQuery.sizeOf(context);
    final isPortrait = size.height >= size.width;
    Navigator.of(surfaceContext).pop();
    await Future<void>.delayed(const Duration(milliseconds: 80));
    if (!mounted) {
      return;
    }
    await _showCacheSurface(isPortrait: isPortrait);
  }

  Future<void> _showCacheSurface({required bool isPortrait}) {
    if (isPortrait) {
      return _showCacheSheet();
    }
    return _showCacheDrawer();
  }

  Future<void> _showCacheDrawer() {
    return showGeneralDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
      barrierColor: Colors.black.withValues(alpha: 0.40),
      transitionDuration: const Duration(milliseconds: 220),
      pageBuilder: (dialogContext, _, _) {
        final drawerWidth = (MediaQuery.sizeOf(dialogContext).width * 0.42)
            .clamp(
              MediaQuery.sizeOf(dialogContext).width * 0.28,
              MediaQuery.sizeOf(dialogContext).width * 0.42,
            )
            .toDouble();
        return Align(
          alignment: Alignment.centerLeft,
          child: Material(
            color: const Color(0xFFF4F4F8),
            borderRadius: const BorderRadius.horizontal(
              right: Radius.circular(22),
            ),
            clipBehavior: Clip.antiAlias,
            child: SafeArea(
              right: false,
              child: SizedBox(
                width: drawerWidth,
                height: double.infinity,
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(14, 12, 14, 16),
                  child: BiliCacheDownloadPanel(
                    detail: widget.detail,
                    currentPage: _selectedPage,
                    selectedQualityId: _selectedBiliQualityId,
                    codecPreference: _currentDownloadCodecPreference(),
                    controller: _offlineController,
                    onMessage: _showMessage,
                    client: widget.client,
                    historyStore: widget.historyStore,
                  ),
                ),
              ),
            ),
          ),
        );
      },
      transitionBuilder: (context, animation, secondaryAnimation, child) {
        final curved = CurvedAnimation(
          parent: animation,
          curve: Curves.easeOutCubic,
          reverseCurve: Curves.easeInCubic,
        );
        return SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(-1, 0),
            end: Offset.zero,
          ).animate(curved),
          child: child,
        );
      },
    );
  }

  Future<void> _showCacheSheet() {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: const Color(0xFFF4F4F8),
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.82,
      ),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (sheetContext) {
        return SafeArea(
          child: Padding(
            padding: EdgeInsets.only(
              left: 16,
              right: 16,
              bottom: 16 + MediaQuery.of(sheetContext).viewInsets.bottom,
            ),
            child: SingleChildScrollView(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: BiliCacheDownloadPanel(
                    detail: widget.detail,
                    currentPage: _selectedPage,
                    selectedQualityId: _selectedBiliQualityId,
                    codecPreference: _currentDownloadCodecPreference(),
                    controller: _offlineController,
                    onMessage: _showMessage,
                    client: widget.client,
                    historyStore: widget.historyStore,
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

class TvRemoteShortcuts extends StatelessWidget {
  const TvRemoteShortcuts({
    super.key,
    required this.child,
    this.onPlayPause,
    this.onSeekForward,
    this.onSeekBackward,
    this.onFastForward,
    this.onRewind,
  });

  final Widget child;
  final VoidCallback? onPlayPause;
  final VoidCallback? onSeekForward;
  final VoidCallback? onSeekBackward;
  final VoidCallback? onFastForward;
  final VoidCallback? onRewind;

  @override
  Widget build(BuildContext context) {
    return Shortcuts(
      shortcuts: <ShortcutActivator, Intent>{
        const SingleActivator(LogicalKeyboardKey.mediaPlayPause):
            const _TvMediaPlayPauseIntent(),
        const SingleActivator(LogicalKeyboardKey.mediaPlay):
            const _TvMediaPlayPauseIntent(),
        const SingleActivator(LogicalKeyboardKey.mediaPause):
            const _TvMediaPlayPauseIntent(),
        const SingleActivator(LogicalKeyboardKey.mediaTrackNext):
            const _TvSeekForwardIntent(),
        const SingleActivator(LogicalKeyboardKey.mediaTrackPrevious):
            const _TvSeekBackwardIntent(),
        const SingleActivator(LogicalKeyboardKey.arrowLeft):
            const _TvSeekBackwardIntent(),
        const SingleActivator(LogicalKeyboardKey.arrowRight):
            const _TvSeekForwardIntent(),
        const SingleActivator(LogicalKeyboardKey.mediaFastForward):
            const _TvFastForwardIntent(),
        const SingleActivator(LogicalKeyboardKey.mediaRewind):
            const _TvRewindIntent(),
      },
      child: Actions(
        actions: <Type, Action<Intent>>{
          _TvMediaPlayPauseIntent:
              CallbackAction<_TvMediaPlayPauseIntent>(
                onInvoke: (_) {
                  onPlayPause?.call();
                  return null;
                },
              ),
          _TvSeekForwardIntent:
              CallbackAction<_TvSeekForwardIntent>(
                onInvoke: (_) {
                  onSeekForward?.call();
                  return null;
                },
              ),
          _TvSeekBackwardIntent:
              CallbackAction<_TvSeekBackwardIntent>(
                onInvoke: (_) {
                  onSeekBackward?.call();
                  return null;
                },
              ),
          _TvFastForwardIntent:
              CallbackAction<_TvFastForwardIntent>(
                onInvoke: (_) {
                  onFastForward?.call();
                  return null;
                },
              ),
          _TvRewindIntent:
              CallbackAction<_TvRewindIntent>(
                onInvoke: (_) {
                  onRewind?.call();
                  return null;
                },
              ),
        },
        child: child,
      ),
    );
  }
}

class _TvMediaPlayPauseIntent extends Intent {
  const _TvMediaPlayPauseIntent();
}

class _TvSeekForwardIntent extends Intent {
  const _TvSeekForwardIntent();
}

class _TvSeekBackwardIntent extends Intent {
  const _TvSeekBackwardIntent();
}

class _TvFastForwardIntent extends Intent {
  const _TvFastForwardIntent();
}

class _TvRewindIntent extends Intent {
  const _TvRewindIntent();
}

enum TvDirectionalIntent { up, down, left, right, enter, back }

class TvDirectionalShortcuts extends StatelessWidget {
  const TvDirectionalShortcuts({
    super.key,
    required this.child,
    required this.onIntent,
  });

  final Widget child;
  final void Function(TvDirectionalIntent intent) onIntent;

  @override
  Widget build(BuildContext context) {
    return Shortcuts(
      shortcuts: const <ShortcutActivator, Intent>{
        SingleActivator(LogicalKeyboardKey.arrowUp): _TvUpIntent(),
        SingleActivator(LogicalKeyboardKey.arrowDown): _TvDownIntent(),
        SingleActivator(LogicalKeyboardKey.arrowLeft): _TvLeftIntent(),
        SingleActivator(LogicalKeyboardKey.arrowRight): _TvRightIntent(),
        SingleActivator(LogicalKeyboardKey.select): _TvEnterIntent(),
        SingleActivator(LogicalKeyboardKey.enter): _TvEnterIntent(),
        SingleActivator(LogicalKeyboardKey.goBack): _TvBackIntent(),
      },
      child: Actions(
        actions: <Type, Action<Intent>>{
          _TvUpIntent: CallbackAction<_TvUpIntent>(
            onInvoke: (_) {
              onIntent(TvDirectionalIntent.up);
              return null;
            },
          ),
          _TvDownIntent: CallbackAction<_TvDownIntent>(
            onInvoke: (_) {
              onIntent(TvDirectionalIntent.down);
              return null;
            },
          ),
          _TvLeftIntent: CallbackAction<_TvLeftIntent>(
            onInvoke: (_) {
              onIntent(TvDirectionalIntent.left);
              return null;
            },
          ),
          _TvRightIntent: CallbackAction<_TvRightIntent>(
            onInvoke: (_) {
              onIntent(TvDirectionalIntent.right);
              return null;
            },
          ),
          _TvEnterIntent: CallbackAction<_TvEnterIntent>(
            onInvoke: (_) {
              onIntent(TvDirectionalIntent.enter);
              return null;
            },
          ),
          _TvBackIntent: CallbackAction<_TvBackIntent>(
            onInvoke: (_) {
              onIntent(TvDirectionalIntent.back);
              return null;
            },
          ),
        },
        child: child,
      ),
    );
  }
}

class _TvUpIntent extends Intent {
  const _TvUpIntent();
}

class _TvDownIntent extends Intent {
  const _TvDownIntent();
}

class _TvLeftIntent extends Intent {
  const _TvLeftIntent();
}

class _TvRightIntent extends Intent {
  const _TvRightIntent();
}

class _TvEnterIntent extends Intent {
  const _TvEnterIntent();
}

class _TvBackIntent extends Intent {
  const _TvBackIntent();
}

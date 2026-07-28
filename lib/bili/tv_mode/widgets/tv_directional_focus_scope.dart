import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import 'tv_focusable.dart';

class TvDirectionalFocusScope extends StatelessWidget {
  const TvDirectionalFocusScope({
    super.key,
    required this.child,
    this.autofocus = true,
    this.handleGoBackKey = true,
    this.onBack,
    this.onMenu,
    this.debugLabel,
  });

  final Widget child;
  final bool autofocus;
  final bool handleGoBackKey;
  final VoidCallback? onBack;
  final VoidCallback? onMenu;
  final String? debugLabel;

  @override
  Widget build(BuildContext context) {
    return Shortcuts(
      shortcuts: <ShortcutActivator, Intent>{
        const SingleActivator(LogicalKeyboardKey.arrowUp):
            const _TvFocusUpIntent(),
        const SingleActivator(LogicalKeyboardKey.arrowDown):
            const _TvFocusDownIntent(),
        const SingleActivator(LogicalKeyboardKey.arrowLeft):
            const _TvFocusLeftIntent(),
        const SingleActivator(LogicalKeyboardKey.arrowRight):
            const _TvFocusRightIntent(),
        if (handleGoBackKey)
          const SingleActivator(LogicalKeyboardKey.goBack):
              const _TvFocusBackIntent(),
        const SingleActivator(LogicalKeyboardKey.browserBack):
            const _TvFocusBackIntent(),
        const SingleActivator(LogicalKeyboardKey.escape):
            const _TvFocusBackIntent(),
        const SingleActivator(LogicalKeyboardKey.contextMenu):
            const _TvFocusMenuIntent(),
      },
      child: Actions(
        actions: <Type, Action<Intent>>{
          _TvFocusUpIntent: CallbackAction<_TvFocusUpIntent>(
            onInvoke: (_) => _moveFocus(TraversalDirection.up),
          ),
          _TvFocusDownIntent: CallbackAction<_TvFocusDownIntent>(
            onInvoke: (_) => _moveFocus(TraversalDirection.down),
          ),
          _TvFocusLeftIntent: CallbackAction<_TvFocusLeftIntent>(
            onInvoke: (_) => _moveFocus(TraversalDirection.left),
          ),
          _TvFocusRightIntent: CallbackAction<_TvFocusRightIntent>(
            onInvoke: (_) => _moveFocus(TraversalDirection.right),
          ),
          _TvFocusBackIntent: CallbackAction<_TvFocusBackIntent>(
            onInvoke: (_) {
              if (onBack != null) {
                onBack!.call();
              } else {
                Navigator.maybePop(context);
              }
              return KeyEventResult.handled;
            },
          ),
          _TvFocusMenuIntent: CallbackAction<_TvFocusMenuIntent>(
            onInvoke: (_) {
              onMenu?.call();
              return onMenu == null
                  ? KeyEventResult.ignored
                  : KeyEventResult.handled;
            },
          ),
        },
        child: FocusTraversalGroup(
          policy: ReadingOrderTraversalPolicy(),
          child: Focus(
            autofocus: autofocus,
            debugLabel: debugLabel,
            onKeyEvent: (_, event) => _handleKeyEvent(context, event),
            child: child,
          ),
        ),
      ),
    );
  }

  KeyEventResult _handleKeyEvent(BuildContext context, KeyEvent event) {
    if (event is! KeyDownEvent) {
      return KeyEventResult.ignored;
    }
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.arrowUp) {
      return _moveFocus(TraversalDirection.up);
    }
    if (key == LogicalKeyboardKey.arrowDown) {
      return _moveFocus(TraversalDirection.down);
    }
    if (key == LogicalKeyboardKey.arrowLeft) {
      return _moveFocus(TraversalDirection.left);
    }
    if (key == LogicalKeyboardKey.arrowRight) {
      return _moveFocus(TraversalDirection.right);
    }
    if ((handleGoBackKey && key == LogicalKeyboardKey.goBack) ||
        key == LogicalKeyboardKey.browserBack ||
        key == LogicalKeyboardKey.escape) {
      if (onBack != null) {
        onBack!.call();
      } else {
        Navigator.maybePop(context);
      }
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.contextMenu && onMenu != null) {
      onMenu!.call();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  KeyEventResult _moveFocus(TraversalDirection direction) {
    final primaryFocus = FocusManager.instance.primaryFocus;
    final moved = primaryFocus == null
        ? false
        : moveTvFocusSpatially(primaryFocus, direction);
    if (moved) {
      revealFocusedTvControl(direction);
    }
    return moved ? KeyEventResult.handled : KeyEventResult.ignored;
  }
}

class _TvFocusUpIntent extends Intent {
  const _TvFocusUpIntent();
}

class _TvFocusDownIntent extends Intent {
  const _TvFocusDownIntent();
}

class _TvFocusLeftIntent extends Intent {
  const _TvFocusLeftIntent();
}

class _TvFocusRightIntent extends Intent {
  const _TvFocusRightIntent();
}

class _TvFocusBackIntent extends Intent {
  const _TvFocusBackIntent();
}

class _TvFocusMenuIntent extends Intent {
  const _TvFocusMenuIntent();
}

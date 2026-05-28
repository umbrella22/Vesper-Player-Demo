import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import 'tv_focusable.dart';

class TvDirectionalFocusScope extends StatelessWidget {
  const TvDirectionalFocusScope({
    super.key,
    required this.child,
    this.autofocus = true,
    this.onBack,
    this.onMenu,
    this.debugLabel,
  });

  final Widget child;
  final bool autofocus;
  final VoidCallback? onBack;
  final VoidCallback? onMenu;
  final String? debugLabel;

  @override
  Widget build(BuildContext context) {
    return Shortcuts(
      shortcuts: const <ShortcutActivator, Intent>{
        SingleActivator(LogicalKeyboardKey.arrowUp): _TvFocusUpIntent(),
        SingleActivator(LogicalKeyboardKey.arrowDown): _TvFocusDownIntent(),
        SingleActivator(LogicalKeyboardKey.arrowLeft): _TvFocusLeftIntent(),
        SingleActivator(LogicalKeyboardKey.arrowRight): _TvFocusRightIntent(),
        SingleActivator(LogicalKeyboardKey.goBack): _TvFocusBackIntent(),
        SingleActivator(LogicalKeyboardKey.browserBack): _TvFocusBackIntent(),
        SingleActivator(LogicalKeyboardKey.escape): _TvFocusBackIntent(),
        SingleActivator(LogicalKeyboardKey.contextMenu): _TvFocusMenuIntent(),
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
    if (key == LogicalKeyboardKey.goBack ||
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
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final focusedContext = FocusManager.instance.primaryFocus?.context;
        if (focusedContext != null) {
          Scrollable.ensureVisible(
            focusedContext,
            duration: const Duration(milliseconds: 160),
            curve: Curves.easeOutCubic,
            alignmentPolicy: ScrollPositionAlignmentPolicy.keepVisibleAtEnd,
          );
        }
      });
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

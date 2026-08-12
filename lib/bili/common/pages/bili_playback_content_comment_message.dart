part of 'bili_playback_content_surfaces.dart';

class _CommentMessageText extends StatefulWidget {
  const _CommentMessageText({
    required this.message,
    required this.timeLinks,
    required this.onSeekToTime,
    this.style,
  });

  final String message;
  final List<BiliCommentTimeLink> timeLinks;
  final ValueChanged<int> onSeekToTime;
  final TextStyle? style;

  @override
  State<_CommentMessageText> createState() => _CommentMessageTextState();
}

class _CommentMessageTextState extends State<_CommentMessageText> {
  final List<TapGestureRecognizer> _recognizers = <TapGestureRecognizer>[];

  @override
  void initState() {
    super.initState();
    _syncRecognizers();
  }

  @override
  void didUpdateWidget(_CommentMessageText oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.timeLinks != widget.timeLinks ||
        oldWidget.onSeekToTime != widget.onSeekToTime) {
      _syncRecognizers();
    }
  }

  @override
  void dispose() {
    _disposeRecognizers();
    super.dispose();
  }

  void _disposeRecognizers() {
    for (final recognizer in _recognizers) {
      recognizer.dispose();
    }
    _recognizers.clear();
  }

  void _syncRecognizers() {
    _disposeRecognizers();
    for (final link in widget.timeLinks.where(_hasInlineRange)) {
      _recognizers.add(
        TapGestureRecognizer()..onTap = () => widget.onSeekToTime(link.seconds),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final visualTheme = AppVisualTheme.of(context);
    final style =
        widget.style ??
        Theme.of(context).textTheme.bodyMedium?.copyWith(
          color: visualTheme.textPrimary,
          height: 1.5,
        );
    final linkStyle = style?.copyWith(
      color: AppVisualTokens.primaryBlue,
      fontWeight: FontWeight.w900,
      decoration: TextDecoration.none,
    );
    final spans = <InlineSpan>[];
    var cursor = 0;
    var recognizerIndex = 0;
    for (final link in widget.timeLinks.where(_hasInlineRange)) {
      final start = link.start!;
      final end = link.end!;
      if (start < cursor || start > widget.message.length) {
        continue;
      }
      if (cursor < start) {
        spans.add(TextSpan(text: widget.message.substring(cursor, start)));
      }
      spans.add(
        TextSpan(
          text: widget.message.substring(start, end),
          style: linkStyle,
          recognizer: _recognizers[recognizerIndex],
        ),
      );
      recognizerIndex += 1;
      cursor = end;
    }
    if (cursor < widget.message.length) {
      spans.add(TextSpan(text: widget.message.substring(cursor)));
    }

    return RichText(
      text: TextSpan(style: style, children: spans),
      textScaler: MediaQuery.textScalerOf(context),
    );
  }
}

bool _hasInlineRange(BiliCommentTimeLink link) =>
    link.start != null && link.end != null && link.start! < link.end!;

class _CommentExtraTimeLinks extends StatelessWidget {
  const _CommentExtraTimeLinks({
    required this.links,
    required this.onSeekToTime,
  });

  final List<BiliCommentTimeLink> links;
  final ValueChanged<int> onSeekToTime;

  @override
  Widget build(BuildContext context) {
    final extraLinks = links
        .where((link) => !_hasInlineRange(link))
        .toList(growable: false);
    if (extraLinks.isEmpty) {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final link in extraLinks)
            _CommentTimeChip(
              link: link,
              onTap: () => onSeekToTime(link.seconds),
            ),
        ],
      ),
    );
  }
}

class _CommentTimeChip extends StatelessWidget {
  const _CommentTimeChip({required this.link, required this.onTap});

  final BiliCommentTimeLink link;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final visualTheme = AppVisualTheme.of(context);
    return Material(
      color: Color.alphaBlend(
        AppVisualTokens.primaryBlue.withValues(alpha: 0.12),
        visualTheme.surfaceRaised,
      ),
      borderRadius: BorderRadius.circular(999),
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.play_arrow_rounded,
                size: 16,
                color: AppVisualTokens.primaryBlue,
              ),
              const SizedBox(width: 3),
              Text(
                link.label,
                style: const TextStyle(
                  color: AppVisualTokens.primaryBlue,
                  fontSize: 12,
                  fontWeight: FontWeight.w900,
                  height: 1.1,
                  fontFeatures: [ui.FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CommentPictureGrid extends StatelessWidget {
  const _CommentPictureGrid({required this.pictures});

  final List<BiliCommentPicture> pictures;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (pictures.length == 1) {
          final picture = pictures.first;
          final width = constraints.maxWidth.clamp(180.0, 420.0).toDouble();
          final aspectRatio = _pictureAspectRatio(picture).clamp(0.72, 1.78);
          return Align(
            alignment: Alignment.centerLeft,
            child: SizedBox(
              width: width,
              child: AspectRatio(
                aspectRatio: aspectRatio,
                child: _CommentPicture(picture: picture),
              ),
            ),
          );
        }

        final itemWidth = ((constraints.maxWidth - 16) / 3)
            .clamp(76.0, 118.0)
            .toDouble();
        return Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final picture in pictures.take(9))
              SizedBox.square(
                dimension: itemWidth,
                child: _CommentPicture(picture: picture),
              ),
          ],
        );
      },
    );
  }

  double _pictureAspectRatio(BiliCommentPicture picture) {
    final width = picture.width;
    final height = picture.height;
    if (width == null || height == null || width <= 0 || height <= 0) {
      return 16 / 9;
    }
    return width / height;
  }
}

class _CommentPicture extends StatelessWidget {
  const _CommentPicture({required this.picture});

  final BiliCommentPicture picture;

  @override
  Widget build(BuildContext context) {
    final visualTheme = AppVisualTheme.of(context);
    final cacheWidth = (MediaQuery.devicePixelRatioOf(context) * 420)
        .round()
        .clamp(280, 960)
        .toInt();
    return ClipRRect(
      borderRadius: BorderRadius.circular(7),
      child: Stack(
        fit: StackFit.expand,
        children: [
          DecoratedBox(
            decoration: BoxDecoration(color: visualTheme.surfaceRaised),
            child: Image.network(
              picture.url,
              fit: BoxFit.cover,
              cacheWidth: cacheWidth,
              errorBuilder: (_, _, _) => Icon(
                Icons.broken_image_outlined,
                color: visualTheme.textTertiary,
              ),
            ),
          ),
          DecoratedBox(
            decoration: BoxDecoration(
              border: Border.fromBorderSide(
                BorderSide(color: visualTheme.imageOutline),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CommentActionRow extends StatelessWidget {
  const _CommentActionRow({required this.comment});

  final BiliVideoComment comment;

  @override
  Widget build(BuildContext context) {
    final visualTheme = AppVisualTheme.of(context);
    return Row(
      children: [
        _CommentPassiveAction(
          icon: comment.liked
              ? Icons.thumb_up_rounded
              : Icons.thumb_up_alt_outlined,
          label: comment.likeCountLabel,
          selected: comment.liked,
        ),
        const SizedBox(width: 14),
        const _CommentPassiveAction(
          icon: Icons.thumb_down_alt_outlined,
          label: '',
        ),
        const SizedBox(width: 14),
        const _CommentPassiveAction(icon: Icons.ios_share_rounded, label: ''),
        const SizedBox(width: 14),
        const _CommentPassiveAction(
          icon: Icons.mode_comment_outlined,
          label: '',
        ),
        const Spacer(),
        Icon(
          Icons.more_vert_rounded,
          size: 20,
          color: visualTheme.textTertiary,
        ),
      ],
    );
  }
}

class _CommentPassiveAction extends StatelessWidget {
  const _CommentPassiveAction({
    required this.icon,
    required this.label,
    this.selected = false,
  });

  final IconData icon;
  final String label;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final visualTheme = AppVisualTheme.of(context);
    final color = selected
        ? AppVisualTokens.primaryBlue
        : visualTheme.textSecondary;
    return SizedBox(
      height: 40,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 21, color: color),
          if (label.isNotEmpty) ...[
            const SizedBox(width: 5),
            Text(
              label,
              style: TextStyle(
                color: color,
                fontSize: 13,
                fontWeight: FontWeight.w800,
                fontFeatures: const [ui.FontFeature.tabularFigures()],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

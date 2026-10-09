import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:mostro/core/order_book_palette.dart';
import 'package:mostro/features/chat/models/reaction_rules.dart';
import 'package:mostro/l10n/app_localizations.dart';

/// The reactions the menu offers in one tap, in order. «…» opens the rest.
const quickReactions = ['❤️', '👍', '👎', '😂', '😮', '😢'];

/// What the user picked in a message's menu.
sealed class MessageMenuChoice {
  const MessageMenuChoice();
}

/// Copy the message's text.
final class CopyMessage extends MessageMenuChoice {
  const CopyMessage();
}

/// React with [emoji], one of [quickReactions].
final class ReactWith extends MessageMenuChoice {
  const ReactWith(this.emoji);

  final String emoji;
}

/// Open the full list of emojis.
final class MoreReactions extends MessageMenuChoice {
  const MoreReactions();
}

/// Where a message is on screen, in global coordinates: [rect] the whole
/// message, [visible] the part its list shows.
typedef MessagePlace = ({Rect rect, Rect visible});

/// The message's [MessagePlace], or null once nobody can see it.
typedef MessageAnchor = MessagePlace? Function();

/// Opens the menu of the chat message drawn by [bubble], which [anchor]
/// locates, and resolves to what the user picked, or null when they
/// dismissed it.
///
/// The message stays lit above the scrim and the menu opens under it, or
/// above it when there is no room below. With [canReact] the reactions sit
/// above the message, [currentReaction] marked as the user's; without
/// [canCopy] (an attachment) they are the whole menu. Everything
/// follows the message when it moves — a new message scrolls the chat, the
/// keyboard closes, the screen turns — and the menu closes if it
/// disappears. [alignEnd] lines everything up with the message's side: the
/// right for one's own, the left for the counterpart's.
Future<MessageMenuChoice?> showMessageActionsMenu({
  required BuildContext context,
  required MessageAnchor anchor,
  required Widget bubble,
  required bool alignEnd,
  bool canReact = false,
  bool canCopy = true,
  String? currentReaction,
}) async {
  final place = anchor();
  if (place == null) return null;
  final book = OrderBookPalette.of(context);
  // Root navigator: the route places the message by global coordinates, so
  // its overlay must cover the whole screen.
  return Navigator.of(context, rootNavigator: true).push(
    _MessageActionsRoute(
      anchor: anchor,
      place: place,
      bubble: bubble,
      alignEnd: alignEnd,
      canReact: canReact,
      canCopy: canCopy,
      currentReaction: currentReaction,
      scrim: book.scrim,
      barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
      animate: !MediaQuery.disableAnimationsOf(context),
    ),
  );
}

class _MessageActionsRoute extends PopupRoute<MessageMenuChoice> {
  _MessageActionsRoute({
    required this.anchor,
    required this.place,
    required this.bubble,
    required this.alignEnd,
    required this.canReact,
    required this.canCopy,
    required this.currentReaction,
    required this.scrim,
    required this.barrierLabel,
    required this.animate,
  });

  final MessageAnchor anchor;

  /// Where the message was when the menu opened.
  final MessagePlace place;
  final Widget bubble;
  final bool alignEnd;
  final bool canReact;
  final bool canCopy;
  final String? currentReaction;
  final Color scrim;
  final bool animate;

  @override
  final String barrierLabel;

  @override
  Color get barrierColor => scrim;

  @override
  bool get barrierDismissible => true;

  @override
  Duration get transitionDuration =>
      animate ? const Duration(milliseconds: 200) : Duration.zero;

  @override
  Widget buildPage(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
  ) {
    return _FollowAnchor(
      anchor: anchor,
      initial: place,
      builder: (context, place) => Stack(
        children: [
          // Cut to what the list shows, as the original is: a message partly
          // scrolled under the header or the composer stays under them.
          Positioned.fromRect(
            rect: place.visible,
            child: ClipRect(
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  // Taps on the message fall through to the barrier and
                  // close the menu; a screen reader already reads the
                  // original underneath.
                  Positioned.fromRect(
                    rect: place.rect.shift(-place.visible.topLeft),
                    // An attachment's bubble holds ink of its own, which
                    // needs a Material out here in the route as well.
                    child: IgnorePointer(
                      child: ExcludeSemantics(
                        child: Material(
                          type: MaterialType.transparency,
                          child: bubble,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          CustomMultiChildLayout(
            delegate: _MenuLayout(
              bubbleRect: place.visible,
              alignEnd: alignEnd,
              safeArea: _usableInsets(context),
            ),
            children: [
              if (canReact)
                LayoutId(
                  id: _Slot.reactions,
                  child: _ReactionPill(current: currentReaction),
                ),
              if (canCopy)
                LayoutId(id: _Slot.actions, child: const _ActionsCard()),
            ],
          ),
        ],
      ),
    );
  }

  /// The safe area, the keyboard counting as the bottom edge while it is up:
  /// the composer may keep it open while a message is held.
  static EdgeInsets _usableInsets(BuildContext context) {
    final padding = MediaQuery.paddingOf(context);
    final keyboard = MediaQuery.viewInsetsOf(context).bottom;
    return padding.copyWith(bottom: math.max(padding.bottom, keyboard));
  }

  @override
  Widget buildTransitions(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    return FadeTransition(
      opacity: CurvedAnimation(parent: animation, curve: Curves.easeOut),
      child: child,
    );
  }
}

/// Rebuilds the menu where the message is after every frame that moved it,
/// and closes the menu once the message is gone.
///
/// Checking after each frame costs one rectangle comparison and schedules
/// nothing: a still screen draws no frame, so the check waits with it.
class _FollowAnchor extends StatefulWidget {
  const _FollowAnchor({
    required this.anchor,
    required this.initial,
    required this.builder,
  });

  final MessageAnchor anchor;
  final MessagePlace initial;
  final Widget Function(BuildContext context, MessagePlace place) builder;

  @override
  State<_FollowAnchor> createState() => _FollowAnchorState();
}

class _FollowAnchorState extends State<_FollowAnchor> {
  late MessagePlace _place = widget.initial;

  @override
  void initState() {
    super.initState();
    _checkAfterFrame();
  }

  void _checkAfterFrame() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final place = widget.anchor();
      if (place == null) {
        Navigator.of(context).maybePop();
        return;
      }
      if (place != _place) setState(() => _place = place);
      _checkAfterFrame();
    });
  }

  @override
  Widget build(BuildContext context) => widget.builder(context, _place);
}

enum _Slot { reactions, actions }

/// Places the reactions above the message and the actions under it. When one
/// side lacks room both go on the other, the reactions first, and when
/// neither has room they stack over the top of the message. Everything is
/// kept inside the safe area, cutouts on the sides included.
class _MenuLayout extends MultiChildLayoutDelegate {
  _MenuLayout({
    required this.bubbleRect,
    required this.alignEnd,
    required this.safeArea,
  });

  final Rect bubbleRect;
  final bool alignEnd;
  final EdgeInsets safeArea;

  /// Space kept from the screen's edges. The reactions get less, so that
  /// seven 48-dp targets still fit a 360-dp screen.
  static const double _margin = 16;
  static const double _reactionsMargin = 8;
  static const double _gap = 8;

  @override
  void performLayout(Size size) {
    final height = math.max(0.0, size.height - safeArea.vertical - 2 * _margin);
    final width = size.width - safeArea.horizontal;
    final actions = hasChild(_Slot.actions)
        ? layoutChild(
            _Slot.actions,
            BoxConstraints.loose(
              Size(math.max(0.0, width - 2 * _margin), height),
            ),
          )
        : null;
    final reactions = hasChild(_Slot.reactions)
        ? layoutChild(
            _Slot.reactions,
            BoxConstraints.loose(
              Size(math.max(0.0, width - 2 * _reactionsMargin), height),
            ),
          )
        : null;

    final top = safeArea.top + _margin;
    final bottom = size.height - safeArea.bottom - _margin;
    final below = bubbleRect.bottom + _gap;
    final above = bubbleRect.top - _gap;

    double? actionsY;
    double? reactionsY;
    if (reactions == null && actions == null) {
      return;
    } else if (reactions == null) {
      actionsY = below + actions!.height <= bottom
          ? below
          : above - actions.height;
      actionsY = _clamp(actionsY, top, bottom - actions.height);
    } else if (actions == null) {
      // Reactions alone (an attachment): above the message, or under it.
      reactionsY = _clamp(
        above - reactions.height >= top ? above - reactions.height : below,
        top,
        bottom - reactions.height,
      );
    } else if (above - reactions.height >= top &&
        below + actions.height <= bottom) {
      reactionsY = above - reactions.height;
      actionsY = below;
    } else {
      // On one side, as one stack clamped whole: clamped apart, a tall
      // message would pin both to the top, the actions over the reactions.
      final stack = reactions.height + _gap + actions.height;
      final stackTop = _clamp(
        below + stack <= bottom ? below : above - stack,
        top,
        bottom - stack,
      );
      reactionsY = stackTop;
      actionsY = stackTop + reactions.height + _gap;
    }

    if (actions != null && actionsY != null) {
      positionChild(
        _Slot.actions,
        Offset(_x(size, actions.width, _margin), actionsY),
      );
    }
    if (reactions != null && reactionsY != null) {
      positionChild(
        _Slot.reactions,
        Offset(_x(size, reactions.width, _reactionsMargin), reactionsY),
      );
    }
  }

  /// Lined up with the message's side, kept [margin] inside the safe area.
  double _x(Size size, double width, double margin) {
    final x = alignEnd ? bubbleRect.right - width : bubbleRect.left;
    return _clamp(
      x,
      safeArea.left + margin,
      size.width - safeArea.right - margin - width,
    );
  }

  /// [value] within [min]..[max], [min] winning when they cross: a child
  /// taller or wider than the room left starts at the top or the left.
  static double _clamp(double value, double min, double max) =>
      math.max(min, math.min(value, max));

  @override
  bool shouldRelayout(_MenuLayout oldDelegate) =>
      bubbleRect != oldDelegate.bubbleRect ||
      alignEnd != oldDelegate.alignEnd ||
      safeArea != oldDelegate.safeArea;
}

/// The six quick reactions and «…», as in Signal. The user's current
/// reaction is marked; picking it again withdraws it.
class _ReactionPill extends StatelessWidget {
  const _ReactionPill({required this.current});

  final String? current;

  /// The pill's padding on each side of its buttons.
  static const double _inset = 4;

  @override
  Widget build(BuildContext context) {
    final book = OrderBookPalette.of(context);
    final l10n = AppLocalizations.of(context);
    // Every target keeps its 48 dp (DS-CMP-6): a screen too narrow for all
    // seven drops the last quick reactions, which «…» still offers.
    return LayoutBuilder(
      builder: (context, constraints) {
        final fit =
            ((constraints.maxWidth - 2 * _inset) / _PillButton._target)
                .floor();
        final shown = quickReactions.take(
          (fit - 1).clamp(0, quickReactions.length),
        );
        return Material(
          color: book.surface,
          shape: StadiumBorder(side: BorderSide(color: book.border)),
          clipBehavior: Clip.antiAlias,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: _inset),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final emoji in shown)
                  _PillButton(
                    // ❤ picked from the full list is the quick ❤️.
                    selected: sameReaction(emoji, current),
                    onTap: () => Navigator.of(context).pop(ReactWith(emoji)),
                    child: Text(emoji, style: const TextStyle(fontSize: 22)),
                  ),
                _PillButton(
                  label: l10n.moreReactions,
                  onTap: () =>
                      Navigator.of(context).pop(const MoreReactions()),
                  child: Icon(
                    Icons.more_horiz_rounded,
                    size: 22,
                    color: book.textBody,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _PillButton extends StatelessWidget {
  const _PillButton({
    required this.onTap,
    required this.child,
    this.selected = false,
    this.label,
  });

  final VoidCallback onTap;
  final Widget child;
  final bool selected;

  /// For a glyph that does not read itself; an emoji does.
  final String? label;

  static const double _target = 48;

  @override
  Widget build(BuildContext context) {
    final book = OrderBookPalette.of(context);
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      child: InkResponse(
        onTap: onTap,
        radius: _target / 2,
        child: SizedBox.square(
          dimension: _target,
          child: Padding(
            padding: const EdgeInsets.all(4),
            child: DecoratedBox(
              decoration: selected
                  ? BoxDecoration(
                      color: book.inset,
                      shape: BoxShape.circle,
                      border: Border.all(color: book.borderHighlight),
                    )
                  : const BoxDecoration(),
              child: Padding(
                padding: const EdgeInsets.all(4),
                // Larger text grows the glyph up to the target, no further.
                child: FittedBox(fit: BoxFit.scaleDown, child: child),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ActionsCard extends StatelessWidget {
  const _ActionsCard();

  @override
  Widget build(BuildContext context) {
    final book = OrderBookPalette.of(context);
    final l10n = AppLocalizations.of(context);
    return Material(
      color: book.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: book.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minWidth: 200),
        child: IntrinsicWidth(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _ActionItem(
                icon: Icons.copy_rounded,
                label: l10n.copyButtonLabel,
                onTap: () => Navigator.of(context).pop(const CopyMessage()),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ActionItem extends StatelessWidget {
  const _ActionItem({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final book = OrderBookPalette.of(context);
    return Semantics(
      button: true,
      child: InkWell(
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 48),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
            child: Row(
              children: [
                Icon(icon, size: 20, color: book.textBody),
                const SizedBox(width: 14),
                Flexible(
                  child: Text(
                    label,
                    style: TextStyle(fontSize: 15, color: book.textPrimary),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

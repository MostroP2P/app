import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:mostro/core/app_routes.dart';
import 'package:mostro/core/app_theme.dart';
import 'package:mostro/core/automation/automation_id.dart';
import 'package:mostro/core/automation/automation_ids.dart';
import 'package:mostro/l10n/app_localizations.dart';

const double _buttonSize = 56;

/// One clock for opening and closing: the ✕ turns over all of it, the scrim
/// fades in over the first 150 ms and the buttons enter over the first 180 ms
/// (handoff 4d).
const Duration _openDuration = Duration(milliseconds: 200);

const double _menuSideInset = 18;

/// Gap between the Buy/Sell stack and the top of the round button.
const double _menuGap = 18;

/// How far the buttons rise while they fade in.
const double _menuRise = 8;

/// Create-order button (order-book handoff, variant 4d).
///
/// Closed: a 56-dp lime circle with a "+". Open: a scrim over the whole
/// screen — bottom bar included — with Buy and Sell as equal full-width
/// buttons above the button, which turns into a grey ✕ in the same place.
/// Tapping the scrim, the ✕ or system back closes it.
///
/// The open state renders in the nearest [Overlay] through an
/// [OverlayPortal]: the Scaffold gives the button only its own slot, so a
/// scrim drawn in place could never cover the bottom bar.
class AddOrderButton extends StatefulWidget {
  const AddOrderButton({super.key});

  @override
  State<AddOrderButton> createState() => _AddOrderButtonState();
}

class _AddOrderButtonState extends State<AddOrderButton>
    with SingleTickerProviderStateMixin {
  final _portal = OverlayPortalController();
  final _buttonKey = GlobalKey();

  late final AnimationController _controller;
  late final CurvedAnimation _scrim;
  late final CurvedAnimation _entrance;

  /// Where the closed button sits in the overlay, captured when opening so
  /// the ✕ lands exactly on top of it.
  Rect _buttonRect = Rect.zero;

  @override
  void initState() {
    super.initState();
    // Created eagerly: a lazy controller on a button that was never opened
    // would first be built in dispose(), and a deactivated element cannot
    // create a ticker.
    _controller = AnimationController(vsync: this, duration: _openDuration);
    _scrim = CurvedAnimation(
      parent: _controller,
      curve: const Interval(0, 0.75),
    );
    _entrance = CurvedAnimation(
      parent: _controller,
      curve: const Interval(0, 0.9, curve: Curves.easeOut),
    );
  }

  @override
  void dispose() {
    _scrim.dispose();
    _entrance.dispose();
    _controller.dispose();
    super.dispose();
  }

  void _open() {
    final button = _buttonKey.currentContext?.findRenderObject() as RenderBox?;
    final overlay = Overlay.of(context).context.findRenderObject() as RenderBox?;
    if (button == null || overlay == null) return;
    setState(() {
      _buttonRect =
          button.localToGlobal(Offset.zero, ancestor: overlay) & button.size;
      _portal.show();
    });
    _controller.forward();
  }

  Future<void> _close() async {
    if (!_portal.isShowing) return;
    await _controller.reverse();
    if (mounted && _portal.isShowing) setState(_portal.hide);
  }

  void _create(String type) {
    _controller.value = 0;
    setState(_portal.hide);
    context.push('${AppRoute.addOrder}?type=$type');
  }

  @override
  Widget build(BuildContext context) {
    final palette = OrderBookPalette.of(context);
    final isOpen = _portal.isShowing;

    return PopScope(
      canPop: !isOpen,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _close();
      },
      child: OverlayPortal(
        controller: _portal,
        overlayChildBuilder:
            (_) => _OpenMenu(
              palette: palette,
              scrim: _scrim,
              entrance: _entrance,
              rotation: _controller,
              buttonRect: _buttonRect,
              onDismiss: _close,
              onCreate: _create,
            ),
        // While open, the ✕ in the overlay is the control: the covered button
        // leaves the semantics tree so automation finds exactly one.
        child: ExcludeSemantics(
          excluding: isOpen,
          child: Padding(
            // The Scaffold keeps floating buttons 16 from the edge; the mock
            // sets 18.
            padding: const EdgeInsets.only(right: 2),
            child: _RoundButton(
              key: _buttonKey,
              palette: palette,
              onPressed: _open,
            ).withAutomationId(AutomationIds.orderAddFab),
          ),
        ),
      ),
    );
  }
}

class _OpenMenu extends StatelessWidget {
  const _OpenMenu({
    required this.palette,
    required this.scrim,
    required this.entrance,
    required this.rotation,
    required this.buttonRect,
    required this.onDismiss,
    required this.onCreate,
  });

  final OrderBookPalette palette;
  final Animation<double> scrim;
  final Animation<double> entrance;
  final Animation<double> rotation;
  final Rect buttonRect;
  final VoidCallback onDismiss;
  final ValueChanged<String> onCreate;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return LayoutBuilder(
      builder:
          (context, constraints) => Stack(
            children: [
              Positioned.fill(
                child: FadeTransition(
                  opacity: scrim,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: onDismiss,
                    child: ColoredBox(color: palette.scrim),
                  ),
                ),
              ),
              Positioned(
                left: _menuSideInset,
                right: _menuSideInset,
                bottom: constraints.maxHeight - buttonRect.top + _menuGap,
                child: AnimatedBuilder(
                  animation: entrance,
                  builder:
                      (context, child) => Opacity(
                        opacity: entrance.value,
                        child: Transform.translate(
                          offset: Offset(0, _menuRise * (1 - entrance.value)),
                          child: child,
                        ),
                      ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _MenuButton(
                        label: l10n.tabBuyBtc,
                        icon: Icons.arrow_downward_rounded,
                        fill: palette.lime,
                        ink: palette.onLime,
                        shadow: palette.buyShadow,
                        onTap: () => onCreate('buy'),
                      ).withAutomationId(AutomationIds.orderAddBuy),
                      const SizedBox(height: 10),
                      _MenuButton(
                        label: l10n.tabSellBtc,
                        icon: Icons.arrow_upward_rounded,
                        fill: palette.sell,
                        ink: palette.onSell,
                        shadow: palette.sellShadow,
                        onTap: () => onCreate('sell'),
                      ).withAutomationId(AutomationIds.orderAddSell),
                      const SizedBox(height: 12),
                      Text(
                        l10n.fabDismissHint,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 12,
                          color: palette.scrimText,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              Positioned.fromRect(
                rect: buttonRect,
                child: _RoundButton(
                  palette: palette,
                  rotation: rotation,
                  onPressed: onDismiss,
                ).withAutomationId(AutomationIds.orderAddFab),
              ),
            ],
          ),
    );
  }
}

/// Buy or Sell: full width, 52 tall, the same size for both — neither side
/// outranks the other.
class _MenuButton extends StatelessWidget {
  const _MenuButton({
    required this.label,
    required this.icon,
    required this.fill,
    required this.ink,
    required this.shadow,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final Color fill;
  final Color ink;
  final List<BoxShadow> shadow;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    const radius = BorderRadius.all(Radius.circular(16));

    return DecoratedBox(
      decoration: BoxDecoration(borderRadius: radius, boxShadow: shadow),
      child: Material(
        color: fill,
        borderRadius: radius,
        child: InkWell(
          onTap: onTap,
          borderRadius: radius,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 52),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(icon, size: 19, color: ink),
                  const SizedBox(width: 10),
                  Flexible(
                    child: Text(
                      label,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: ink,
                      ),
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

/// The round button: lime "+" when closed; grey ✕, turning into place, when
/// [rotation] is given (the open state).
class _RoundButton extends StatelessWidget {
  const _RoundButton({
    super.key,
    required this.palette,
    required this.onPressed,
    this.rotation,
  });

  final OrderBookPalette palette;
  final VoidCallback onPressed;
  final Animation<double>? rotation;

  @override
  Widget build(BuildContext context) {
    final rotation = this.rotation;
    final isOpen = rotation != null;

    return Semantics(
      button: true,
      label:
          isOpen
              ? MaterialLocalizations.of(context).closeButtonTooltip
              : AppLocalizations.of(context).addOrderFabLabel,
      child: SizedBox.square(
        dimension: _buttonSize,
        child: DecoratedBox(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            boxShadow: isOpen ? null : palette.fabShadow,
          ),
          child: Material(
            color: isOpen ? palette.fabClose : palette.lime,
            shape: CircleBorder(
              side:
                  isOpen
                      ? BorderSide(color: palette.fabCloseBorder)
                      : BorderSide.none,
            ),
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: onPressed,
              child: Center(
                child:
                    isOpen
                        ? RotationTransition(
                          turns: Tween(begin: -0.125, end: 0.0).animate(rotation),
                          child: Icon(
                            Icons.close,
                            size: 22,
                            color: palette.fabCloseIcon,
                          ),
                        )
                        : Icon(Icons.add, size: 26, color: palette.onLime),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

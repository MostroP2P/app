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
/// The open state is its own [OverlayEntry] above the route. The Scaffold
/// gives the button only its own slot, so a scrim drawn in place could never
/// cover the bottom bar; and only an entry painted after the route can block
/// the route's semantics — an [OverlayPortal] child is attached, for
/// semantics, where the button sits, before the bottom bar.
class AddOrderButton extends StatefulWidget {
  const AddOrderButton({super.key});

  @override
  State<AddOrderButton> createState() => _AddOrderButtonState();
}

class _AddOrderButtonState extends State<AddOrderButton>
    with SingleTickerProviderStateMixin {
  final _buttonKey = GlobalKey();

  late final AnimationController _controller;
  late final CurvedAnimation _scrim;
  late final CurvedAnimation _entrance;

  /// The open menu, inserted into the navigator's overlay above the route.
  OverlayEntry? _menu;

  bool get _isOpen => _menu != null;

  /// Screen size the open menu was placed for.
  Size? _menuScreenSize;

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
  void didChangeDependencies() {
    super.didChangeDependencies();
    // The menu is placed from where the button sat when it opened. Rotating
    // or resizing moves the button, so close rather than leave the ✕ and the
    // Buy/Sell buttons behind. After the frame: resetting the controller here
    // would rebuild the menu's animated widgets in the middle of a build.
    final size = MediaQuery.sizeOf(context);
    if (_isOpen && size != _menuScreenSize) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !_isOpen) return;
        setState(() {
          _controller.value = 0;
          _discardMenu();
        });
      });
    }
  }

  @override
  void dispose() {
    _discardMenu();
    _scrim.dispose();
    _entrance.dispose();
    _controller.dispose();
    super.dispose();
  }

  void _open() {
    final button = _buttonKey.currentContext?.findRenderObject() as RenderBox?;
    final overlay = Overlay.of(context);
    final overlayBox = overlay.context.findRenderObject() as RenderBox?;
    if (_isOpen || button == null || overlayBox == null) return;

    // Where the closed button sits in the overlay, so the ✕ lands exactly on
    // top of it.
    final buttonRect =
        button.localToGlobal(Offset.zero, ancestor: overlayBox) & button.size;
    final menu = OverlayEntry(
      builder:
          (context) => _OpenMenu(
            palette: OrderBookPalette.of(context),
            scrim: _scrim,
            entrance: _entrance,
            rotation: _controller,
            buttonRect: buttonRect,
            onDismiss: _close,
            onCreate: _create,
          ),
    );
    overlay.insert(menu);
    _menuScreenSize = MediaQuery.sizeOf(context);
    setState(() => _menu = menu);
    _controller.forward();
  }

  Future<void> _close() async {
    if (!_isOpen) return;
    await _controller.reverse();
    if (mounted) setState(_discardMenu);
  }

  void _create(String type) {
    _controller.value = 0;
    setState(_discardMenu);
    context.push('${AppRoute.addOrder}?type=$type');
  }

  void _discardMenu() {
    _menu
      ?..remove()
      ..dispose();
    _menu = null;
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_isOpen,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _close();
      },
      child: Padding(
        // The Scaffold keeps floating buttons 16 from the edge; the mock sets
        // 18.
        padding: const EdgeInsets.only(right: 2),
        child: _RoundButton(
          key: _buttonKey,
          palette: OrderBookPalette.of(context),
          onPressed: _open,
        ).withAutomationId(AutomationIds.orderAddFab),
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

    // Modal while open: from its own overlay entry, BlockSemantics drops the
    // whole route — page and bottom bar — from the semantics tree, and the
    // route-like scope makes a screen reader treat the open menu as the
    // current screen.
    return BlockSemantics(
      child: Semantics(
        container: true,
        explicitChildNodes: true,
        scopesRoute: true,
        child: LayoutBuilder(
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
                              offset: Offset(
                                0,
                                _menuRise * (1 - entrance.value),
                              ),
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
        ),
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
                          turns: Tween(
                            begin: -0.125,
                            end: 0.0,
                          ).animate(rotation),
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

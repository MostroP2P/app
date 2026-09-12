import 'dart:math' as math;
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:mostro/core/automation/automation_id.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:mostro/core/app_routes.dart';
import 'package:mostro/core/app_theme.dart';
import 'package:mostro/core/automation/automation_ids.dart';
import 'package:mostro/features/about/screens/about_screen.dart'
    show appVersionProvider;
import 'package:mostro/features/trades/providers/trades_providers.dart'
    show orderBookNotificationCountProvider;
import 'package:mostro/l10n/app_localizations.dart';
import 'package:mostro/shared/widgets/bottom_nav_bar.dart'
    show chatNotificationCountProvider;

// ── Layout tokens (drawer redesign handoff, 3b / 3c) ─────────────────────────

const double _panelWidth = 300;

/// Scrim always left visible beside the overlay panel on narrow screens, so
/// the drawer can be dismissed by tapping outside it.
const double _minScrimWidth = 56;
const Duration _slideDuration = Duration(milliseconds: 246);
const double _panelRadius = 28;
const double _contentInset = 22;
const double _listInset = 14;
const double _rowGap = 8;
const double _rowMinHeight = 60;
const double _rowRadius = 18;
const double _tileSize = 40;
const double _tileRadius = 13;
const double _logoHeight = 50;
const String _mascotAsset = 'assets/images/mostro_mascot.webp';

/// Header top padding; below a taller status bar it keeps the same gap.
const double _headerTop = 46;
const double _headerSafeGap = 22;

/// CSS `radial-gradient(circle, …)` sizes to the farthest corner, i.e. half
/// the square's diagonal; [RadialGradient.radius] is relative to its side.
const double _farthestCornerRadius = math.sqrt2 / 2;

/// Direction of a CSS `linear-gradient(<deg>, …)` applied to a top → bottom
/// [LinearGradient]: CSS angles run clockwise from "to top", so 180° is
/// top → bottom and anything below it leans right.
GradientTransform _cssAngle(double degrees) =>
    GradientRotation((degrees - 180) * math.pi / 180);

/// Drawer menu — overlay on mobile/tablet, persistent sidebar on desktop.
///
/// **Overlay mode** (`persistent: false`, default): a floating gradient panel
/// slides in from the left over a fading scrim; tapping the scrim slides it
/// back out and then calls [onClose].
/// **Persistent mode** (`persistent: true`): the same panel as a fixed-width
/// sidebar column, suitable for embedding in a [Row] on desktop.
///
/// Header: mascot, wordmark, tagline and release-stage chip.
/// Desktop nav: Order Book, My Trades, Chat — active item highlighted.
/// Account items: Account, Settings, About — never shown as selected.
/// Footer: app version.
class DrawerMenu extends ConsumerWidget {
  const DrawerMenu({super.key, this.onClose, this.persistent = false});

  /// Called when the overlay drawer is dismissed (overlay mode only).
  final VoidCallback? onClose;

  /// When `true` the widget renders as a sidebar column rather than an overlay.
  final bool persistent;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = DrawerPalette.of(context);
    final tradesCount =
        persistent ? ref.watch(orderBookNotificationCountProvider) : 0;
    final chatCount = persistent ? ref.watch(chatNotificationCountProvider) : 0;
    // Loading and a failed read both hide the version line.
    final version = ref.watch(appVersionProvider).valueOrNull;

    final content = _SidebarContent(
      palette: palette,
      persistent: persistent,
      tradesCount: tradesCount,
      chatCount: chatCount,
      version: version,
      onNavigate: persistent ? null : onClose,
    );

    if (persistent) {
      return SizedBox(
        width: _panelWidth,
        child: _Panel(palette: palette, floating: false, child: content),
      );
    }

    return _OverlayDrawer(palette: palette, onClose: onClose, child: content);
  }
}

// ── Overlay: scrim + sliding panel ───────────────────────────────────────────

class _OverlayDrawer extends StatefulWidget {
  const _OverlayDrawer({
    required this.palette,
    required this.onClose,
    required this.child,
  });

  final DrawerPalette palette;
  final VoidCallback? onClose;
  final Widget child;

  @override
  State<_OverlayDrawer> createState() => _OverlayDrawerState();
}

class _OverlayDrawerState extends State<_OverlayDrawer>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: _slideDuration,
  )..forward();

  late final Animation<double> _progress = CurvedAnimation(
    parent: _controller,
    curve: Curves.fastOutSlowIn,
  );

  late final Animation<Offset> _slide = Tween(
    begin: const Offset(-1, 0),
    end: Offset.zero,
  ).animate(_progress);

  bool _dismissing = false;

  Future<void> _dismiss() async {
    if (_dismissing) return;
    _dismissing = true;
    await _controller.reverse();
    if (mounted) widget.onClose?.call();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final width = math.min(
      _panelWidth,
      MediaQuery.sizeOf(context).width - _minScrimWidth,
    );

    return Stack(
      children: [
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: _dismiss,
            child: FadeTransition(
              opacity: _progress,
              child: ColoredBox(color: widget.palette.scrim),
            ),
          ),
        ),
        Align(
          alignment: Alignment.centerLeft,
          child: SlideTransition(
            position: _slide,
            child: SizedBox(
              width: width,
              height: double.infinity,
              child: _Panel(
                palette: widget.palette,
                floating: true,
                child: widget.child,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

// ── Panel surface: gradient, halos, edge ─────────────────────────────────────

class _Panel extends StatelessWidget {
  const _Panel({
    required this.palette,
    required this.floating,
    required this.child,
  });

  final DrawerPalette palette;

  /// Overlay panels round their right edge and cast a shadow; the desktop
  /// sidebar sits flush against its divider.
  final bool floating;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final radius =
        floating
            ? const BorderRadius.horizontal(
              right: Radius.circular(_panelRadius),
            )
            : BorderRadius.zero;

    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: radius,
        boxShadow: floating ? palette.panelShadow : null,
      ),
      child: ClipRRect(
        borderRadius: radius,
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: palette.panelGradient,
              stops: palette.panelGradientStops,
              transform: _cssAngle(175),
            ),
          ),
          child: Stack(
            children: [
              Positioned(
                top: -70,
                left: -60,
                child: _Halo(size: 280, color: palette.haloGreen),
              ),
              Positioned(
                bottom: -90,
                right: -70,
                child: _Halo(size: 240, color: palette.haloYellow),
              ),
              if (floating)
                Positioned(
                  top: 0,
                  right: 0,
                  bottom: 0,
                  width: 1,
                  child: ColoredBox(color: palette.panelBorder),
                ),
              Positioned.fill(child: child),
            ],
          ),
        ),
      ),
    );
  }
}

class _Halo extends StatelessWidget {
  const _Halo({required this.size, required this.color});

  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: SizedBox.square(
        dimension: size,
        child: DecoratedBox(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: RadialGradient(
              radius: _farthestCornerRadius,
              colors: [color, color.withValues(alpha: 0)],
              stops: const [0, 0.7],
            ),
          ),
        ),
      ),
    );
  }
}

// ── Sidebar content (shared between overlay and persistent modes) ─────────────

class _SidebarContent extends StatelessWidget {
  const _SidebarContent({
    required this.palette,
    required this.persistent,
    required this.tradesCount,
    required this.chatCount,
    required this.version,
    required this.onNavigate,
  });

  final DrawerPalette palette;
  final bool persistent;
  final int tradesCount;
  final int chatCount;
  final String? version;

  /// Called before each navigation push (closes overlay drawer if not null).
  final VoidCallback? onNavigate;

  @override
  Widget build(BuildContext context) {
    final insets = MediaQuery.paddingOf(context);

    // Scrolls only when the content outgrows the panel (large text scale,
    // short landscape screens); otherwise the footer is pinned to the bottom.
    return SafeArea(
      top: false,
      bottom: false,
      right: false,
      child: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _Header(
                  palette: palette,
                  top: math.max(_headerTop, insets.top + _headerSafeGap),
                ),
                _GradientLine(
                  height: 2,
                  colors: palette.accentDivider,
                  margin: _contentInset,
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    _listInset,
                    28,
                    _listInset,
                    0,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: _menuRows(context),
                  ),
                ),
              ],
            ),
          ),
          SliverFillRemaining(
            hasScrollBody: false,
            child: Align(
              alignment: Alignment.bottomCenter,
              child: _Footer(
                palette: palette,
                version: version,
                bottom: 30 + insets.bottom,
              ),
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _menuRows(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    Widget accountRow(String id, IconData icon, String label, String route) {
      return _MenuRow(
        automationId: id,
        palette: palette,
        icon: icon,
        label: label,
        showChevron: true,
        onTap: () {
          onNavigate?.call();
          context.push(route);
        },
      );
    }

    final accountRows = [
      accountRow(
        AutomationIds.drawerAccount,
        Icons.key_outlined,
        l10n.drawerAccountMenuItem,
        AppRoute.keyManagement,
      ),
      accountRow(
        AutomationIds.drawerSettings,
        Icons.settings_outlined,
        l10n.drawerSettingsMenuItem,
        AppRoute.settings,
      ),
      accountRow(
        AutomationIds.drawerAbout,
        Icons.info_outline,
        l10n.drawerAboutMenuItem,
        AppRoute.about,
      ),
    ];

    return _withGaps([
      if (persistent) ..._navRows(context, l10n),
      if (persistent)
        _GradientLine(
          height: 1,
          colors: palette.footerHairline,
          margin: _rowGap,
        ),
      ...accountRows,
    ]);
  }

  List<Widget> _navRows(BuildContext context, AppLocalizations l10n) {
    final currentPath = GoRouterState.of(context).uri.path;

    return [
      _MenuRow(
        automationId: AutomationIds.navOrderBook,
        palette: palette,
        icon:
            currentPath == AppRoute.home
                ? Icons.list_alt
                : Icons.list_alt_outlined,
        label: l10n.navOrderBook,
        selected: currentPath == AppRoute.home,
        onTap: () => context.go(AppRoute.home),
      ),
      _MenuRow(
        automationId: AutomationIds.navTrades,
        palette: palette,
        icon:
            currentPath.startsWith(AppRoute.orderBook)
                ? Icons.bolt
                : Icons.bolt_outlined,
        label: l10n.navMyTrades,
        selected: currentPath.startsWith(AppRoute.orderBook),
        badgeCount: tradesCount,
        onTap: () => context.go(AppRoute.orderBook),
      ),
      _MenuRow(
        automationId: AutomationIds.navChat,
        palette: palette,
        icon:
            currentPath.startsWith(AppRoute.chatList)
                ? Icons.chat_bubble
                : Icons.chat_bubble_outline,
        label: l10n.navChat,
        selected: currentPath.startsWith(AppRoute.chatList),
        badgeCount: chatCount,
        onTap: () => context.go(AppRoute.chatList),
      ),
    ];
  }

  static List<Widget> _withGaps(List<Widget> rows) => [
    for (var i = 0; i < rows.length; i++) ...[
      if (i > 0) const SizedBox(height: _rowGap),
      rows[i],
    ],
  ];
}

// ── Header ────────────────────────────────────────────────────────────────────

class _Header extends StatelessWidget {
  const _Header({required this.palette, required this.top});

  final DrawerPalette palette;
  final double top;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return Padding(
      padding: EdgeInsets.fromLTRB(
        _contentInset,
        top,
        _contentInset,
        _contentInset,
      ),
      child: Row(
        children: [
          _Mascot(palette: palette),
          const SizedBox(width: 13),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  l10n.drawerTitle,
                  style: TextStyle(
                    color: palette.wordmark,
                    fontSize: 21,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.21,
                    height: 1,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  l10n.drawerTagline.toUpperCase(),
                  semanticsLabel: l10n.drawerTagline,
                  style: TextStyle(
                    color: palette.tagline,
                    fontSize: 10,
                    fontWeight: FontWeight.w400,
                    letterSpacing: 1.8,
                    height: 1,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: _rowGap),
          _StageChip(palette: palette),
        ],
      ),
    );
  }
}

class _Mascot extends StatelessWidget {
  const _Mascot({required this.palette});

  final DrawerPalette palette;

  @override
  Widget build(BuildContext context) {
    final image = Image.asset(
      _mascotAsset,
      height: _logoHeight,
      fit: BoxFit.contain,
      excludeFromSemantics: true,
    );
    final sigma = palette.logoShadowBlur / 2;

    // CSS `drop-shadow`: a blurred silhouette of the image, tinted and
    // offset 6 below it.
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Transform.translate(
          offset: const Offset(0, 6),
          child: ImageFiltered(
            imageFilter: ImageFilter.blur(sigmaX: sigma, sigmaY: sigma),
            child: ColorFiltered(
              colorFilter: ColorFilter.mode(
                palette.logoShadow,
                BlendMode.srcIn,
              ),
              child: image,
            ),
          ),
        ),
        image,
      ],
    );
  }
}

class _StageChip extends StatelessWidget {
  const _StageChip({required this.palette});

  final DrawerPalette palette;

  @override
  Widget build(BuildContext context) {
    final label = AppLocalizations.of(context).drawerStageBadge;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: palette.chipFill,
        border: Border.all(color: palette.chipBorder),
        borderRadius: BorderRadius.circular(999),
        boxShadow: palette.chipGlow,
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
        child: Text(
          label.toUpperCase(),
          semanticsLabel: label,
          style: TextStyle(
            color: palette.chipText,
            fontSize: 10,
            fontWeight: FontWeight.w600,
            letterSpacing: 1.2,
          ),
        ),
      ),
    );
  }
}

/// A thin horizontal gradient rule (header accent, footer hairline).
class _GradientLine extends StatelessWidget {
  const _GradientLine({
    required this.height,
    required this.colors,
    required this.margin,
  });

  final double height;
  final List<Color> colors;
  final double margin;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: margin),
      child: SizedBox(
        height: height,
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(height),
            gradient: LinearGradient(colors: colors),
          ),
        ),
      ),
    );
  }
}

// ── Menu row ──────────────────────────────────────────────────────────────────

class _MenuRow extends StatefulWidget {
  const _MenuRow({
    required this.automationId,
    required this.palette,
    required this.icon,
    required this.label,
    required this.onTap,
    this.selected,
    this.badgeCount = 0,
    this.showChevron = false,
  });

  /// Stable identifier for UI automation; see `AutomationIds`.
  final String automationId;

  final DrawerPalette palette;
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  /// Only desktop destinations carry a selection state; account rows leave
  /// it null so they are never announced as selected.
  final bool? selected;
  final int badgeCount;

  /// Rows that open another screen show a trailing chevron.
  final bool showChevron;

  @override
  State<_MenuRow> createState() => _MenuRowState();
}

class _MenuRowState extends State<_MenuRow> {
  bool _pressed = false;
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final palette = widget.palette;
    final l10n = AppLocalizations.of(context);
    final isActive = _pressed || _hovered || (widget.selected ?? false);
    final radius = BorderRadius.circular(_rowRadius);

    return Semantics(
      identifier: widget.automationId,
      button: true,
      label: automationSemanticLabel(widget.automationId, widget.label),
      selected: widget.selected,
      hint:
          widget.badgeCount > 0
              ? l10n.drawerBadgeNewCount(widget.badgeCount)
              : null,
      child: Material(
        type: MaterialType.transparency,
        child: Ink(
          decoration: BoxDecoration(
            color: isActive ? palette.itemFillActive : palette.itemFill,
            border: Border.all(
              color: isActive ? palette.itemBorderActive : palette.itemBorder,
            ),
            borderRadius: radius,
            boxShadow: palette.itemShadow,
          ),
          child: InkWell(
            onTap: widget.onTap,
            onHighlightChanged: (value) => setState(() => _pressed = value),
            onHover: (value) => setState(() => _hovered = value),
            borderRadius: radius,
            highlightColor: Colors.transparent,
            splashColor: palette.itemFillActive,
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: _rowMinHeight),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: AppSpacing.sm,
                ),
                child: Row(
                  children: [
                    _IconTile(palette: palette, icon: widget.icon),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Text(
                        widget.label,
                        style: TextStyle(
                          color: palette.itemLabel,
                          fontSize: 16,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                    if (widget.badgeCount > 0) const _BadgeDot(),
                    if (widget.showChevron)
                      Icon(
                        Icons.chevron_right,
                        size: 16,
                        color: palette.chevron,
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _IconTile extends StatelessWidget {
  const _IconTile({required this.palette, required this.icon});

  final DrawerPalette palette;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: _tileSize,
      height: _tileSize,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(_tileRadius),
        border: Border.all(color: palette.iconTileBorder),
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: palette.iconTileGradient,
          transform: _cssAngle(150),
        ),
      ),
      child: Icon(icon, size: 19, color: palette.icon),
    );
  }
}

class _BadgeDot extends StatelessWidget {
  const _BadgeDot();

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppColors>();
    return Container(
      width: 8,
      height: 8,
      decoration: BoxDecoration(
        color: colors?.destructiveRed ?? const Color(0xFFD84D4D),
        shape: BoxShape.circle,
      ),
    );
  }
}

// ── Footer ────────────────────────────────────────────────────────────────────

class _Footer extends StatelessWidget {
  const _Footer({
    required this.palette,
    required this.version,
    required this.bottom,
  });

  final DrawerPalette palette;
  final String? version;
  final double bottom;

  @override
  Widget build(BuildContext context) {
    final version = this.version;

    return Padding(
      padding: EdgeInsets.fromLTRB(
        _contentInset,
        AppSpacing.xl,
        _contentInset,
        bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _GradientLine(height: 1, colors: palette.footerHairline, margin: 0),
          if (version != null) ...[
            const SizedBox(height: AppSpacing.md),
            Row(
              children: [
                Icon(Icons.bolt, size: 13, color: palette.footerGlyph),
                const SizedBox(width: _rowGap),
                Flexible(
                  child: Text(
                    AppLocalizations.of(context).drawerVersion(version),
                    style: TextStyle(
                      color: palette.footerText,
                      fontSize: 11,
                      fontWeight: FontWeight.w400,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

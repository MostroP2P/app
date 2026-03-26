/// Responsive layout scaffold for Mostro.
///
/// Breakpoints:
///   < 600 dp   → phone  : BottomNavigationBar
///   600–1199 dp → tablet : NavigationRail (left)
///   ≥ 1200 dp  → desktop: NavigationDrawer (left, expanded)
///
/// Usage:
///   ResponsiveLayout(
///     phone: (context) => PhoneShell(body: child, ...),
///     tablet: (context) => TabletShell(body: child, ...),
///     desktop: (context) => DesktopShell(body: child, ...),
///   )
///
/// Or use [ResponsiveLayout.builder] for a single adaptive builder.
library responsive_layout;

import 'package:flutter/material.dart';

const double _kTabletBreakpoint = 600;
const double _kDesktopBreakpoint = 1200;

enum _FormFactor { phone, tablet, desktop }

_FormFactor _formFactor(double width) {
  if (width >= _kDesktopBreakpoint) return _FormFactor.desktop;
  if (width >= _kTabletBreakpoint) return _FormFactor.tablet;
  return _FormFactor.phone;
}

/// Selects one of three widget builders based on screen width.
class ResponsiveLayout extends StatelessWidget {
  const ResponsiveLayout({
    super.key,
    required this.phone,
    required this.tablet,
    required this.desktop,
  });

  final WidgetBuilder phone;
  final WidgetBuilder tablet;
  final WidgetBuilder desktop;

  /// Single builder receiving the current [FormFactor].
  static Widget builder({
    Key? key,
    required Widget Function(BuildContext context, bool isPhone, bool isTablet,
            bool isDesktop)
        builder,
  }) {
    return LayoutBuilder(
      key: key,
      builder: (context, constraints) {
        final ff = _formFactor(constraints.maxWidth);
        return builder(
          context,
          ff == _FormFactor.phone,
          ff == _FormFactor.tablet,
          ff == _FormFactor.desktop,
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final ff = _formFactor(constraints.maxWidth);
        return switch (ff) {
          _FormFactor.phone => phone(context),
          _FormFactor.tablet => tablet(context),
          _FormFactor.desktop => desktop(context),
        };
      },
    );
  }
}

// ─── Navigation destination model ────────────────────────────────────────────

class NavDestination {
  const NavDestination({
    required this.icon,
    required this.selectedIcon,
    required this.label,
    required this.route,
  });

  final Widget icon;
  final Widget selectedIcon;
  final String label;
  final String route;
}

// ─── App shell scaffolds ─────────────────────────────────────────────────────

/// Phone shell: body + BottomNavigationBar.
class PhoneShell extends StatelessWidget {
  const PhoneShell({
    super.key,
    required this.body,
    required this.destinations,
    required this.selectedIndex,
    required this.onDestinationSelected,
  });

  final Widget body;
  final List<NavDestination> destinations;
  final int selectedIndex;
  final ValueChanged<int> onDestinationSelected;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: body,
      bottomNavigationBar: NavigationBar(
        selectedIndex: selectedIndex,
        onDestinationSelected: onDestinationSelected,
        destinations: destinations
            .map(
              (d) => NavigationDestination(
                icon: d.icon,
                selectedIcon: d.selectedIcon,
                label: d.label,
              ),
            )
            .toList(),
      ),
    );
  }
}

/// Tablet shell: NavigationRail on the left + body.
class TabletShell extends StatelessWidget {
  const TabletShell({
    super.key,
    required this.body,
    required this.destinations,
    required this.selectedIndex,
    required this.onDestinationSelected,
  });

  final Widget body;
  final List<NavDestination> destinations;
  final int selectedIndex;
  final ValueChanged<int> onDestinationSelected;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Row(
        children: [
          NavigationRail(
            selectedIndex: selectedIndex,
            onDestinationSelected: onDestinationSelected,
            labelType: NavigationRailLabelType.selected,
            destinations: destinations
                .map(
                  (d) => NavigationRailDestination(
                    icon: d.icon,
                    selectedIcon: d.selectedIcon,
                    label: Text(d.label),
                  ),
                )
                .toList(),
          ),
          const VerticalDivider(width: 1),
          Expanded(child: body),
        ],
      ),
    );
  }
}

/// Desktop shell: persistent NavigationDrawer on the left + body.
class DesktopShell extends StatelessWidget {
  const DesktopShell({
    super.key,
    required this.body,
    required this.destinations,
    required this.selectedIndex,
    required this.onDestinationSelected,
    this.appTitle = 'Mostro',
  });

  final Widget body;
  final List<NavDestination> destinations;
  final int selectedIndex;
  final ValueChanged<int> onDestinationSelected;
  final String appTitle;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Scaffold(
      body: Row(
        children: [
          SizedBox(
            width: 256,
            child: Material(
              color: colorScheme.surface,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(24, 32, 24, 24),
                    child: Text(
                      appTitle,
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                  ),
                  ...destinations.asMap().entries.map((entry) {
                    final idx = entry.key;
                    final d = entry.value;
                    final selected = idx == selectedIndex;
                    return ListTile(
                      leading: selected ? d.selectedIcon : d.icon,
                      title: Text(d.label),
                      selected: selected,
                      selectedTileColor:
                          colorScheme.primary.withValues(alpha: 0.1),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      contentPadding:
                          const EdgeInsets.symmetric(horizontal: 16),
                      onTap: () => onDestinationSelected(idx),
                    );
                  }),
                ],
              ),
            ),
          ),
          const VerticalDivider(width: 1),
          Expanded(child: body),
        ],
      ),
    );
  }
}

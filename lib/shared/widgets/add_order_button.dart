import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:mostro/core/app_routes.dart';
import 'package:mostro/core/app_theme.dart';

/// Expandable FAB for creating orders.
///
/// Collapsed: circular 56dp green "+" button.
/// Expanded: gray "×", dark overlay, two stacked buttons (Buy + Sell).
class AddOrderButton extends StatefulWidget {
  const AddOrderButton({super.key});

  @override
  State<AddOrderButton> createState() => _AddOrderButtonState();
}

class _AddOrderButtonState extends State<AddOrderButton>
    with SingleTickerProviderStateMixin {
  bool _expanded = false;

  late final AnimationController _controller;
  late final Animation<double> _expandAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
    );
    _expandAnimation = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOut,
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _toggle() {
    setState(() => _expanded = !_expanded);
    if (_expanded) {
      _controller.forward();
    } else {
      _controller.reverse();
    }
  }

  void _collapse() {
    if (_expanded) _toggle();
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppColors>();
    final green = colors?.mostroGreen ?? const Color(0xFF8CC63F);
    final sellColor = colors?.sellColor ?? const Color(0xFFFF8A8A);

    return Stack(
      alignment: Alignment.bottomRight,
      children: [
        // Dark overlay
        if (_expanded)
          Positioned.fill(
            child: GestureDetector(
              onTap: _collapse,
              child: Container(
                color: Colors.black.withValues(alpha: 0.3),
              ),
            ),
          ),

        // Sub-buttons + main FAB column
        Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            // Buy button
            FadeTransition(
              opacity: _expandAnimation,
              child: ScaleTransition(
                scale: _expandAnimation,
                alignment: Alignment.bottomRight,
                child: Padding(
                  padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                  child: _SubButton(
                    label: 'Buy',
                    icon: Icons.arrow_downward,
                    color: green,
                    onTap: () {
                      _collapse();
                      context.push('${AppRoute.addOrder}?type=buy');
                    },
                  ),
                ),
              ),
            ),

            // Sell button
            FadeTransition(
              opacity: _expandAnimation,
              child: ScaleTransition(
                scale: _expandAnimation,
                alignment: Alignment.bottomRight,
                child: Padding(
                  padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                  child: _SubButton(
                    label: 'Sell',
                    icon: Icons.arrow_upward,
                    color: sellColor,
                    onTap: () {
                      _collapse();
                      context.push('${AppRoute.addOrder}?type=sell');
                    },
                  ),
                ),
              ),
            ),

            // Main FAB
            FloatingActionButton(
              heroTag: 'addOrderFab',
              onPressed: _toggle,
              backgroundColor: _expanded ? Colors.grey[700] : green,
              child: AnimatedRotation(
                turns: _expanded ? 0.125 : 0,
                duration: const Duration(milliseconds: 200),
                child: Icon(
                  _expanded ? Icons.close : Icons.add,
                  color: _expanded ? Colors.white : Colors.black,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _SubButton extends StatelessWidget {
  const _SubButton({
    required this.label,
    required this.icon,
    required this.color,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: color,
      borderRadius: BorderRadius.circular(AppRadius.button),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.button),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.lg,
            vertical: AppSpacing.md,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 18, color: Colors.black),
              const SizedBox(width: AppSpacing.sm),
              Text(
                label,
                style: const TextStyle(
                  color: Colors.black,
                  fontWeight: FontWeight.w600,
                  fontSize: 14,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

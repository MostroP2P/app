import 'package:flutter/material.dart';

import 'package:mostro/core/app_theme.dart';
import 'package:mostro/core/backup_palette.dart';

/// A card of the Account screen: the surface, its radius, and [children]
/// [gap] apart.
class AccountCard extends StatelessWidget {
  const AccountCard({
    super.key,
    required this.padding,
    required this.gap,
    required this.children,
  });

  final EdgeInsets padding;
  final double gap;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: OrderBookPalette.of(context).surface,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < children.length; i++) ...[
            if (i > 0) SizedBox(height: gap),
            children[i],
          ],
        ],
      ),
    );
  }
}

/// The icon and title a card of the Account screen opens with.
class AccountCardHeader extends StatelessWidget {
  const AccountCardHeader({
    super.key,
    required this.icon,
    required this.title,
    this.trailing,
  });

  final IconData icon;
  final String title;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 18, color: BackupPalette.of(context).accent),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            title,
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: OrderBookPalette.of(context).textStrong,
            ),
          ),
        ),
        if (trailing case final trailing?) trailing,
      ],
    );
  }
}

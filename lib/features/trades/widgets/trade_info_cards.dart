import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:mostro/core/app_theme.dart';

/// Reusable info card container for trade detail.
class TradeInfoCard extends StatelessWidget {
  const TradeInfoCard({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppColors>();
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: colors?.backgroundCard ?? const Color(0xFF1E2230),
        borderRadius: BorderRadius.circular(AppRadius.card),
      ),
      child: child,
    );
  }
}

/// Order ID card with copy-to-clipboard.
class OrderIdCard extends StatelessWidget {
  const OrderIdCard({super.key, required this.orderId});

  final String orderId;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return TradeInfoCard(
      child: Row(
        children: [
          Expanded(
            child: Text(
              orderId,
              style: theme.textTheme.bodySmall!.copyWith(
                fontFamily: 'monospace',
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          IconButton(
            onPressed: () {
              Clipboard.setData(ClipboardData(text: orderId));
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Order ID copied'),
                  duration: Duration(seconds: 1),
                ),
              );
            },
            icon: const Icon(Icons.copy, size: 18),
            tooltip: 'Copy order ID',
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
          ),
        ],
      ),
    );
  }
}

/// Instructions card with green lightning bolt icon.
class InstructionsCard extends StatelessWidget {
  const InstructionsCard({
    super.key,
    required this.text,
    required this.statusLabel,
  });

  final String text;
  final String statusLabel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.extension<AppColors>();
    final green = colors?.mostroGreen ?? const Color(0xFF8CC63F);

    return TradeInfoCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.bolt, color: green, size: 20),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(text, style: theme.textTheme.bodyMedium),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.sm,
              vertical: 2,
            ),
            decoration: BoxDecoration(
              color: green.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(AppRadius.chip),
            ),
            child: Text(
              statusLabel,
              style: TextStyle(
                color: green,
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

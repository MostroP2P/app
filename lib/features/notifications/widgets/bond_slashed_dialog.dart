import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:mostro/core/app_routes.dart';
import 'package:mostro/core/automation/automation_id.dart';
import 'package:mostro/core/automation/automation_ids.dart';
import 'package:mostro/features/notifications/models/notification_model.dart';
import 'package:mostro/features/trades/providers/trades_providers.dart';
import 'package:mostro/l10n/app_localizations.dart';

/// What a `bond-slashed` notice means, on tap (docs/ANTI_ABUSE_BOND.md §8.5,
/// mock 145-bond-slashed): the cause and the amount, the order, and a way to
/// the node's bond policy on the About screen. "View trade" only while the
/// trade row still exists: a timeout slash follows a resolution that wiped
/// the never-active row, and the trade screen would only send the user
/// straight back.
class BondSlashedDialog extends ConsumerWidget {
  const BondSlashedDialog({super.key, required this.notification});

  final NotificationModel notification;

  static Future<void> show(BuildContext context, NotificationModel n) =>
      showDialog<void>(
        context: context,
        builder: (_) => BondSlashedDialog(notification: n),
      );

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final detail = notification.resolvedDetail(l10n);
    final orderId = notification.orderId;
    final tradeExists =
        orderId != null &&
        ref.watch(tradeInfoProvider(orderId)).valueOrNull != null;
    return AlertDialog(
      title: Text(notification.resolvedTitle(l10n)),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(notification.resolvedMessage(l10n)),
          const SizedBox(height: 12),
          for (final entry in detail.entries)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text(
                      entry.key,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 2,
                    child: Text(
                      entry.value,
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () {
            Navigator.of(context).pop();
            context.push(AppRoute.about);
          },
          child: Text(l10n.bondSlashedViewPolicy),
        ).withAutomationId(AutomationIds.bondSlashedViewPolicy),
        if (tradeExists)
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
              context.push(AppRoute.tradeDetailPath(orderId));
            },
            child: Text(l10n.bondSlashedViewTrade),
          ).withAutomationId(AutomationIds.bondSlashedViewTrade),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.closeButtonLabel),
        ).withAutomationId(AutomationIds.bondSlashedClose),
      ],
    );
  }
}

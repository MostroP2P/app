import 'package:flutter/material.dart';

import 'package:mostro/core/node_selector_palette.dart';
import 'package:mostro/core/order_book_palette.dart';
import 'package:mostro/l10n/app_localizations.dart';

/// Asks before switching nodes while a trade is in progress: changing node
/// changes market, and the running trade stays on the node it started on.
///
/// Returns `true` when the user confirms.
Future<bool> showNodeSwitchConfirmSheet(
  BuildContext context, {
  required String currentNode,
  required String newNode,
}) async {
  final book = OrderBookPalette.of(context);
  final confirmed = await showModalBottomSheet<bool>(
    context: context,
    backgroundColor: book.surface,
    barrierColor: book.scrim,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder:
        (_) =>
            _NodeSwitchConfirmSheet(currentNode: currentNode, newNode: newNode),
  );
  return confirmed ?? false;
}

class _NodeSwitchConfirmSheet extends StatelessWidget {
  const _NodeSwitchConfirmSheet({
    required this.currentNode,
    required this.newNode,
  });

  final String currentNode;
  final String newNode;

  @override
  Widget build(BuildContext context) {
    final book = OrderBookPalette.of(context);
    final pal = NodeSelectorPalette.of(context);
    final l10n = AppLocalizations.of(context);

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 10, 18, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: book.textPrimary.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
            ),
            const SizedBox(height: 18),
            Text(
              l10n.nodeSwitchConfirmTitle,
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w600,
                color: book.textPrimary,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              l10n.nodeSwitchConfirmBody(currentNode, newNode),
              style: TextStyle(
                fontSize: 13,
                height: 1.5,
                color: book.textSecondary,
              ),
            ),
            const SizedBox(height: 18),
            Row(
              children: [
                Expanded(
                  flex: 10,
                  child: OutlinedButton(
                    onPressed: () => Navigator.of(context).pop(false),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: book.textBody,
                      side: BorderSide(color: pal.buttonBorder),
                      padding: const EdgeInsets.symmetric(vertical: 13),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    child: Text(
                      l10n.cancel,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  flex: 13,
                  child: FilledButton(
                    onPressed: () => Navigator.of(context).pop(true),
                    style: FilledButton.styleFrom(
                      backgroundColor: book.lime,
                      foregroundColor: book.onLime,
                      padding: const EdgeInsets.symmetric(vertical: 13),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    child: Text(
                      l10n.nodeSwitchConfirmAction,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

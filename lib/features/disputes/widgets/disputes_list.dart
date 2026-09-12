import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:mostro/core/activity_palette.dart';
import 'package:mostro/core/order_book_palette.dart';
import 'package:mostro/features/disputes/providers/disputes_providers.dart';
import 'package:mostro/features/disputes/widgets/dispute_list_item.dart';
import 'package:mostro/l10n/app_localizations.dart';
import 'package:mostro/shared/widgets/tab_app_bar.dart' show GroupHeader;

/// The Disputes segment of the chat tab (handoff 11b): the same grouped
/// cards as the conversations — open disputes, then resolved ones stepped
/// back at [ActivityPalette.closedOpacity].
class DisputesList extends ConsumerWidget {
  const DisputesList({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final book = OrderBookPalette.of(context);
    final pal = ActivityPalette.of(context);
    final l10n = AppLocalizations.of(context);
    final disputesAsync = ref.watch(userDisputeDataProvider);

    return disputesAsync.when(
      loading: () => Center(child: CircularProgressIndicator(color: book.lime)),
      error: (err, stack) {
        debugPrint('Disputes load error: $err\n$stack');
        return _Centered(
          icon: Icons.error_outline_rounded,
          title: l10n.disputeLoadError,
          action: TextButton(
            onPressed: () => ref.invalidate(userDisputeDataProvider),
            child: Text(l10n.retry),
          ),
        );
      },
      data: (disputes) {
        if (disputes.isEmpty) {
          return _Centered(
            icon: Icons.gavel_rounded,
            title: l10n.disputesEmptyState,
          );
        }
        final open =
            disputes.where((d) => d.status != DisputeStatus.resolved).toList();
        final closed =
            disputes.where((d) => d.status == DisputeStatus.resolved).toList();
        return ListView(
          padding: const EdgeInsets.fromLTRB(18, 0, 18, 18),
          children: [
            if (open.isNotEmpty)
              _Group(
                title: l10n.tradeListChipDispute,
                disputes: open,
                color: pal.groupHeader,
              ),
            if (open.isNotEmpty && closed.isNotEmpty)
              const SizedBox(height: 18),
            if (closed.isNotEmpty)
              Opacity(
                opacity: ActivityPalette.closedOpacity,
                child: _Group(
                  title: l10n.tradesGroupClosed,
                  disputes: closed,
                  color: pal.groupHeader,
                ),
              ),
          ],
        );
      },
    );
  }
}

class _Group extends StatelessWidget {
  const _Group({
    required this.title,
    required this.disputes,
    required this.color,
  });

  final String title;
  final List<DisputeItem> disputes;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final book = OrderBookPalette.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        GroupHeader(title: title, count: disputes.length, color: color),
        const SizedBox(height: 10),
        Material(
          color: book.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
            side: BorderSide(color: book.border),
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            children: [
              for (final (i, d) in disputes.indexed)
                DisputeListItem(
                  key: ValueKey(d.id),
                  dispute: d,
                  isLast: i == disputes.length - 1,
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _Centered extends StatelessWidget {
  const _Centered({required this.icon, required this.title, this.action});

  final IconData icon;
  final String title;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final book = OrderBookPalette.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 28,
              color: ActivityPalette.of(context).chevronIdle,
            ),
            const SizedBox(height: 12),
            Text(
              title,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: book.textMuted,
              ),
            ),
            if (action != null) ...[const SizedBox(height: 8), action!],
          ],
        ),
      ),
    );
  }
}

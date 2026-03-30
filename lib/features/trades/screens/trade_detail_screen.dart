import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:mostro/core/app_routes.dart';
import 'package:mostro/core/app_theme.dart';
import 'package:mostro/features/disputes/providers/disputes_providers.dart';
import 'package:mostro/features/trades/widgets/release_confirmation_dialog.dart';
import 'package:mostro/features/trades/widgets/trade_info_cards.dart';
import 'package:mostro/shared/widgets/mostro_reactive_button.dart';

/// Trade detail screen — Route `/trade_detail/:orderId`.
///
/// Shows trade summary, payment method, dates, order ID, instructions,
/// countdown timer, and role-based action buttons.
class TradeDetailScreen extends ConsumerStatefulWidget {
  const TradeDetailScreen({super.key, required this.orderId});

  final String orderId;

  @override
  ConsumerState<TradeDetailScreen> createState() => _TradeDetailScreenState();
}

/// Default trade countdown duration (matches Mostro daemon default).
const _kCountdownSeconds = 900; // 15 minutes

/// Type-safe trade status for the detail screen.
/// Will map to/from Rust bridge TradeStep when wired.
enum TradeStatus {
  active('Active'),
  fiatSent('Fiat Sent'),
  completed('Completed'),
  cancelled('Cancelled'),
  disputed('Disputed');

  const TradeStatus(this.label);
  final String label;
}

class _TradeDetailScreenState extends ConsumerState<TradeDetailScreen> {
  Timer? _countdownTimer;
  Duration _remaining = const Duration(seconds: _kCountdownSeconds);

  // TODO(bridge): Replace with real state from a TradeInfo Riverpod
  // provider backed by the Rust bridge once FFI bindings expose
  // TradeInfo for widget.orderId. Map TradeInfo.current_step to
  // TradeStatus and TradeInfo.role to _isBuyer.
  TradeStatus _status = TradeStatus.active;
  // ignore: prefer_final_fields
  bool _isBuyer = true;

  @override
  void initState() {
    super.initState();
    _startCountdown();
  }

  @override
  void dispose() {
    _countdownTimer?.cancel();
    super.dispose();
  }

  void _startCountdown() {
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() {
        final next = _remaining - const Duration(seconds: 1);
        if (next.inSeconds <= 0) {
          _countdownTimer?.cancel();
          _remaining = Duration.zero;
        } else {
          _remaining = next;
        }
      });
    });
  }

  String _getInstructionText() {
    if (_isBuyer) {
      if (_status == TradeStatus.active) {
        return 'Send the fiat payment to the seller, then tap "Fiat Sent".';
      } else if (_status == TradeStatus.fiatSent) {
        return 'Fiat payment marked as sent. Waiting for the seller '
            'to confirm receipt and release your sats.';
      }
    } else {
      // Seller
      if (_status == TradeStatus.active) {
        return 'Contact the buyer with payment instructions.';
      } else if (_status == TradeStatus.fiatSent) {
        return 'The buyer has confirmed they sent the fiat payment. '
            'Once you verify receipt, release the sats.';
      }
    }
    if (_status == TradeStatus.disputed) {
      return 'A dispute resolver has been assigned. '
          'They will contact you through the app.';
    }
    return 'Trade in progress.';
  }

  String _formatDuration(Duration d) {
    if (d.isNegative) return '00:00:00';
    final h = d.inHours.toString().padLeft(2, '0');
    final m = (d.inMinutes % 60).toString().padLeft(2, '0');
    final s = (d.inSeconds % 60).toString().padLeft(2, '0');
    return '$h:$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.extension<AppColors>();
    final green = colors?.mostroGreen ?? const Color(0xFF8CC63F);
    final textSec = colors?.textSecondary ?? const Color(0xFFB0B3C6);

    return Scaffold(
      appBar: AppBar(title: const Text('ORDER DETAILS')),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.lg),
        children: [
          // Card 1: Trade summary
          TradeInfoCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _isBuyer
                      ? 'You are buying sats'
                      : 'You are selling sats',
                  style: theme.textTheme.headlineSmall,
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  'Order ${widget.orderId}',
                  style: TextStyle(color: textSec, fontSize: 12),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.sm),

          // Card 2: Payment method
          TradeInfoCard(
            child: Row(
              children: [
                Icon(Icons.payment_outlined, size: 18, color: textSec),
                const SizedBox(width: AppSpacing.sm),
                Text('Mercado Pago', style: theme.textTheme.bodyMedium),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.sm),

          // Card 3: Creation date
          TradeInfoCard(
            child: Row(
              children: [
                Icon(Icons.calendar_today_outlined, size: 18, color: textSec),
                const SizedBox(width: AppSpacing.sm),
                Text('2024-01-15 14:30', style: theme.textTheme.bodyMedium),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.sm),

          // Card 4: Order ID
          OrderIdCard(orderId: widget.orderId),
          const SizedBox(height: AppSpacing.sm),

          // Card 5: Instructions + status
          InstructionsCard(
            text: _getInstructionText(),
            statusLabel: _status.label,
          ),
          const SizedBox(height: AppSpacing.xl),

          // Countdown
          if (_remaining > Duration.zero) ...[
            Center(
              child: Column(
                children: [
                  SizedBox(
                    width: 80,
                    height: 80,
                    child: CircularProgressIndicator(
                      value: (_remaining.inSeconds / _kCountdownSeconds)
                          .clamp(0.0, 1.0),
                      strokeWidth: 4,
                      color: _remaining.inMinutes < 5
                          ? colors?.destructiveRed ?? const Color(0xFFD84D4D)
                          : green,
                      backgroundColor:
                          colors?.backgroundInput ?? const Color(0xFF252A3A),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    'Time remaining: ${_formatDuration(_remaining)}',
                    style: TextStyle(color: textSec, fontSize: 13),
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.xl),
          ],

          // Action buttons (buyer flow — T060)
          if (_isBuyer && _status == TradeStatus.active) ...[
            MostroReactiveButton(
              label: 'FIAT SENT',
              backgroundColor: green,
              icon: Icons.send,
              onPressed: () async {
                // TODO: Call send_fiat_sent() via Rust bridge.
                await Future.delayed(const Duration(milliseconds: 500));
                if (mounted) {
                  setState(() => _status = TradeStatus.fiatSent);
                }
              },
              onError: (e) {
                if (!mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Failed to mark fiat sent: $e')),
                );
              },
            ),
            const SizedBox(height: AppSpacing.sm),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Coming soon')),
                      );
                    },
                    icon: const Icon(Icons.cancel_outlined, size: 16),
                    label: const Text('CANCEL'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor:
                          colors?.destructiveRed ?? const Color(0xFFD84D4D),
                      side: BorderSide(
                        color:
                            colors?.destructiveRed ?? const Color(0xFFD84D4D),
                      ),
                      minimumSize: const Size(0, 40),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(AppRadius.button),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Coming soon')),
                      );
                    },
                    icon: const Icon(Icons.gavel, size: 16),
                    label: const Text('DISPUTE'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor:
                          colors?.destructiveRed ?? const Color(0xFFD84D4D),
                      side: BorderSide(
                        color:
                            colors?.destructiveRed ?? const Color(0xFFD84D4D),
                      ),
                      minimumSize: const Size(0, 40),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(AppRadius.button),
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            FilledButton.icon(
              onPressed: () =>
                  context.push(AppRoute.chatRoomPath(widget.orderId)),
              icon: const Icon(Icons.chat_bubble_outline, size: 16),
              label: const Text('CONTACT'),
              style: FilledButton.styleFrom(
                backgroundColor: green,
                foregroundColor: Colors.black,
                minimumSize: const Size.fromHeight(40),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppRadius.button),
                ),
              ),
            ),
          ],

          // ── Seller: Active — CLOSE + CANCEL + DISPUTE + CONTACT ──
          if (!_isBuyer && _status == TradeStatus.active) ...[
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => context.pop(),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: green,
                      side: BorderSide(color: green),
                      minimumSize: const Size(0, 40),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(AppRadius.button),
                      ),
                    ),
                    child: const Text('CLOSE'),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Coming soon')),
                      );
                    },
                    icon: const Icon(Icons.cancel_outlined, size: 16),
                    label: const Text('CANCEL'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor:
                          colors?.destructiveRed ?? const Color(0xFFD84D4D),
                      side: BorderSide(
                        color:
                            colors?.destructiveRed ?? const Color(0xFFD84D4D),
                      ),
                      minimumSize: const Size(0, 40),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(AppRadius.button),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Coming soon')),
                      );
                    },
                    icon: const Icon(Icons.gavel, size: 16),
                    label: const Text('DISPUTE'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor:
                          colors?.destructiveRed ?? const Color(0xFFD84D4D),
                      side: BorderSide(
                        color:
                            colors?.destructiveRed ?? const Color(0xFFD84D4D),
                      ),
                      minimumSize: const Size(0, 40),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(AppRadius.button),
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            FilledButton.icon(
              onPressed: () =>
                  context.push(AppRoute.chatRoomPath(widget.orderId)),
              icon: const Icon(Icons.chat_bubble_outline, size: 16),
              label: const Text('CONTACT'),
              style: FilledButton.styleFrom(
                backgroundColor: green,
                foregroundColor: Colors.black,
                minimumSize: const Size.fromHeight(40),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppRadius.button),
                ),
              ),
            ),
          ],

          // ── Disputed — CLOSE + CONTACT + CANCEL + RELEASE + VIEW DISPUTE ──
          if (_status == TradeStatus.disputed) ...[
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => context.pop(),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: green,
                      side: BorderSide(color: green),
                      minimumSize: const Size(0, 40),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(AppRadius.button),
                      ),
                    ),
                    child: const Text('CLOSE'),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () =>
                        context.push(AppRoute.chatRoomPath(widget.orderId)),
                    icon: const Icon(Icons.chat_bubble_outline, size: 16),
                    label: const Text('CONTACT'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: green,
                      side: BorderSide(color: green),
                      minimumSize: const Size(0, 40),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(AppRadius.button),
                      ),
                    ),
                  ),
                ),
              ],
            ),
            // CANCEL + RELEASE only available to the seller during a dispute.
            if (!_isBuyer) ...[
            const SizedBox(height: AppSpacing.sm),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Coming soon')),
                      );
                    },
                    icon: const Icon(Icons.cancel_outlined, size: 16),
                    label: const Text('CANCEL'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor:
                          colors?.destructiveRed ?? const Color(0xFFD84D4D),
                      side: BorderSide(
                        color:
                            colors?.destructiveRed ?? const Color(0xFFD84D4D),
                      ),
                      minimumSize: const Size(0, 40),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(AppRadius.button),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: MostroReactiveButton(
                    label: 'RELEASE',
                    backgroundColor: green,
                    icon: Icons.lock_open,
                    onPressed: () async {
                      final confirmed =
                          await showReleaseConfirmationDialog(context);
                      if (confirmed != true || !context.mounted) return;
                      try {
                        await Future.delayed(
                          const Duration(milliseconds: 500),
                        );
                        if (context.mounted) {
                          context.push(
                            AppRoute.rateUserPath(widget.orderId),
                          );
                        }
                      } catch (e) {
                        if (!context.mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('Release failed: $e')),
                        );
                      }
                    },
                    onError: (e) {
                      if (!mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Release failed: $e')),
                      );
                    },
                  ),
                ),
              ],
            ),
            ], // end if (!_isBuyer)
            const SizedBox(height: AppSpacing.sm),
            FilledButton.icon(
              onPressed: () {
                final dispute = ref.read(
                  disputeByTradeIdProvider(widget.orderId),
                );
                if (dispute == null) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Dispute not found for this order.'),
                      duration: Duration(seconds: 2),
                    ),
                  );
                  return;
                }
                context.push(AppRoute.disputeDetailsPath(dispute.id));
              },
              icon: const Icon(Icons.gavel, size: 16),
              label: const Text('VIEW DISPUTE'),
              style: FilledButton.styleFrom(
                backgroundColor: colors?.destructiveRed ?? const Color(0xFFD84D4D),
                foregroundColor: Colors.white,
                minimumSize: const Size.fromHeight(40),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppRadius.button),
                ),
              ),
            ),
          ],

          // ── Seller: Fiat Sent — CLOSE + RELEASE + CANCEL + DISPUTE + CONTACT ──
          if (!_isBuyer && _status == TradeStatus.fiatSent) ...[
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => context.pop(),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: green,
                      side: BorderSide(color: green),
                      minimumSize: const Size(0, 40),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(AppRadius.button),
                      ),
                    ),
                    child: const Text('CLOSE'),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: MostroReactiveButton(
                    label: 'RELEASE',
                    backgroundColor: green,
                    icon: Icons.lock_open,
                    onPressed: () async {
                      final confirmed =
                          await showReleaseConfirmationDialog(context);
                      if (confirmed != true || !context.mounted) return;
                      try {
                        // TODO(bridge): Call release_order(widget.orderId)
                        // via Rust bridge once FFI bindings are generated.
                        // Currently the Rust function exists but the Dart
                        // bridge only exposes test helpers.
                        await Future.delayed(
                          const Duration(milliseconds: 500),
                        );
                        if (context.mounted) {
                          context.push(
                            AppRoute.rateUserPath(widget.orderId),
                          );
                        }
                      } catch (e) {
                        if (!context.mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('Release failed: $e')),
                        );
                      }
                    },
                    onError: (e) {
                      if (!mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Release failed: $e')),
                      );
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Coming soon')),
                      );
                    },
                    icon: const Icon(Icons.cancel_outlined, size: 16),
                    label: const Text('CANCEL'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor:
                          colors?.destructiveRed ?? const Color(0xFFD84D4D),
                      side: BorderSide(
                        color:
                            colors?.destructiveRed ?? const Color(0xFFD84D4D),
                      ),
                      minimumSize: const Size(0, 40),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(AppRadius.button),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Coming soon')),
                      );
                    },
                    icon: const Icon(Icons.gavel, size: 16),
                    label: const Text('DISPUTE'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor:
                          colors?.destructiveRed ?? const Color(0xFFD84D4D),
                      side: BorderSide(
                        color:
                            colors?.destructiveRed ?? const Color(0xFFD84D4D),
                      ),
                      minimumSize: const Size(0, 40),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(AppRadius.button),
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            FilledButton.icon(
              onPressed: () =>
                  context.push(AppRoute.chatRoomPath(widget.orderId)),
              icon: const Icon(Icons.chat_bubble_outline, size: 16),
              label: const Text('CONTACT'),
              style: FilledButton.styleFrom(
                backgroundColor: green,
                foregroundColor: Colors.black,
                minimumSize: const Size.fromHeight(40),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppRadius.button),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

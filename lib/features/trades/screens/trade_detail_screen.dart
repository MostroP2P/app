import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:mostro/core/app_routes.dart';
import 'package:mostro/core/app_theme.dart';
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

class _TradeDetailScreenState extends ConsumerState<TradeDetailScreen> {
  Timer? _countdownTimer;
  Duration _remaining = const Duration(minutes: 15);

  // Mock trade state — will be replaced by Rust bridge provider.
  String _status = 'Active';
  // ignore: prefer_final_fields — will be set from provider in Phase 9+
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
        _remaining -= const Duration(seconds: 1);
        if (_remaining.isNegative) {
          _countdownTimer?.cancel();
          _remaining = Duration.zero;
        }
      });
    });
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
            text: _isBuyer && _status == 'Active'
                ? 'Send the fiat payment to the seller, then tap "Fiat Sent".'
                : 'Waiting for the buyer to send fiat payment.',
            statusLabel: _status,
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
                      value: (_remaining.inSeconds / 900).clamp(0.0, 1.0),
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
          if (_isBuyer && _status == 'Active') ...[
            MostroReactiveButton(
              label: 'FIAT SENT',
              backgroundColor: green,
              icon: Icons.send,
              onPressed: () async {
                // TODO: Call send_fiat_sent() via Rust bridge.
                await Future.delayed(const Duration(milliseconds: 500));
                if (mounted) {
                  setState(() => _status = 'Fiat Sent');
                }
              },
            ),
            const SizedBox(height: AppSpacing.sm),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () {
                      // TODO: Wire cooperative cancel.
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
                      // TODO: Wire dispute action.
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

          // Fiat sent state — waiting for seller release
          if (_isBuyer && _status == 'Fiat Sent') ...[
            const InstructionsCard(
              text: 'Fiat payment marked as sent. Waiting for the seller '
                  'to confirm receipt and release your sats.',
              statusLabel: 'Fiat Sent',
            ),
          ],
        ],
      ),
    );
  }
}

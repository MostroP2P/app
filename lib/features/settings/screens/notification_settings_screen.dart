import 'package:flutter/material.dart';

import 'package:mostro/core/app_theme.dart';

/// Notification preferences screen.
///
/// Local state only — TODO(bridge): persist via settings API.
class NotificationSettingsScreen extends StatefulWidget {
  const NotificationSettingsScreen({super.key});

  @override
  State<NotificationSettingsScreen> createState() =>
      _NotificationSettingsScreenState();
}

class _NotificationSettingsScreenState
    extends State<NotificationSettingsScreen> {
  bool _tradeUpdates = true;
  bool _newMessages = true;
  bool _paymentAlerts = true;
  bool _disputeUpdates = true;

  @override
  Widget build(BuildContext context) {
    final colorsRaw = Theme.of(context).extension<AppColors>();
    if (colorsRaw == null) throw StateError('AppColors theme extension must be registered');
    final colors = colorsRaw;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Push Notifications'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.lg),
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.md),
            child: Text(
              'Choose which events trigger push notifications.',
              style: Theme.of(context)
                  .textTheme
                  .bodyMedium
                  ?.copyWith(color: colors.textSubtle),
            ),
          ),
          _buildSwitch(
            context,
            colors,
            icon: Icons.swap_horiz,
            title: 'Trade updates',
            subtitle: 'Status changes in your active trades',
            value: _tradeUpdates,
            onChanged: (v) => setState(() => _tradeUpdates = v),
          ),
          _buildSwitch(
            context,
            colors,
            icon: Icons.chat_bubble_outline,
            title: 'New messages',
            subtitle: 'Messages from your trade counterparty',
            value: _newMessages,
            onChanged: (v) => setState(() => _newMessages = v),
          ),
          _buildSwitch(
            context,
            colors,
            icon: Icons.bolt,
            title: 'Payment alerts',
            subtitle: 'Lightning payment confirmations and failures',
            value: _paymentAlerts,
            onChanged: (v) => setState(() => _paymentAlerts = v),
          ),
          _buildSwitch(
            context,
            colors,
            icon: Icons.gavel_outlined,
            title: 'Dispute updates',
            subtitle: 'Admin actions and dispute resolutions',
            value: _disputeUpdates,
            onChanged: (v) => setState(() => _disputeUpdates = v),
          ),
        ],
      ),
    );
  }

  Widget _buildSwitch(
    BuildContext context,
    AppColors colors, {
    required IconData icon,
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.md),
      decoration: BoxDecoration(
        color: colors.backgroundCard,
        borderRadius: BorderRadius.circular(AppRadius.card),
      ),
      child: SwitchListTile(
        contentPadding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.lg,
          vertical: AppSpacing.xs,
        ),
        secondary: Icon(icon, color: colors.mostroGreen, size: 22),
        title: Text(
          title,
          style: Theme.of(context)
              .textTheme
              .bodyLarge
              ?.copyWith(fontWeight: FontWeight.w600),
        ),
        subtitle: Text(
          subtitle,
          style: Theme.of(context).textTheme.bodySmall,
        ),
        value: value,
        onChanged: onChanged,
        activeThumbColor: colors.mostroGreen,
      ),
    );
  }
}

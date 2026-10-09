import 'package:flutter/material.dart';

import 'package:mostro/core/app_theme.dart';
import 'package:mostro/core/automation/automation_id.dart';
import 'package:mostro/core/automation/automation_ids.dart';
import 'package:mostro/core/order_detail_palette.dart';
import 'package:mostro/l10n/app_localizations.dart';
import 'package:mostro/shared/widgets/mostro_modal.dart';
import 'package:mostro/src/rust/api/types.dart' as rust_types;

/// The dispute chat's app bar action that sends the solver the peer chat key
/// (#415), so they can read what buyer and seller wrote to each other.
///
/// A key button that asks first ([showShareChatKeyDialog]). Once the current
/// solver has the key it turns lime and says so, and still sends it again:
/// the user may have sent it to a solver who handed the dispute over
/// (Serbero before a human), or just want it sent again.
class ShareChatKeyAction extends StatelessWidget {
  const ShareChatKeyAction({
    super.key,
    required this.shared,
    required this.onPressed,
  });

  /// Whether the current solver already has the key.
  final bool shared;

  final VoidCallback onPressed;

  static const double _target = 48;

  @override
  Widget build(BuildContext context) {
    final palette = OrderBookPalette.of(context);
    final l10n = AppLocalizations.of(context);

    return IconButton(
      onPressed: onPressed,
      tooltip: shared ? l10n.chatKeySharedIndicator : l10n.shareChatKeyAction,
      constraints: const BoxConstraints.tightFor(
        width: _target,
        height: _target,
      ),
      icon: Icon(
        Icons.key_rounded,
        size: 22,
        color: shared ? palette.limeIcon : palette.textPrimary,
      ),
    ).withAutomationId(AutomationIds.disputeShareKey);
  }
}

/// Asks before the chat key goes to the solver, and sends it on the answer.
///
/// The dialog stays open while [share] runs, its answer busy, and shows why
/// it failed in place, so the user can try again or leave. Resolves to the
/// message that carried the key, or `null` when nothing was sent.
Future<rust_types.ChatMessage?> showShareChatKeyDialog({
  required BuildContext context,
  required Future<rust_types.ChatMessage> Function() share,
}) {
  return showMostroDialog<rust_types.ChatMessage>(
    context: context,
    builder: (_) => ShareChatKeyDialog(share: share),
  );
}

/// The confirmation behind [ShareChatKeyAction]. Public for tests; open it
/// with [showShareChatKeyDialog].
class ShareChatKeyDialog extends StatefulWidget {
  const ShareChatKeyDialog({super.key, required this.share});

  final Future<rust_types.ChatMessage> Function() share;

  @override
  State<ShareChatKeyDialog> createState() => _ShareChatKeyDialogState();
}

class _ShareChatKeyDialogState extends State<ShareChatKeyDialog> {
  bool _sharing = false;
  String? _error;

  Future<void> _share() async {
    if (_sharing) return;
    final l10n = AppLocalizations.of(context);
    final navigator = Navigator.of(context);
    setState(() {
      _sharing = true;
      _error = null;
    });
    try {
      final sent = await widget.share();
      if (mounted) navigator.pop(sent);
    } catch (e) {
      debugPrint('[disputes] chat key share failed: $e');
      if (!mounted) return;
      setState(() {
        _sharing = false;
        _error = shareChatKeyErrorMessage(l10n, e);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final palette = OrderBookPalette.of(context);

    return MostroDialog(
      title: l10n.shareChatKeyTitle,
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            l10n.shareChatKeyBody,
            style: TextStyle(
              fontFamily: AppFonts.ui,
              fontSize: 14,
              height: 1.5,
              color: palette.textSecondary,
            ),
          ),
          if (_error case final error?) ...[
            const SizedBox(height: 12),
            Semantics(
              liveRegion: true,
              child: Text(
                error,
                style: TextStyle(
                  fontFamily: AppFonts.ui,
                  fontSize: 12,
                  // The modal's own red (`sell`) is one value for both
                  // themes and too light for text on the light surface.
                  color: OrderDetailPalette.of(context).danger,
                ),
              ),
            ),
          ],
        ],
      ),
      secondary: ModalAction(
        label: l10n.cancel,
        onPressed: _sharing ? null : () => Navigator.of(context).pop(),
        automationId: AutomationIds.disputeShareKeyCancel,
      ),
      primary: ModalAction(
        label: l10n.shareChatKeyConfirm,
        // It cannot be taken back (DS-CMP-2).
        tone: ModalTone.destructive,
        onPressed: _share,
        busy: _sharing,
        automationId: AutomationIds.disputeShareKeyConfirm,
      ),
    );
  }
}

/// Why the chat key did not go to the solver, localized from the marker
/// `share_chat_key_with_solver` fails with (CLAUDE.md, *Translations*).
String shareChatKeyErrorMessage(AppLocalizations l10n, Object error) {
  final raw = error.toString();
  if (raw.contains('AdminNotAssigned')) return l10n.disputeSolverNotAssigned;
  if (raw.contains('NoOpenDispute')) return l10n.disputeChatClosed;
  if (raw.contains('NoSharedKey') || raw.contains('TradeNotFound')) {
    return l10n.shareChatKeyUnavailable;
  }
  return l10n.messageSendFailed;
}

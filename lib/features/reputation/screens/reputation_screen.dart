import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:mostro/core/app_routes.dart';
import 'package:mostro/core/automation/automation_id.dart';
import 'package:mostro/core/automation/automation_ids.dart';
import 'package:mostro/core/order_book_palette.dart';
import 'package:mostro/features/account/providers/privacy_mode_provider.dart';
import 'package:mostro/features/reputation/npub.dart';
import 'package:mostro/features/reputation/reputation_api.dart';
import 'package:mostro/features/reputation/reputation_errors.dart';
import 'package:mostro/l10n/app_localizations.dart';
import 'package:mostro/shared/widgets/mostro_modal.dart';
import 'package:mostro/shared/widgets/redesign_app_bar.dart';

/// Reputation (#674): export what the user earned on the active node, import
/// what they earned elsewhere, and authorise moving an exported reputation to
/// a new identity.
class ReputationScreen extends ConsumerStatefulWidget {
  const ReputationScreen({super.key});

  @override
  ConsumerState<ReputationScreen> createState() => _ReputationScreenState();
}

class _ReputationScreenState extends ConsumerState<ReputationScreen> {
  final _newIdentity = TextEditingController();
  String? _exported;
  String? _rebind;
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    _newIdentity.dispose();
    super.dispose();
  }

  Future<void> _export() async {
    final l10n = AppLocalizations.of(context);
    final api = ref.read(reputationApiProvider);
    final identity = await api.identity();
    if (identity == null || !mounted) return;
    // The request binds the node's account to the identity: confirm it.
    final confirmed = await showMostroDialog<bool>(
      context: context,
      builder:
          (context) => MostroDialog(
            title: l10n.reputationExportConfirmTitle,
            content: SelectableText(
              l10n.reputationExportConfirmBody(hexToNpub(identity) ?? identity),
            ),
            secondary: ModalAction(
              label: l10n.cancel,
              onPressed: () => Navigator.of(context).pop(false),
            ),
            primary: ModalAction(
              label: l10n.reputationExportConfirmButton,
              onPressed: () => Navigator.of(context).pop(true),
              automationId: AutomationIds.reputationExportConfirm,
            ),
          ),
    );
    if (confirmed != true || !mounted) return;
    setState(() {
      _busy = true;
      _error = null;
      _exported = null;
    });
    try {
      final attestation = await api.export();
      if (mounted) setState(() => _exported = attestation.json);
    } catch (e) {
      if (mounted) setState(() => _error = localizedReputationError(l10n, e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _signRebind(String issuer) async {
    final l10n = AppLocalizations.of(context);
    final input = _newIdentity.text.trim();
    setState(() {
      _error = null;
      _rebind = null;
    });
    if (input.isEmpty) {
      setState(() => _error = l10n.reputationInvalidIdentity);
      return;
    }
    try {
      final rebind = await ref
          .read(reputationApiProvider)
          .signRebind(issuer: issuer, newIdentity: input);
      if (mounted) setState(() => _rebind = rebind);
    } catch (e) {
      if (mounted) {
        setState(
          () =>
              _error = localizedReputationError(
                l10n,
                e,
                fallback: l10n.reputationInvalidIdentity,
              ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final book = OrderBookPalette.of(context);
    final support = ref.read(reputationApiProvider).support();
    final privacy = ref.watch(privacyModeProvider);
    final body = TextStyle(color: book.textMuted, fontSize: 13);
    final issuer = support.issuer;
    return Scaffold(
      backgroundColor: book.bg,
      appBar: redesignAppBar(
        context,
        title: l10n.reputationSettingTitle,
        onBack:
            () =>
                context.canPop()
                    ? context.pop()
                    : context.go(AppRoute.settings),
      ),
      body: ListView(
        padding: EdgeInsets.fromLTRB(
          redesignSidePadding,
          6,
          redesignSidePadding,
          14 + MediaQuery.of(context).viewPadding.bottom,
        ),
        children: [
          if (privacy)
            _Card(child: Text(l10n.reputationIdentityRequired, style: body)),
          _Card(
            title: l10n.reputationImportTitle,
            children: [
              Text(l10n.reputationImportCardBody, style: body),
              const SizedBox(height: 10),
              FilledButton(
                onPressed:
                    privacy
                        ? null
                        : () => context.push(AppRoute.importReputation),
                child: Text(l10n.reputationImportTitle),
              ).withAutomationId(AutomationIds.reputationOpenImport),
            ],
          ),
          _Card(
            title: l10n.reputationExportTitle,
            children:
                issuer == null
                    ? [Text(l10n.reputationNodeDoesNotExport, style: body)]
                    : [
                      Text(l10n.reputationExportCardBody, style: body),
                      const SizedBox(height: 10),
                      FilledButton(
                        onPressed: privacy || _busy ? null : _export,
                        child: Text(l10n.reputationExportTitle),
                      ).withAutomationId(AutomationIds.reputationExport),
                      if (_exported != null) ...[
                        const SizedBox(height: 10),
                        Text(l10n.reputationExported, style: body),
                        _Copyable(
                          text: _exported!,
                        ).withAutomationId(AutomationIds.reputationExported),
                      ],
                      const SizedBox(height: 16),
                      Text(l10n.reputationRebindBody, style: body),
                      TextField(
                        controller: _newIdentity,
                        style: TextStyle(color: book.textPrimary),
                        decoration: InputDecoration(
                          hintText: l10n.reputationNewIdentityHint,
                        ),
                      ).withAutomationId(
                        AutomationIds.reputationRebindIdentity,
                      ),
                      const SizedBox(height: 8),
                      OutlinedButton(
                        onPressed: privacy ? null : () => _signRebind(issuer),
                        child: Text(l10n.reputationRebindSign),
                      ).withAutomationId(AutomationIds.reputationRebindSign),
                      if (_rebind != null) _Copyable(text: _rebind!),
                    ],
          ),
          if (_error != null) Text(_error!, style: TextStyle(color: book.sell)),
        ],
      ),
    );
  }
}

class _Card extends StatelessWidget {
  final String? title;
  final Widget? child;
  final List<Widget> children;

  const _Card({this.title, this.child, this.children = const []});

  @override
  Widget build(BuildContext context) {
    final book = OrderBookPalette.of(context);
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: book.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: book.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (title != null) ...[
            Text(
              title!,
              style: TextStyle(
                color: book.textPrimary,
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
          ],
          if (child != null) child!,
          ...children,
        ],
      ),
    );
  }
}

/// A long value the user copies whole into another app.
class _Copyable extends StatelessWidget {
  final String text;

  const _Copyable({required this.text});

  @override
  Widget build(BuildContext context) {
    final book = OrderBookPalette.of(context);
    return Row(
      children: [
        Expanded(
          child: Text(
            text,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: book.textPrimary, fontSize: 11),
          ),
        ),
        IconButton(
          icon: Icon(Icons.copy, color: book.textMuted),
          onPressed: () => Clipboard.setData(ClipboardData(text: text)),
        ),
      ],
    );
  }
}

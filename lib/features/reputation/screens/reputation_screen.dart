import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:mostro/core/app_routes.dart';
import 'package:mostro/core/automation/automation_id.dart';
import 'package:mostro/core/automation/automation_ids.dart';
import 'package:mostro/core/order_book_palette.dart';
import 'package:mostro/core/settings_palette.dart';
import 'package:mostro/features/account/providers/privacy_mode_provider.dart';
import 'package:mostro/features/reputation/reputation_api.dart';
import 'package:mostro/features/reputation/reputation_errors.dart';
import 'package:mostro/features/reputation/widgets/reputation_controls.dart';
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
  /// How often the node's capabilities are read again. On a cold start the
  /// Kind 38385 fetch can finish after this screen opened, and nothing else
  /// rebuilds it when the issuer key arrives.
  static const _supportRefresh = Duration(seconds: 2);

  final _rebindInput = TextEditingController();
  final _newIdentity = TextEditingController();
  Timer? _supportTimer;
  String? _issuer;
  String? _exported;
  String? _rebind;
  String? _error;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _issuer = ref.read(reputationApiProvider).support().issuer;
    _supportTimer = Timer.periodic(_supportRefresh, (_) => _refreshSupport());
  }

  @override
  void dispose() {
    _supportTimer?.cancel();
    _rebindInput.dispose();
    _newIdentity.dispose();
    super.dispose();
  }

  void _refreshSupport() {
    final issuer = ref.read(reputationApiProvider).support().issuer;
    if (mounted && issuer != _issuer) setState(() => _issuer = issuer);
  }

  /// [identity] as an npub for the user to read, or the value itself when it
  /// cannot be encoded.
  String _npubOf(String identity) {
    try {
      return ref.read(reputationApiProvider).npub(identity);
    } catch (_) {
      return identity;
    }
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
              l10n.reputationExportConfirmBody(_npubOf(identity)),
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
    final rebind = _rebindInput.text.trim();
    setState(() {
      _busy = true;
      _error = null;
      _exported = null;
    });
    try {
      final attestation = await api.export(
        rebind: rebind.isEmpty ? null : rebind,
      );
      if (mounted) setState(() => _exported = attestation.json);
    } catch (e) {
      // The user is on the source and pasted nothing: a failure without a
      // message of its own must not read as an invalid paste (#882).
      if (mounted) {
        setState(
          () =>
              _error = localizedReputationError(
                l10n,
                e,
                fallback: l10n.reputationExportFailed,
              ),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _signRebind(String issuer) async {
    final l10n = AppLocalizations.of(context);
    final api = ref.read(reputationApiProvider);
    setState(() {
      _error = null;
      _rebind = null;
    });
    final String npub;
    try {
      npub = api.npub(_newIdentity.text.trim());
    } catch (_) {
      setState(() => _error = l10n.reputationInvalidIdentity);
      return;
    }
    // Whoever holds that key takes the reputation over: confirm it.
    final confirmed = await showMostroDialog<bool>(
      context: context,
      builder:
          (context) => MostroDialog(
            title: l10n.reputationRebindConfirmTitle,
            content: SelectableText(l10n.reputationRebindConfirmBody(npub)),
            secondary: ModalAction(
              label: l10n.cancel,
              onPressed: () => Navigator.of(context).pop(false),
            ),
            primary: ModalAction(
              label: l10n.reputationRebindSign,
              onPressed: () => Navigator.of(context).pop(true),
              automationId: AutomationIds.reputationRebindConfirm,
            ),
          ),
    );
    if (confirmed != true || !mounted) return;
    try {
      final rebind = await api.signRebind(issuer: issuer, newIdentity: npub);
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
    final privacy = ref.watch(privacyModeProvider);
    final body = TextStyle(color: book.textMuted, fontSize: 13);
    final issuer = _issuer;
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
              ReputationSecondaryButton(
                label: l10n.reputationImportTitle,
                onPressed:
                    privacy
                        ? null
                        : () => context.push(AppRoute.importReputation),
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
                      _Field(
                        controller: _rebindInput,
                        hint: l10n.reputationRebindInputHint,
                      ).withAutomationId(AutomationIds.reputationRebindInput),
                      const SizedBox(height: 10),
                      ReputationPrimaryButton(
                        label: l10n.reputationExportTitle,
                        onPressed: privacy || _busy ? null : _export,
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
                      _Field(
                        controller: _newIdentity,
                        hint: l10n.reputationNewIdentityHint,
                      ).withAutomationId(
                        AutomationIds.reputationRebindIdentity,
                      ),
                      const SizedBox(height: 8),
                      ReputationSecondaryButton(
                        label: l10n.reputationRebindSign,
                        onPressed: privacy ? null : () => _signRebind(issuer),
                      ).withAutomationId(AutomationIds.reputationRebindSign),
                      if (_rebind != null)
                        _Copyable(text: _rebind!).withAutomationId(
                          AutomationIds.reputationRebindResult,
                        ),
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
                fontSize: 15,
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

/// A one-line text field underlined as in Settings.
class _Field extends StatelessWidget {
  final TextEditingController controller;
  final String hint;

  const _Field({required this.controller, required this.hint});

  @override
  Widget build(BuildContext context) {
    final book = OrderBookPalette.of(context);
    final settings = SettingsPalette.of(context);
    return TextField(
      controller: controller,
      style: TextStyle(color: book.textPrimary),
      decoration: InputDecoration(
        isDense: true,
        hintText: hint,
        hintStyle: TextStyle(color: settings.placeholder),
        filled: false,
        contentPadding: const EdgeInsets.only(top: 6, bottom: 8),
        enabledBorder: UnderlineInputBorder(
          borderSide: BorderSide(color: settings.fieldUnderline),
        ),
        focusedBorder: UnderlineInputBorder(
          borderSide: BorderSide(
            color: settings.fieldUnderlineFocus,
            width: 1.5,
          ),
        ),
      ),
    );
  }
}

/// A long value the user copies whole into another app. It can also be
/// selected, and copying says so.
class _Copyable extends StatelessWidget {
  final String text;

  const _Copyable({required this.text});

  Future<void> _copy(BuildContext context) async {
    final copied = AppLocalizations.of(context).messageCopied;
    final messenger = ScaffoldMessenger.of(context);
    await Clipboard.setData(ClipboardData(text: text));
    messenger.showSnackBar(SnackBar(content: Text(copied)));
  }

  @override
  Widget build(BuildContext context) {
    final book = OrderBookPalette.of(context);
    return Row(
      children: [
        Expanded(
          child: SelectableText(
            text,
            maxLines: 3,
            style: TextStyle(color: book.textPrimary, fontSize: 11),
          ),
        ),
        IconButton(
          tooltip: AppLocalizations.of(context).copyButtonLabel,
          icon: Icon(Icons.copy, color: book.textMuted),
          onPressed: () => _copy(context),
        ),
      ],
    );
  }
}

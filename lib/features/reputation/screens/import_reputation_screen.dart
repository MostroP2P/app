import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:mostro/core/app_routes.dart';
import 'package:mostro/core/automation/automation_id.dart';
import 'package:mostro/core/automation/automation_ids.dart';
import 'package:mostro/core/order_book_palette.dart';
import 'package:mostro/core/settings_palette.dart';
import 'package:mostro/features/reputation/lnp2pbot.dart';
import 'package:mostro/features/reputation/reputation_api.dart';
import 'package:mostro/features/reputation/reputation_errors.dart';
import 'package:mostro/features/reputation/widgets/reputation_controls.dart';
import 'package:mostro/l10n/app_localizations.dart';
import 'package:mostro/shared/utils/platform_int64.dart';
import 'package:mostro/shared/widgets/redesign_app_bar.dart';
import 'package:mostro/src/rust/api/reputation_transfer.dart';

/// Import reputation earned elsewhere: get an attestation from lnp2pBot on
/// Telegram, or exported from another Mostro, check its figures, and import
/// it into the active node (#674).
class ImportReputationScreen extends ConsumerStatefulWidget {
  const ImportReputationScreen({super.key});

  @override
  ConsumerState<ImportReputationScreen> createState() =>
      _ImportReputationScreenState();
}

class _ImportReputationScreenState
    extends ConsumerState<ImportReputationScreen> {
  final _input = TextEditingController();
  ReputationAttestationInfo? _attestation;
  String? _error;
  bool _busy = false;
  bool _imported = false;

  @override
  void initState() {
    super.initState();
    // An attestation exported from another Mostro waits to be imported.
    ref.read(reputationApiProvider).pending().then((pending) {
      if (!mounted || pending == null || _input.text.isNotEmpty) return;
      _input.text = pending.json;
      _check();
    }, onError: (_) {});
  }

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  void _check() {
    final l10n = AppLocalizations.of(context);
    final json = extractAttestationJson(_input.text);
    setState(() {
      _attestation = null;
      _imported = false;
      _error = null;
      if (json == null) {
        _error = l10n.reputationInvalidAttestation;
        return;
      }
      try {
        _attestation = ref.read(reputationApiProvider).parse(json);
      } catch (e) {
        _error = localizedReputationError(l10n, e);
      }
    });
  }

  Future<void> _import() async {
    final attestation = _attestation;
    if (attestation == null) return;
    final l10n = AppLocalizations.of(context);
    setState(() => _busy = true);
    try {
      await ref.read(reputationApiProvider).import(attestation.json);
      if (mounted) setState(() => _imported = true);
    } catch (e) {
      if (mounted) setState(() => _error = localizedReputationError(l10n, e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _openBot() async {
    final identity = await ref.read(reputationApiProvider).identity();
    final uri = identity == null ? null : lnp2pbotExportUri(identity);
    if (uri == null) return;
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      // No app for the link: the user can still paste what they received.
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final book = OrderBookPalette.of(context);
    final attestation = _attestation;
    final settings = SettingsPalette.of(context);
    return Scaffold(
      backgroundColor: book.bg,
      appBar: redesignAppBar(
        context,
        title: l10n.reputationImportTitle,
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
          Text(
            l10n.reputationImportIntro,
            style: TextStyle(color: book.textMuted, fontSize: 13),
          ),
          const SizedBox(height: 14),
          ReputationSecondaryButton(
            icon: Icons.send_outlined,
            label: l10n.reputationOpenLnp2pbot,
            onPressed: _openBot,
          ).withAutomationId(AutomationIds.reputationImportOpenBot),
          const SizedBox(height: 14),
          TextField(
            controller: _input,
            minLines: 3,
            maxLines: 6,
            style: TextStyle(color: book.textPrimary, fontSize: 12),
            decoration: InputDecoration(
              hintText: l10n.reputationPasteHint,
              hintStyle: TextStyle(color: settings.placeholder, fontSize: 12),
              filled: false,
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: settings.fieldUnderline),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(
                  color: settings.fieldUnderlineFocus,
                  width: 1.5,
                ),
              ),
            ),
          ).withAutomationId(AutomationIds.reputationImportInput),
          const SizedBox(height: 8),
          ReputationPrimaryButton(
            label: l10n.reputationCheck,
            onPressed: _busy ? null : _check,
          ).withAutomationId(AutomationIds.reputationImportCheck),
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(_error!, style: TextStyle(color: book.sell)),
          ],
          if (attestation != null) ...[
            const SizedBox(height: 14),
            _Figures(
              attestation: attestation,
            ).withAutomationId(AutomationIds.reputationImportFigures),
            const SizedBox(height: 14),
            if (_imported)
              Text(
                l10n.reputationImported,
                style: TextStyle(color: book.limeText),
              )
            else
              ReputationPrimaryButton(
                label: l10n.reputationImportConfirm,
                onPressed: _busy ? null : _import,
              ).withAutomationId(AutomationIds.reputationImportConfirm),
          ],
        ],
      ),
    );
  }
}

class _Figures extends StatelessWidget {
  final ReputationAttestationInfo attestation;

  const _Figures({required this.attestation});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final book = OrderBookPalette.of(context);
    final since = DateTime.fromMillisecondsSinceEpoch(
      platformInt64ToInt(attestation.since) * 1000,
      isUtc: true,
    );
    final days = DateTime.now().toUtc().difference(since).inDays;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: book.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: book.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l10n.reputationFigures(
              attestation.reviews,
              attestation.rating,
              days < 0 ? 0 : days,
            ),
            style: TextStyle(color: book.textPrimary, fontSize: 15),
          ),
          const SizedBox(height: 6),
          Text(
            l10n.reputationFiguresNote,
            style: TextStyle(color: book.textMuted, fontSize: 12),
          ),
        ],
      ),
    );
  }
}

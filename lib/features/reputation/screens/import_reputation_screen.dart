import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import 'package:mostro/core/app_routes.dart';
import 'package:mostro/core/automation/automation_id.dart';
import 'package:mostro/core/automation/automation_ids.dart';
import 'package:mostro/core/order_book_palette.dart';
import 'package:mostro/core/settings_palette.dart';
import 'package:mostro/core/trade_palette.dart';
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

  /// The node does not advertise `reputation_import_issuers`.
  late final bool _unsupported;

  /// Full privacy mode: no identity key to import into, nor to send the bot.
  bool _privacy = false;

  /// What Check last answered for [_checkedText]: the attestation, or why it
  /// was refused. Both are withdrawn as soon as the text changes, so Import
  /// only ever sends the attestation that is in the field.
  ReputationAttestationInfo? _attestation;
  String? _error;
  String? _checkedText;

  String? _botError;
  bool _busy = false;
  bool _imported = false;

  bool get _blocked => _unsupported || _privacy;

  @override
  void initState() {
    super.initState();
    _unsupported =
        ref.read(reputationApiProvider).support().importIssuers == null;
    _input.addListener(_onTextChanged);
    _load();
  }

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final api = ref.read(reputationApiProvider);
    final privacy = await api.privacyMode().catchError((_) => false);
    if (!mounted) return;
    setState(() => _privacy = privacy);
    if (_blocked) return;
    // An attestation exported from another Mostro waits to be imported.
    final pending = await api.pending().catchError(
      (_) => null as ReputationAttestationInfo?,
    );
    if (!mounted || pending == null || _input.text.isNotEmpty) return;
    _input.text = pending.json;
    await _check();
  }

  void _onTextChanged() {
    if (_checkedText == null || _input.text == _checkedText) return;
    setState(() {
      _attestation = null;
      _error = null;
      _imported = false;
      _checkedText = null;
    });
  }

  Future<void> _check() async {
    final l10n = AppLocalizations.of(context);
    final text = _input.text;
    final json = extractAttestationJson(text);
    setState(() {
      _attestation = null;
      _imported = false;
      _error = json == null ? l10n.reputationInvalidAttestation : null;
      _checkedText = json == null ? text : null;
      _busy = json != null;
    });
    if (json == null) return;
    ReputationAttestationInfo? info;
    String? error;
    try {
      info = await ref.read(reputationApiProvider).check(json);
    } catch (e) {
      error = localizedReputationError(l10n, e);
    }
    if (!mounted) return;
    setState(() {
      _busy = false;
      // The text changed while the core checked it: the answer is stale.
      if (_input.text != text) return;
      _attestation = info;
      _error = error;
      _checkedText = text;
    });
  }

  Future<void> _import() async {
    final attestation = _attestation;
    if (attestation == null || _input.text != _checkedText) return;
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
    if (_blocked) return;
    final l10n = AppLocalizations.of(context);
    final api = ref.read(reputationApiProvider);
    setState(() => _botError = null);
    final identity = await api.identity().catchError((_) => null);
    final uri = identity == null ? null : lnp2pbotExportUri(identity);
    final opened = uri != null && await api.openExternal(uri);
    if (!opened && mounted) {
      // The user can still open the bot by hand and paste what it sends.
      setState(() => _botError = l10n.reputationOpenLnp2pbotFailed);
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
          if (_blocked) ...[
            const SizedBox(height: 14),
            _Notice(
              _unsupported
                  ? l10n.reputationNodeDoesNotImport
                  : l10n.reputationIdentityRequired,
            ),
          ],
          const SizedBox(height: 14),
          ReputationSecondaryButton(
            icon: Icons.send_outlined,
            label: l10n.reputationOpenLnp2pbot,
            onPressed: _blocked || _busy ? null : _openBot,
          ).withAutomationId(AutomationIds.reputationImportOpenBot),
          if (_botError != null) ...[
            const SizedBox(height: 8),
            Text(_botError!, style: TextStyle(color: book.sell, fontSize: 12)),
          ],
          const SizedBox(height: 14),
          TextField(
            controller: _input,
            enabled: !_blocked,
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
              disabledBorder: OutlineInputBorder(
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
            onPressed: _blocked || _busy ? null : _check,
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

/// Why the screen cannot import here, said before the user goes to the bot.
class _Notice extends StatelessWidget {
  final String text;

  const _Notice(this.text);

  @override
  Widget build(BuildContext context) {
    final trade = TradePalette.of(context);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: trade.warnBg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: trade.warnBorder),
      ),
      child: Text(text, style: TextStyle(color: trade.warnInk, fontSize: 13)),
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
    final locale = Localizations.localeOf(context).toString();
    final since = DateTime.fromMillisecondsSinceEpoch(
      platformInt64ToInt(attestation.since) * 1000,
      isUtc: true,
    );
    final days = DateTime.now().toUtc().difference(since).inDays;
    // The core sends the average as text with two decimals ("4.87"); shown
    // like the order book's ratings, for the locale (DS-L10N-3).
    final average = double.tryParse(attestation.rating);
    final rating =
        average == null
            ? attestation.rating
            : NumberFormat('0.##', locale).format(average);
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
              rating,
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

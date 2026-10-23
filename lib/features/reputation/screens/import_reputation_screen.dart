import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:mostro/core/app_routes.dart';
import 'package:mostro/core/app_theme.dart' show AppFonts;
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
import 'package:mostro/shared/utils/rating_format.dart';
import 'package:mostro/shared/utils/reputation_age.dart';
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

  /// How often the node's capabilities are read again. On a cold start the
  /// Kind 38385 fetch can finish after this screen opened, and nothing else
  /// rebuilds it when the trust list arrives (#883).
  static const _supportRefresh = Duration(seconds: 2);
  Timer? _supportTimer;

  /// The node does not advertise `reputation_import_issuers`.
  bool _unsupported = false;

  /// Full privacy mode: no identity key to import into, nor to send the bot.
  bool _privacy = true;
  bool _loading = true;
  String? _loadError;
  String? _identity;
  String? _npub;

  /// What Check last answered for [_checkedText]: the attestation, or why it
  /// was refused. Both are withdrawn as soon as the text changes, so Import
  /// only ever sends the attestation that is in the field.
  ReputationAttestationInfo? _attestation;
  String? _error;
  String? _checkedText;

  String? _botError;
  bool _busy = false;

  /// [_load] is reading the pending attestation and checking it.
  bool _prefilling = false;
  bool _imported = false;
  bool _importing = false;

  bool get _blocked =>
      _loading ||
      _loadError != null ||
      _unsupported ||
      _privacy ||
      _identity == null;

  @override
  void initState() {
    super.initState();
    _input.addListener(_onTextChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _load();
    });
    _supportTimer = Timer.periodic(_supportRefresh, (_) => _refreshSupport());
  }

  @override
  void dispose() {
    _supportTimer?.cancel();
    _input.dispose();
    super.dispose();
  }

  /// Reload when the node's capability changed since [_load] read it, in
  /// either direction: a fetch that retracts the trust list blocks the
  /// actions as the first read would have.
  void _refreshSupport() {
    if (!mounted || _loading || _prefilling || _busy) return;
    final unsupported =
        ref.read(reputationApiProvider).support().importIssuers == null;
    if (unsupported != _unsupported) _load();
  }

  Future<void> _load() async {
    if (_busy) return;
    final api = ref.read(reputationApiProvider);
    final l10n = AppLocalizations.of(context);
    setState(() {
      _loading = true;
      _loadError = null;
      _botError = null;
      _attestation = null;
      _checkedText = null;
      _error = null;
      _imported = false;
    });
    try {
      final privacy = await api.privacyMode();
      if (!mounted) return;
      final unsupported = api.support().importIssuers == null;
      final identity = privacy || unsupported ? null : await api.identity();
      if (!mounted) return;
      if (!privacy && !unsupported && identity == null) {
        throw StateError('NoIdentity');
      }
      final npub = identity == null ? null : api.npub(identity);
      setState(() {
        _privacy = privacy;
        _unsupported = unsupported;
        _identity = identity;
        _npub = npub;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _identity = null;
        _npub = null;
        _loadError = localizedReputationError(
          l10n,
          e,
          fallback: l10n.reputationUnavailable,
        );
      });
    } finally {
      if (mounted) setState(() => _loading = false);
    }
    if (!mounted || _blocked) return;
    // An attestation exported from another Mostro waits to be imported. The
    // read and its check still belong to this load: a capability change
    // meanwhile waits for the next tick, instead of starting a load that
    // would leave the prefilled attestation unchecked.
    _prefilling = true;
    try {
      final pending = await api.pending().catchError(
        (_) => null as ReputationAttestationInfo?,
      );
      if (!mounted || pending == null || _input.text.isNotEmpty) return;
      _input.text = pending.json;
      await _check();
    } finally {
      _prefilling = false;
    }
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
    if (_blocked || _busy) return;
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
    if (_blocked ||
        _busy ||
        attestation == null ||
        _input.text != _checkedText) {
      return;
    }
    final l10n = AppLocalizations.of(context);
    setState(() {
      _busy = true;
      _importing = true;
      _error = null;
    });
    try {
      await ref.read(reputationApiProvider).import(attestation.json);
      if (mounted) setState(() => _imported = true);
    } catch (e) {
      if (mounted) setState(() => _error = localizedReputationError(l10n, e));
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _importing = false;
        });
      }
    }
  }

  Future<void> _openBot() async {
    if (_blocked || _busy) return;
    final l10n = AppLocalizations.of(context);
    final api = ref.read(reputationApiProvider);
    setState(() {
      _botError = null;
      _busy = true;
    });
    try {
      final identity = await api.identity();
      // Recheck at the handoff, including changes since this screen loaded.
      final privacy = await api.privacyMode();
      if (!mounted || ModalRoute.of(context)?.isCurrent == false) return;
      final unsupported = api.support().importIssuers == null;
      setState(() {
        _privacy = privacy;
        _unsupported = unsupported;
      });
      if (privacy || unsupported) return;
      if (identity == null) throw StateError('NoIdentity');
      if (identity != _identity) {
        final npub = api.npub(identity);
        setState(() {
          _identity = identity;
          _npub = npub;
          _attestation = null;
          _checkedText = null;
          _error = null;
          _imported = false;
          _botError = l10n.reputationIdentityChanged;
        });
        return;
      }
      final uri = lnp2pbotExportUri(identity);
      final opened = uri != null && await api.openExternal(uri);
      if (!opened && mounted) {
        setState(() => _botError = l10n.reputationOpenLnp2pbotFailed);
      }
    } catch (e) {
      if (mounted) {
        setState(
          () =>
              _botError = localizedReputationError(
                l10n,
                e,
                fallback: l10n.reputationOpenLnp2pbotFailed,
              ),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
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
          if (_loading) ...[
            const SizedBox(height: 14),
            Text(l10n.loading, style: TextStyle(color: book.textMuted)),
          ] else if (_blocked) ...[
            const SizedBox(height: 14),
            _Notice(
              _loadError ??
                  (_unsupported
                      ? l10n.reputationNodeDoesNotImport
                      : l10n.reputationIdentityRequired),
            ),
          ],
          if (!_loading && _blocked) ...[
            const SizedBox(height: 8),
            ReputationSecondaryButton(
              label: l10n.retry,
              onPressed: _busy ? null : _load,
            ),
          ],
          if (!_blocked && _npub != null) ...[
            const SizedBox(height: 14),
            Text(
              l10n.reputationIdentityHint,
              style: TextStyle(color: book.textMuted, fontSize: 13),
            ),
            const SizedBox(height: 8),
            SelectableText(
              _npub!,
              textDirection: TextDirection.ltr,
              style: TextStyle(
                color: book.textPrimary,
                fontFamily: 'monospace',
                fontSize: 12,
              ),
            ).withAutomationId(AutomationIds.reputationImportIdentity),
          ],
          const SizedBox(height: 14),
          ReputationSecondaryButton(
            icon: Icons.send_outlined,
            label: l10n.reputationOpenLnp2pbot,
            onPressed: _blocked || _busy ? null : _openBot,
          ).withAutomationId(AutomationIds.reputationImportOpenBot),
          if (_botError != null) ...[
            const SizedBox(height: 8),
            Semantics(
              liveRegion: true,
              child: Text(
                _botError!,
                style: TextStyle(color: book.sell, fontSize: 12),
              ),
            ),
          ],
          const SizedBox(height: 14),
          TextField(
            controller: _input,
            enabled: !_blocked && !_importing,
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
            Semantics(
              liveRegion: true,
              child: Text(_error!, style: TextStyle(color: book.sell)),
            ),
          ],
          if (attestation != null) ...[
            const SizedBox(height: 14),
            Semantics(
              liveRegion: true,
              child: _Figures(attestation: attestation),
            ).withAutomationId(AutomationIds.reputationImportFigures),
            const SizedBox(height: 14),
            if (_imported)
              Semantics(
                liveRegion: true,
                child: Text(
                  l10n.reputationImported,
                  style: TextStyle(color: book.limeText),
                ),
              )
            else
              ReputationPrimaryButton(
                label: l10n.reputationImportConfirm,
                onPressed: _blocked || _busy ? null : _import,
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
      child: Semantics(
        liveRegion: true,
        child: Text(text, style: TextStyle(color: trade.warnInk, fontSize: 13)),
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
    final locale = Localizations.localeOf(context).toString();
    final since = DateTime.fromMillisecondsSinceEpoch(
      platformInt64ToInt(attestation.since) * 1000,
      isUtc: true,
    );
    // The core sends the average as text with two decimals ("4.87"); shown
    // like every other rating, for the locale (DS-L10N-5).
    final average = double.tryParse(attestation.rating);
    final rating =
        average == null ? attestation.rating : formatRating(average, locale);
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
          // The same three figures as every reputation (DS-L10N-5).
          Text(
            '★ $rating · ${l10n.reputationRatingsCount(attestation.reviews)}'
            ' · ${reputationSinceText(l10n, since)}',
            style: TextStyle(
              color: book.textPrimary,
              fontSize: 15,
              fontFamily: AppFonts.figures,
              fontWeight: FontWeight.w500,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
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

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
import 'package:mostro/src/rust/api/types.dart';

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

  /// Who signed [_attestation], as the card names it (#881); withdrawn with
  /// it.
  _Source? _source;

  String? _botError;
  bool _busy = false;
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
  }

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
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
      _source = null;
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
      _source = null;
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
      _source = null;
      _imported = false;
      _error = json == null ? l10n.reputationInvalidAttestation : null;
      _checkedText = json == null ? text : null;
      _busy = json != null;
    });
    if (json == null) return;
    final api = ref.read(reputationApiProvider);
    ReputationAttestationInfo? info;
    _Source? source;
    String? error;
    try {
      info = await api.check(json);
      source = await _resolveSource(api, info.issuer);
    } catch (e) {
      error = localizedReputationError(l10n, e);
    }
    if (!mounted) return;
    setState(() {
      _busy = false;
      // The text changed while the core checked it: the answer is stale.
      if (_input.text != text) return;
      _attestation = info;
      _source = source;
      _error = error;
      _checkedText = text;
    });
  }

  /// Who signed an attestation with [issuer]: lnp2pBot, a known Mostro whose
  /// info event announces the key, or the key itself. A failed registry
  /// lookup names the key: the figures still show, the import still waits.
  Future<_Source> _resolveSource(ReputationApi api, String issuer) async {
    if (issuer == lnp2pbotIssuerKey) return const _Lnp2pbot();
    MostroNodeEntry? node;
    try {
      node = await api.issuerNode(issuer);
    } catch (_) {
      node = null;
    }
    if (node == null) return _UnknownKey(_npubOrHex(api, issuer));
    // The name is the node's own profile text: blank reads as none.
    final name = node.name?.trim();
    return _KnownMostro(
      name == null || name.isEmpty ? _npubOrHex(api, node.pubkey) : name,
    );
  }

  static String _npubOrHex(ReputationApi api, String key) {
    try {
      return api.npub(key);
    } catch (_) {
      return key;
    }
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
          _source = null;
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
              child: _Figures(attestation: attestation, source: _source),
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

/// Who signed an attestation, as the checked card names it (#881).
sealed class _Source {
  const _Source();
}

class _Lnp2pbot extends _Source {
  const _Lnp2pbot();
}

/// A known Mostro, by its cached profile name or its npub.
class _KnownMostro extends _Source {
  final String name;

  const _KnownMostro(this.name);
}

/// A key nothing identifies, as npub.
class _UnknownKey extends _Source {
  final String npub;

  const _UnknownKey(this.npub);
}

class _Figures extends StatelessWidget {
  final ReputationAttestationInfo attestation;
  final _Source? source;

  const _Figures({required this.attestation, required this.source});

  /// The source, named before the figures: the import cannot be undone and
  /// uses up this issuer for the identity on this node.
  List<Widget> _sourceLines(AppLocalizations l10n, OrderBookPalette book) {
    final source = this.source;
    if (source == null) return const [];
    final label = TextStyle(color: book.textMuted, fontSize: 12);
    final key = switch (source) {
      _UnknownKey(:final npub) => npub,
      _ => null,
    };
    return [
      Text(switch (source) {
        _Lnp2pbot() => l10n.reputationIssuedByLnp2pbot,
        _KnownMostro(:final name) => l10n.reputationIssuedByMostro(name),
        _UnknownKey() => l10n.reputationIssuedByUnknownKey,
      }, style: label).withAutomationId(AutomationIds.reputationImportSource),
      if (key != null) ...[
        const SizedBox(height: 4),
        SelectableText(
          key,
          textDirection: TextDirection.ltr,
          style: TextStyle(
            color: book.textPrimary,
            fontFamily: 'monospace',
            fontSize: 12,
          ),
        ),
      ],
      const SizedBox(height: 8),
    ];
  }

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
          ..._sourceLines(l10n, book),
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

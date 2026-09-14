import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:mostro/core/about_palette.dart';
import 'package:mostro/core/app_routes.dart';
import 'package:mostro/core/app_theme.dart';
import 'package:mostro/features/about/models/about_rules.dart';
import 'package:mostro/features/about/models/mostro_instance.dart';
import 'package:mostro/features/about/providers/app_version_provider.dart';
import 'package:mostro/features/about/providers/mostro_node_provider.dart';
import 'package:mostro/features/about/widgets/about_widgets.dart';
import 'package:mostro/features/order/widgets/order_detail_cards.dart'
    show orderDetailAppBar;
import 'package:mostro/features/settings/providers/mostro_nodes_provider.dart'
    show truncatePubkey;
import 'package:mostro/l10n/app_localizations.dart';

export 'package:mostro/features/about/providers/app_version_provider.dart'
    show appVersionProvider;

// ── External links ────────────────────────────────────────────────────────────

/// This app's own source. AGPL section 13 asks a program that interacts with
/// users over a network to offer them the Corresponding Source, and this link
/// is that offer — it pointed at `MostroP2P/mostro-mobile`, a repository that
/// does not exist, so the offer was a 404. `MostroP2P/mobile` is v1; this app
/// is `MostroP2P/app`.
const _githubUrl = 'https://github.com/MostroP2P/app';
const _docsEnUrl = 'https://mostro.network/docs-english/';
const _docsEsUrl = 'https://mostro.network/docs-spanish/';
const _docsTechUrl = 'https://mostro.network/protocol/';

const _logoAsset = 'assets/images/mostro_logo.webp';

// ── License notice ───────────────────────────────────────────────────────────

/// The AGPLv3 notice the FSF recommends programs display, kept verbatim and
/// **not** localized: a translated licence has no legal force
/// (<https://www.gnu.org/licenses/translations.html>), so every locale shows
/// the English original and only the dialog's title is translated.
///
/// The project is `AGPL-3.0-or-later`, so the notice keeps the FSF's "or (at
/// your option) any later version" clause: the project can adopt a future
/// version of the licence without collecting every contributor's consent, and
/// `LICENSE` still ships version 3 as the terms in force today. The full
/// 661-line text lives there and at the URL below, not in the app bundle.
///
/// AGPL section 13 asks a program that interacts with users over a network to
/// offer them its source. This screen's repository link is that offer, which
/// is why it must keep pointing at this app's own source.
const _agplLicenseNotice = '''Mostro
Copyright (C) 2024 Mostro

This program is free software: you can redistribute it and/or modify
it under the terms of the GNU Affero General Public License as published by
the Free Software Foundation, either version 3 of the License, or
(at your option) any later version.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU Affero General Public License for more details.

You should have received a copy of the GNU Affero General Public License
along with this program.  If not, see <https://www.gnu.org/licenses/>.''';

// ── Screen ────────────────────────────────────────────────────────────────────

/// About (`design_handoff_acerca_de`, 12a): one screen with what a user
/// looks up — the app, its docs and the connected node's limits. The node's
/// technical fields live one tap away, on `NodeTechnicalDataScreen` (12b).
class AboutScreen extends ConsumerWidget {
  const AboutScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final appVersion = ref
        .watch(appVersionProvider)
        .when(data: (v) => v, loading: () => '…', error: (_, __) => 'unknown');
    final nodeAsync = ref.watch(mostroNodeProvider);

    return Scaffold(
      backgroundColor: OrderBookPalette.of(context).bg,
      appBar: orderDetailAppBar(
        context,
        title: l10n.aboutScreenTitle,
        onBack:
            () => context.canPop() ? context.pop() : context.go(AppRoute.home),
      ),
      // #267: SafeArea keeps the last card clear of the system navigation bar.
      body: SafeArea(
        top: false,
        child: AboutFillViewport(
          footer: _TechnicalDataCard(nodeAsync: nodeAsync),
          children: [
            _BrandCard(appVersion: appVersion),
            AboutGroupHeader(l10n.aboutAppSection),
            AboutCard(
              child: AboutRowList(
                rows: [
                  AboutNavRow(
                    label: l10n.aboutLicenseLabel,
                    value: l10n.aboutLicenseName,
                    trailing: AboutRowTrailing.chevron,
                    onTap: () => _showLicenseDialog(context, l10n),
                  ),
                  AboutNavRow(
                    label: l10n.aboutSourceCodeLabel,
                    value: l10n.aboutGithubRepoName,
                    valueIsFigure: true,
                    trailing: AboutRowTrailing.external,
                    onTap: () => _openExternal(context, _githubUrl),
                  ),
                ],
              ),
            ),
            AboutGroupHeader(l10n.aboutDocumentationTitle),
            AboutCard(
              child: AboutRowList(
                rows: [
                  AboutNavRow(
                    label: l10n.aboutUserGuideLabel,
                    value: l10n.aboutLanguageSpanish,
                    trailing: AboutRowTrailing.external,
                    onTap: () => _openExternal(context, _docsEsUrl),
                  ),
                  AboutNavRow(
                    label: l10n.aboutUserGuideLabel,
                    value: l10n.aboutLanguageEnglish,
                    trailing: AboutRowTrailing.external,
                    onTap: () => _openExternal(context, _docsEnUrl),
                  ),
                  AboutNavRow(
                    label: l10n.aboutTechnicalDocsLabel,
                    value: l10n.aboutLanguageEnglish,
                    trailing: AboutRowTrailing.external,
                    onTap: () => _openExternal(context, _docsTechUrl),
                  ),
                ],
              ),
            ),
            AboutGroupHeader(l10n.aboutConnectedNodeTitle),
            _ConnectedNodeCard(nodeAsync: nodeAsync),
          ],
        ),
      ),
    );
  }

  void _showLicenseDialog(BuildContext context, AppLocalizations l10n) {
    final book = OrderBookPalette.of(context);
    showDialog<void>(
      context: context,
      builder:
          (ctx) => AlertDialog(
            title: Text(l10n.aboutLicenseDialogTitle),
            content: SizedBox(
              width: double.maxFinite,
              height: 320,
              child: SingleChildScrollView(
                child: Text(
                  _agplLicenseNotice,
                  style: TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 12,
                    color: book.textMuted,
                    height: 1.5,
                  ),
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: Text(l10n.closeButtonLabel),
              ),
            ],
          ),
    );
  }
}

/// Opens [url] in the external browser. With no app to hand it to, the link
/// is offered on a snackbar instead, with a copy action.
Future<void> _openExternal(BuildContext context, String url) async {
  final l10n = AppLocalizations.of(context);
  final messenger = ScaffoldMessenger.of(context);
  var launched = false;
  try {
    launched = await launchUrl(
      Uri.parse(url),
      mode: LaunchMode.externalApplication,
    );
  } catch (_) {
    // A platform without a browser throws instead of returning false; both
    // land on the same fallback below.
    launched = false;
  }
  if (launched) return;
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Text(url),
        action: SnackBarAction(
          label: l10n.copyButtonLabel,
          onPressed: () {
            Clipboard.setData(ClipboardData(text: url));
            messenger.showSnackBar(
              SnackBar(
                content: Text(l10n.linkCopiedToClipboard),
                duration: const Duration(seconds: 2),
              ),
            );
          },
        ),
      ),
    );
}

// ── Brand ─────────────────────────────────────────────────────────────────────

class _BrandCard extends StatelessWidget {
  const _BrandCard({required this.appVersion});

  final String appVersion;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final book = OrderBookPalette.of(context);
    final pal = AboutPalette.of(context);
    final pill =
        appVersion == '…' || appVersion.startsWith('v')
            ? appVersion
            : 'v$appVersion';

    return AboutCard(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: pal.logoFill,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Image.asset(
              _logoAsset,
              fit: BoxFit.contain,
              excludeFromSemantics: true,
            ),
          ),
          const SizedBox(width: 13),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Mostro',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: book.textPrimary,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  l10n.footerTagline,
                  style: TextStyle(fontSize: 11, color: book.textSecondary),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Semantics(
            label: '${l10n.aboutVersionLabel} $appVersion',
            excludeSemantics: true,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
              decoration: BoxDecoration(
                color: pal.pillFill,
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: pal.pillBorder),
              ),
              child: Text(
                pill,
                style: TextStyle(
                  fontFamily: AppFonts.figures,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: pal.accent,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Connected node ────────────────────────────────────────────────────────────

/// Always rendered, loaded or not: hiding it until the node answers would make
/// the layout jump. Missing figures read `—` and the dot says which state the
/// node is in.
class _ConnectedNodeCard extends ConsumerWidget {
  const _ConnectedNodeCard({required this.nodeAsync});

  final AsyncValue<MostroInstance?> nodeAsync;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final book = OrderBookPalette.of(context);
    final pal = AboutPalette.of(context);
    final node = nodeAsync.valueOrNull;
    final dot =
        node != null
            ? pal.dotOnline
            : nodeAsync.isLoading
            ? pal.dotPending
            : pal.dotOffline;
    final String pubkey =
        node != null ? node.pubKey : ref.watch(activeMostroPubkeyProvider);
    final name = ref.watch(activeNodeNameProvider) ?? l10n.aboutMostroNodeTitle;
    final limits = NodeLimits.of(node, l10n);

    return AboutCard(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // The copy icon keeps a 44 dp target, which sets this row's height
          // and supplies its right-hand inset.
          Padding(
            padding: const EdgeInsets.only(left: 14),
            child: SizedBox(
              height: aboutMinTapTarget,
              child: Row(
                children: [
                  Container(
                    width: 7,
                    height: 7,
                    decoration: BoxDecoration(
                      color: dot,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 9),
                  Expanded(
                    child: Text(
                      name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: book.textPrimary,
                      ),
                    ),
                  ),
                  const SizedBox(width: 9),
                  Semantics(
                    label: pubkey,
                    excludeSemantics: true,
                    child: Text(
                      truncatePubkey(pubkey),
                      style: TextStyle(
                        fontFamily: AppFonts.figures,
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                        color: book.textSecondary,
                      ),
                    ),
                  ),
                  CopyIconButton(
                    text: pubkey,
                    size: 14,
                    color: pal.icon,
                    tooltip: l10n.copyButtonLabel,
                    copiedLabel: l10n.aboutCopiedToClipboard,
                  ),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: Row(
              children: [
                Expanded(child: _LimitCell(l10n.aboutMinOrderCell, limits.min)),
                const SizedBox(width: 8),
                Expanded(child: _LimitCell(l10n.aboutMaxOrderCell, limits.max)),
                const SizedBox(width: 8),
                Expanded(child: _LimitCell(l10n.aboutFeeCell, limits.fee)),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: Text(
              l10n.aboutLimitsFootnote,
              style: TextStyle(fontSize: 10, color: pal.groupHeader),
            ),
          ),
        ],
      ),
    );
  }
}

class _LimitCell extends StatelessWidget {
  const _LimitCell(this.label, this.value);

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final book = OrderBookPalette.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
      decoration: BoxDecoration(
        color: AboutPalette.of(context).cell,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 10, color: book.textSecondary),
          ),
          const SizedBox(height: 3),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              value,
              style: TextStyle(
                fontFamily: AppFonts.figures,
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: book.textStrong,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Leads to 12b once the node answered; retries the fetch when it did not.
class _TechnicalDataCard extends ConsumerWidget {
  const _TechnicalDataCard({required this.nodeAsync});

  final AsyncValue<MostroInstance?> nodeAsync;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final node = nodeAsync.valueOrNull;
    final unavailable = node == null && !nodeAsync.isLoading;
    final value =
        node != null
            ? l10n.aboutFieldCount(nodeFieldCount(nodeTechSections(node, l10n)))
            : unavailable
            ? l10n.aboutNodeRetry
            : missingFigure;

    return AboutCard(
      child: AboutNavRow(
        icon: Icons.dns_outlined,
        label: l10n.aboutNodeTechnicalDataRow,
        value: value,
        trailing: AboutRowTrailing.chevron,
        onTap:
            node != null
                ? () => context.push(AppRoute.aboutTechnical)
                : unavailable
                ? () => ref.invalidate(mostroNodeProvider)
                : null,
      ),
    );
  }
}

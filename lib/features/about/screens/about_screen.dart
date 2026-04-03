import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:mostro/core/app_theme.dart';
import 'package:mostro/features/about/models/mostro_instance.dart';
import 'package:mostro/features/about/providers/mostro_node_provider.dart';
import 'package:mostro/l10n/app_localizations.dart';
import 'package:mostro/src/rust/api.dart' as rust_api;

// ── App version provider ──────────────────────────────────────────────────────

/// Provides the app version string from the Rust layer.
final appVersionProvider = FutureProvider<String>((ref) async {
  return rust_api.getAppVersion();
});

// ── Commit hash from build environment ───────────────────────────────────────

const _gitCommit =
    String.fromEnvironment('GIT_COMMIT', defaultValue: '');

// ── External links ────────────────────────────────────────────────────────────

const _githubUrl =
    'https://github.com/MostroP2P/mostro-mobile';
const _docsEnUrl = 'https://mostro.network/docs-english/';
const _docsEsUrl = 'https://mostro.network/docs-spanish/';
const _docsTechUrl = 'https://mostro.network/protocol/';

// ── MIT License text ──────────────────────────────────────────────────────────

const _mitLicenseText = '''MIT License

Copyright (c) 2024 Mostro

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.''';

// ── Screen ────────────────────────────────────────────────────────────────────

class AboutScreen extends ConsumerWidget {
  const AboutScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final colors = Theme.of(context).extension<AppColors>()!;
    final appVersion = ref.watch(appVersionProvider).when(
          data: (v) => v,
          loading: () => '…',
          error: (_, __) => 'unknown',
        );
    final nodeAsync = ref.watch(mostroNodeProvider);

    return Scaffold(
      appBar: AppBar(title: Text(l10n.aboutScreenTitle)),
      body: ListView(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.lg,
          vertical: AppSpacing.lg,
        ),
        children: [
          // ── App Information Card ───────────────────────────────────────────
          _InfoCard(
            icon: Icons.smartphone_outlined,
            title: l10n.aboutAppInfoTitle,
            children: [
              _InfoRow(label: l10n.aboutVersionLabel, value: appVersion),
              _InfoRowLink(
                label: l10n.aboutGithubRepoLabel,
                display: l10n.aboutGithubRepoName,
                url: _githubUrl,
              ),
              if (_gitCommit.isNotEmpty)
                _InfoRow(
                  label: l10n.aboutCommitHashLabel,
                  value: _gitCommit.length > 7
                      ? _gitCommit.substring(0, 7)
                      : _gitCommit,
                ),
              _InfoRowTappable(
                label: l10n.aboutLicenseLabel,
                value: l10n.aboutLicenseName,
                onTap: () => _showLicenseDialog(context, l10n),
              ),
            ],
          ),

          const SizedBox(height: AppSpacing.lg),

          // ── Documentation Card ─────────────────────────────────────────────
          _InfoCard(
            icon: Icons.menu_book_outlined,
            title: l10n.aboutDocumentationTitle,
            children: [
              _InfoRowLink(
                label: l10n.aboutDocsUsersEnglish,
                display: l10n.aboutDocsRead,
                url: _docsEnUrl,
              ),
              _InfoRowLink(
                label: l10n.aboutDocsUsersSpanish,
                display: l10n.aboutDocsRead,
                url: _docsEsUrl,
              ),
              _InfoRowLink(
                label: l10n.aboutDocsTechnical,
                display: l10n.aboutDocsRead,
                url: _docsTechUrl,
              ),
            ],
          ),

          const SizedBox(height: AppSpacing.lg),

          // ── Mostro Node Card ───────────────────────────────────────────────
          _InfoCard(
            icon: Icons.dns_outlined,
            title: l10n.aboutMostroNodeTitle,
            children: [
              nodeAsync.when(
                loading: () => Padding(
                  padding: const EdgeInsets.symmetric(vertical: AppSpacing.lg),
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: colors.mostroGreen,
                          ),
                        ),
                        const SizedBox(height: AppSpacing.sm),
                        Text(
                          l10n.aboutNodeLoadingText,
                          style: TextStyle(
                            fontSize: 13,
                            color: colors.textSubtle,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                error: (_, __) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: AppSpacing.lg),
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          l10n.aboutNodeUnavailable,
                          style: TextStyle(
                            fontSize: 13,
                            color: colors.textSubtle,
                          ),
                        ),
                        const SizedBox(height: AppSpacing.sm),
                        TextButton(
                          onPressed: () =>
                              ref.invalidate(mostroNodeProvider),
                          child: Text(l10n.aboutNodeRetry),
                        ),
                      ],
                    ),
                  ),
                ),
                data: (node) => node == null
                    ? Padding(
                        padding:
                            const EdgeInsets.symmetric(vertical: AppSpacing.lg),
                        child: Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                l10n.aboutNodeUnavailable,
                                style: TextStyle(
                                  fontSize: 13,
                                  color: colors.textSubtle,
                                ),
                              ),
                              const SizedBox(height: AppSpacing.sm),
                              TextButton(
                                onPressed: () =>
                                    ref.invalidate(mostroNodeProvider),
                                child: Text(l10n.aboutNodeRetry),
                              ),
                            ],
                          ),
                        ),
                      )
                    : _MostroNodeContent(node: node, l10n: l10n),
              ),
            ],
          ),

          const SizedBox(height: AppSpacing.xxl),

          Center(
            child: Text(
              l10n.footerTagline,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: colors.textSubtle,
                  ),
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
        ],
      ),
    );
  }

  void _showLicenseDialog(BuildContext context, AppLocalizations l10n) {
    final colors = Theme.of(context).extension<AppColors>()!;
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.aboutLicenseDialogTitle),
        content: SizedBox(
          width: double.maxFinite,
          height: 320,
          child: SingleChildScrollView(
            child: Text(
              _mitLicenseText,
              style: TextStyle(
                fontFamily: 'monospace',
                fontSize: 12,
                color: colors.textSecondary,
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

// ── Mostro Node Content ───────────────────────────────────────────────────────

class _MostroNodeContent extends StatelessWidget {
  const _MostroNodeContent({required this.node, required this.l10n});

  final MostroInstance node;
  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionHeader(title: l10n.aboutGeneralInfoSection),
        const SizedBox(height: AppSpacing.md),
        _NodeInfoRowCopyable(
          label: l10n.aboutMostroPublicKeyLabel,
          value: node.pubKey,
          explanation: l10n.aboutMostroPublicKeyExplanation,
        ),
        if (node.maxOrderAmount != null)
          _NodeInfoRowInfo(
            label: l10n.aboutMaxOrderAmountLabel,
            value:
                '${_fmt(node.maxOrderAmount!)} ${l10n.aboutSatoshisSuffix}',
            explanation: l10n.aboutMaxOrderAmountExplanation,
          ),
        if (node.minOrderAmount != null)
          _NodeInfoRowInfo(
            label: l10n.aboutMinOrderAmountLabel,
            value:
                '${_fmt(node.minOrderAmount!)} ${l10n.aboutSatoshisSuffix}',
            explanation: l10n.aboutMinOrderAmountExplanation,
          ),
        if (node.expirationHours != null)
          _NodeInfoRowInfo(
            label: l10n.aboutOrderLifespanLabel,
            value: '${node.expirationHours} ${l10n.aboutHoursSuffix}',
            explanation: l10n.aboutOrderLifespanExplanation,
          ),
        if (node.feePercent != null)
          _NodeInfoRowInfo(
            label: l10n.aboutServiceFeeLabel,
            value: node.feePercent!,
            explanation: l10n.aboutServiceFeeExplanation,
          ),
        _NodeInfoRowInfo(
          label: l10n.aboutFiatCurrenciesLabel,
          value: _fiatDisplay(node.fiatCurrenciesAccepted, l10n),
          explanation: l10n.aboutFiatCurrenciesExplanation,
        ),

        const SizedBox(height: AppSpacing.xl),
        _SectionHeader(title: l10n.aboutTechnicalDetailsSection),
        const SizedBox(height: AppSpacing.md),
        if (node.mostroVersion != null)
          _NodeInfoRowInfo(
            label: l10n.aboutMostroVersionLabel,
            value: node.mostroVersion!,
            explanation: l10n.aboutMostroVersionExplanation,
          ),
        if (node.commitHash != null)
          _NodeInfoRowInfo(
            label: l10n.aboutMostroCommitLabel,
            value: _truncateHash(node.commitHash!),
            explanation: l10n.aboutMostroCommitExplanation,
          ),
        if (node.expirationSeconds != null)
          _NodeInfoRowInfo(
            label: l10n.aboutOrderExpirationLabel,
            value: '${node.expirationSeconds} ${l10n.aboutSecondsSuffix}',
            explanation: l10n.aboutOrderExpirationExplanation,
          ),
        if (node.holdInvoiceExpirationWindow != null)
          _NodeInfoRowInfo(
            label: l10n.aboutHoldInvoiceExpLabel,
            value:
                '${node.holdInvoiceExpirationWindow} ${l10n.aboutSecondsSuffix}',
            explanation: l10n.aboutHoldInvoiceExpExplanation,
          ),
        if (node.holdInvoiceCltvDelta != null)
          _NodeInfoRowInfo(
            label: l10n.aboutHoldInvoiceCltvLabel,
            value:
                '${node.holdInvoiceCltvDelta} ${l10n.aboutBlocksSuffix}',
            explanation: l10n.aboutHoldInvoiceCltvExplanation,
          ),
        if (node.invoiceExpirationWindow != null)
          _NodeInfoRowInfo(
            label: l10n.aboutInvoiceExpWindowLabel,
            value:
                '${node.invoiceExpirationWindow} ${l10n.aboutSecondsSuffix}',
            explanation: l10n.aboutInvoiceExpWindowExplanation,
          ),
        if (node.pow != null)
          _NodeInfoRowInfo(
            label: l10n.aboutProofOfWorkLabel,
            value: '${node.pow}',
            explanation: l10n.aboutProofOfWorkExplanation,
          ),
        if (node.maxOrdersPerResponse != null)
          _NodeInfoRowInfo(
            label: l10n.aboutMaxOrdersPerResponseLabel,
            value: '${node.maxOrdersPerResponse}',
            explanation: l10n.aboutMaxOrdersPerResponseExplanation,
          ),

        const SizedBox(height: AppSpacing.xl),
        _SectionHeader(title: l10n.aboutLightningNetworkSection),
        const SizedBox(height: AppSpacing.md),
        if (node.lndVersion != null)
          _NodeInfoRowInfo(
            label: l10n.aboutLndVersionLabel,
            value: node.lndVersion!,
            explanation: l10n.aboutLndVersionExplanation,
          ),
        if (node.lndNodePublicKey != null)
          _NodeInfoRowCopyable(
            label: l10n.aboutLndNodePublicKeyLabel,
            value: node.lndNodePublicKey!,
            explanation: l10n.aboutLndNodePublicKeyExplanation,
          ),
        if (node.lndCommitHash != null)
          _NodeInfoRowInfo(
            label: l10n.aboutLndCommitLabel,
            value: _truncateHash(node.lndCommitHash!),
            explanation: l10n.aboutLndCommitExplanation,
          ),
        if (node.lndNodeAlias != null)
          _NodeInfoRowInfo(
            label: l10n.aboutLndNodeAliasLabel,
            value: node.lndNodeAlias!,
            explanation: l10n.aboutLndNodeAliasExplanation,
          ),
        if (node.lndChains != null)
          _NodeInfoRowInfo(
            label: l10n.aboutSupportedChainsLabel,
            value: node.lndChains!,
            explanation: l10n.aboutSupportedChainsExplanation,
          ),
        if (node.lndNetworks != null)
          _NodeInfoRowInfo(
            label: l10n.aboutSupportedNetworksLabel,
            value: node.lndNetworks!,
            explanation: l10n.aboutSupportedNetworksExplanation,
          ),
        if (node.lndUris != null)
          _NodeInfoRowCopyable(
            label: l10n.aboutLndNodeUriLabel,
            value: node.lndUris!,
            explanation: l10n.aboutLndNodeUriExplanation,
          ),
      ],
    );
  }

  String _fiatDisplay(String? raw, AppLocalizations l10n) {
    if (raw == null || raw.trim().isEmpty) return l10n.aboutFiatCurrenciesAll;
    return raw;
  }

  String _truncateHash(String hash) {
    if (hash.length <= 7) return hash;
    return hash.substring(0, 7);
  }

  static String _fmt(int v) => v.toString().replaceAllMapped(
        RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'),
        (m) => '${m[1]},',
      );
}

// ── Card wrapper ──────────────────────────────────────────────────────────────

class _InfoCard extends StatelessWidget {
  const _InfoCard({
    required this.icon,
    required this.title,
    required this.children,
  });

  final IconData icon;
  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppColors>()!;
    return Container(
      decoration: BoxDecoration(
        color: colors.backgroundCard,
        borderRadius: BorderRadius.circular(AppRadius.card),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Card header
            Row(
              children: [
                Icon(icon, size: 20, color: colors.mostroGreen),
                const SizedBox(width: AppSpacing.sm),
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: colors.textPrimary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.lg),
            ...children,
          ],
        ),
      ),
    );
  }
}

// ── Section header ────────────────────────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppColors>()!;
    return Row(
      children: [
        Expanded(
          child: Divider(color: colors.textSubtle.withAlpha(60), height: 1),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
          child: Text(
            title,
            style: TextStyle(
              color: colors.mostroGreen,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        Expanded(
          child: Divider(color: colors.textSubtle.withAlpha(60), height: 1),
        ),
      ],
    );
  }
}

// ── Standard info row (label + value) ─────────────────────────────────────────

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppColors>()!;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 140,
            child: Text(
              label,
              style: TextStyle(fontSize: 14, color: colors.textSecondary),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: colors.textPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Info row with external link ───────────────────────────────────────────────

class _InfoRowLink extends StatelessWidget {
  const _InfoRowLink({
    required this.label,
    required this.display,
    required this.url,
  });

  final String label;
  final String display;
  final String url;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppColors>()!;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 140,
            child: Text(
              label,
              style: TextStyle(fontSize: 14, color: colors.textSecondary),
            ),
          ),
          Expanded(
            child: GestureDetector(
              onTap: () => _openLink(context, url),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    display,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: colors.textLink,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Icon(
                    Icons.open_in_new,
                    size: 14,
                    color: colors.textLink,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _openLink(BuildContext context, String url) {
    // url_launcher is not in pubspec — show a SnackBar with copy action.
    final messenger = ScaffoldMessenger.of(context);
    messenger.showSnackBar(
      SnackBar(
        content: Text(url),
        action: SnackBarAction(
          label: 'Copy',
          onPressed: () {
            Clipboard.setData(ClipboardData(text: url));
            messenger.hideCurrentSnackBar();
            messenger.showSnackBar(
              const SnackBar(
                content: Text('Link copied to clipboard'),
                duration: Duration(seconds: 2),
              ),
            );
          },
        ),
      ),
    );
  }
}

// ── Info row tappable (e.g. License) ──────────────────────────────────────────

class _InfoRowTappable extends StatelessWidget {
  const _InfoRowTappable({
    required this.label,
    required this.value,
    required this.onTap,
  });

  final String label;
  final String value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppColors>()!;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 140,
            child: Text(
              label,
              style: TextStyle(fontSize: 14, color: colors.textSecondary),
            ),
          ),
          Expanded(
            child: GestureDetector(
              onTap: onTap,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    value,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: colors.textLink,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Icon(
                    Icons.open_in_new,
                    size: 14,
                    color: colors.textLink,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Node info row with ℹ️ button ──────────────────────────────────────────────

class _NodeInfoRowInfo extends StatelessWidget {
  const _NodeInfoRowInfo({
    required this.label,
    required this.value,
    required this.explanation,
  });

  final String label;
  final String value;
  final String explanation;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppColors>()!;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                label,
                style: TextStyle(fontSize: 14, color: colors.textSecondary),
              ),
              const SizedBox(width: AppSpacing.xs),
              GestureDetector(
                onTap: () => _showInfo(context, label, explanation),
                child: Icon(
                  Icons.info_outline,
                  size: 16,
                  color: colors.textSubtle,
                ),
              ),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: colors.textPrimary,
            ),
          ),
        ],
      ),
    );
  }

  void _showInfo(BuildContext context, String title, String body) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(body),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }
}

// ── Node info row with ℹ️ and 📋 buttons ─────────────────────────────────────

class _NodeInfoRowCopyable extends StatelessWidget {
  const _NodeInfoRowCopyable({
    required this.label,
    required this.value,
    required this.explanation,
  });

  final String label;
  final String value;
  final String explanation;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppColors>()!;
    final display = value.length > 20
        ? '${value.substring(0, 8)}…${value.substring(value.length - 8)}'
        : value;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                label,
                style: TextStyle(fontSize: 14, color: colors.textSecondary),
              ),
              const SizedBox(width: AppSpacing.xs),
              GestureDetector(
                onTap: () => _showInfo(context, label, explanation),
                child: Icon(
                  Icons.info_outline,
                  size: 16,
                  color: colors.textSubtle,
                ),
              ),
              const SizedBox(width: AppSpacing.xs),
              GestureDetector(
                onTap: () => _copy(context, value),
                child: Icon(
                  Icons.content_copy_outlined,
                  size: 16,
                  color: colors.textSubtle,
                ),
              ),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            display,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w500,
              fontFamily: 'monospace',
              color: colors.textPrimary,
            ),
          ),
        ],
      ),
    );
  }

  void _showInfo(BuildContext context, String title, String body) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(body),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  void _copy(BuildContext context, String v) {
    Clipboard.setData(ClipboardData(text: v));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Copied to clipboard'),
        duration: Duration(seconds: 2),
      ),
    );
  }
}

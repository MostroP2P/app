import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:mostro/core/about_palette.dart';
import 'package:mostro/core/app_routes.dart';
import 'package:mostro/core/app_theme.dart';
import 'package:mostro/features/about/models/about_rules.dart';
import 'package:mostro/features/about/providers/app_version_provider.dart';
import 'package:mostro/features/about/providers/mostro_node_provider.dart';
import 'package:mostro/features/about/widgets/about_widgets.dart';
import 'package:mostro/features/order/widgets/order_detail_cards.dart'
    show orderDetailAppBar;
import 'package:mostro/l10n/app_localizations.dart';

/// Technical data (`design_handoff_acerca_de`, 12b): every field the
/// connected node publishes, grouped, with copy on keys and URIs and one
/// `Copy all data` for support requests. Reached from About (12a).
class NodeTechnicalDataScreen extends ConsumerWidget {
  const NodeTechnicalDataScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final pal = AboutPalette.of(context);
    final appVersion = ref.watch(appVersionProvider).valueOrNull ?? '…';
    final nodeAsync = ref.watch(mostroNodeProvider);
    final node = nodeAsync.valueOrNull;

    final app = appTechSection(appVersion, appGitCommit, l10n);
    final nodeSections =
        node == null ? const <TechSection>[] : nodeTechSections(node, l10n);
    final clipboard =
        node == null
            ? null
            : technicalDataClipboard(
              app: app,
              limits: NodeLimits.of(node, l10n),
              nodeSections: nodeSections,
              l10n: l10n,
            );
    final sections = [app, ...nodeSections];

    return Scaffold(
      backgroundColor: OrderBookPalette.of(context).bg,
      appBar: orderDetailAppBar(
        context,
        title: l10n.aboutTechnicalDataTitle,
        onBack:
            () => context.canPop() ? context.pop() : context.go(AppRoute.about),
        trailing:
            clipboard == null
                ? null
                : CopyIconButton(
                  text: clipboard,
                  size: 17,
                  color: pal.accent,
                  tooltip: l10n.aboutCopyAllData,
                  copiedLabel: l10n.aboutCopiedToClipboard,
                ),
      ),
      body: SafeArea(
        top: false,
        child: AboutFillViewport(
          footer:
              clipboard == null
                  ? null
                  : CopyAllButton(
                    text: clipboard,
                    label: l10n.aboutCopyAllData,
                    copiedLabel: l10n.aboutCopiedToClipboard,
                  ),
          children: [
            for (var i = 0; i < sections.length; i++) ...[
              AboutGroupHeader(sections[i].title, topPadding: i == 0 ? 2 : 4),
              AboutCard(
                child: AboutRowList(
                  rows: [
                    for (final row in sections[i].rows)
                      TechRowTile(
                        row,
                        copyTooltip: l10n.copyButtonLabel,
                        copiedLabel: l10n.aboutCopiedToClipboard,
                      ),
                  ],
                ),
              ),
            ],
            if (node != null)
              AboutNote(l10n.aboutTechnicalFootnote)
            else if (nodeAsync.isLoading)
              AboutNote(l10n.aboutNodeLoadingText)
            else
              AboutNote(
                l10n.aboutNodeUnavailable,
                action: TextButton(
                  onPressed: () => ref.invalidate(mostroNodeProvider),
                  child: Text(l10n.aboutNodeRetry),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

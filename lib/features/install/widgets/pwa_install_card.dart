import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mostro/core/app_theme.dart';
import 'package:mostro/features/install/providers/pwa_install_provider.dart';
import 'package:mostro/features/install/widgets/pwa_install_action.dart';
import 'package:mostro/l10n/app_localizations.dart';
import 'package:mostro/shared/widgets/redesign_app_bar.dart';

const _cardRadius = BorderRadius.all(Radius.circular(18));

/// The most of the screen's height the card may take.
const double _maxHeightShare = 1 / 3;

/// The order book's offer to install the web app, once, on a phone (#778).
///
/// A flat card rather than a modal, and links rather than a filled button:
/// the create-order button stays the screen's one primary action (DS-CMP-3),
/// and "Not now" is a way out without consequence (DS-CMP-20). Either answer
/// hides it for good; Settings → Install app stays for a change of mind.
/// Renders nothing while there is nothing to offer.
class PwaInstallCard extends ConsumerWidget {
  const PwaInstallCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final offered = ref.watch(pwaInstallProvider.select((s) => s.offersCard));
    // In landscape or a wide split screen the order book's fixed header
    // already fills most of the height: the card waits for portrait. Not
    // shown is not answered, so it is offered again then.
    final portrait = MediaQuery.orientationOf(context) == Orientation.portrait;
    if (!offered || !portrait) return const SizedBox.shrink();

    final l10n = AppLocalizations.of(context);
    final book = OrderBookPalette.of(context);

    // On a short portrait screen (large text) it keeps to a third of the
    // height rather than squeezing the list out (DS-SPC-5). The text scrolls
    // inside it; the answers stay in view below.
    return ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * _maxHeightShare,
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          redesignSidePadding,
          0,
          redesignSidePadding,
          12,
        ),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: book.surface,
            borderRadius: _cardRadius,
            border: Border.all(color: book.border),
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 4),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Flexible(
                  child: SingleChildScrollView(
                    child: _Message(
                      title: l10n.pwaInstallTitle,
                      body: l10n.pwaInstallBody,
                    ),
                  ),
                ),
                Wrap(
                  alignment: WrapAlignment.end,
                  spacing: 8,
                  children: [
                    _CardLink(
                      label: l10n.pwaInstallNotNow,
                      color: book.textSecondary,
                      weight: FontWeight.w500,
                      onPressed:
                          () =>
                              ref
                                  .read(pwaInstallProvider.notifier)
                                  .markAnswered(),
                    ),
                    _CardLink(
                      label: l10n.pwaInstallAction,
                      color: book.limeText,
                      weight: FontWeight.w600,
                      onPressed: () => startPwaInstall(context, ref),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The card's icon, title and body.
class _Message extends StatelessWidget {
  const _Message({required this.title, required this.body});

  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    final book = OrderBookPalette.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(Icons.install_mobile_outlined, size: 20, color: book.limeIcon),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: book.textPrimary,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                body,
                style: TextStyle(
                  fontSize: 13,
                  height: 1.45,
                  color: book.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// A text action of the card, padded out to a 48-dp target (DS-CMP-6).
class _CardLink extends StatelessWidget {
  const _CardLink({
    required this.label,
    required this.color,
    required this.weight,
    required this.onPressed,
  });

  final String label;
  final Color color;
  final FontWeight weight;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return TextButton(
      onPressed: onPressed,
      style: TextButton.styleFrom(
        foregroundColor: color,
        minimumSize: const Size(48, 48),
        textStyle: TextStyle(fontSize: 13, fontWeight: weight),
      ),
      child: Text(label),
    );
  }
}

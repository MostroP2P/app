import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mostro/core/app_theme.dart';
import 'package:mostro/features/install/providers/pwa_install_provider.dart';
import 'package:mostro/l10n/app_localizations.dart';
import 'package:mostro/shared/widgets/mostro_modal.dart';

/// Installs the web app the way this browser allows (#778): its own dialog
/// on Android and desktop Chromium, the steps to follow by hand on iOS.
///
/// Counts as the user's answer to the order book's card, so the card never
/// shows again. Shared by the card and by Settings → Install app.
Future<void> startPwaInstall(BuildContext context, WidgetRef ref) async {
  // Opened before the answer is stored, while the card's context still
  // stands; the sheet lives on the navigator after the card is gone.
  if (ref.read(pwaInstallProvider).route == PwaInstallRoute.instructions) {
    unawaited(_showSteps(context));
  }
  await ref.read(pwaInstallProvider.notifier).install();
}

Future<void> _showSteps(BuildContext context) => showMostroSheet<void>(
  context: context,
  builder: (sheetContext) {
    final l10n = AppLocalizations.of(sheetContext);
    return MostroSheet(
      title: l10n.pwaInstallStepsTitle,
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _Step(icon: Icons.ios_share_outlined, text: l10n.pwaInstallStepShare),
          const SizedBox(height: 14),
          _Step(icon: Icons.add_box_outlined, text: l10n.pwaInstallStepAdd),
        ],
      ),
      primary: ModalAction(
        label: l10n.pwaInstallStepsDone,
        onPressed: () => Navigator.of(sheetContext).pop(),
      ),
    );
  },
);

/// One step: the icon the user looks for in Safari, then what to do.
class _Step extends StatelessWidget {
  const _Step({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final book = OrderBookPalette.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 20, color: book.limeIcon),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            text,
            style: TextStyle(fontSize: 14, height: 1.45, color: book.textBody),
          ),
        ),
      ],
    );
  }
}

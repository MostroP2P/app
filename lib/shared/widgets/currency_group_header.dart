import 'package:flutter/material.dart';

import 'package:mostro/core/order_book_palette.dart';
import 'package:mostro/l10n/app_localizations.dart';

/// The group header above the stablecoins in a currency picker (the
/// create-order picker, the default currency in Settings, the order book
/// filter): a caps meta label, as the guide's 11-sp group headers.
class StablecoinsGroupHeader extends StatelessWidget {
  const StablecoinsGroupHeader({super.key, this.padding});

  /// Defaults to a 12 top inset and a 4 bottom one, which separate the group
  /// from the last fiat row in a list.
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    final book = OrderBookPalette.of(context);
    return Padding(
      padding: padding ?? const EdgeInsets.only(top: 12, bottom: 4),
      child: Text(
        AppLocalizations.of(context).stablecoinsGroupHeader.toUpperCase(),
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.6,
          color: book.textTertiary,
        ),
      ),
    );
  }
}

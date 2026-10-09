import 'package:flutter/material.dart';

import 'package:mostro/core/app_theme.dart';
import 'package:mostro/core/invoice_palette.dart';

/// A note that explains what a step does with the user's sats (DS-CMP-25):
/// an escrow, a hold, a deposit. It sits in the body after what it explains,
/// never in an action bar. The lock, the default [icon], always means "your
/// sats are held".
class ExplanatoryNote extends StatelessWidget {
  /// A note of plain [text].
  const ExplanatoryNote({
    super.key,
    required String this.text,
    this.icon = Icons.lock_outline,
  }) : spans = null;

  /// A note whose sentence carries its own styled runs.
  const ExplanatoryNote.rich({
    super.key,
    required List<InlineSpan> this.spans,
    this.icon = Icons.lock_outline,
  }) : text = null;

  final String? text;
  final List<InlineSpan>? spans;
  final IconData icon;

  static const double _radius = 12;
  static const double _iconSize = 14;

  @override
  Widget build(BuildContext context) {
    final book = OrderBookPalette.of(context);
    final pal = InvoicePalette.of(context);
    final style = TextStyle(
      fontSize: 11,
      height: 1.45,
      color: book.textSecondary,
    );
    final spans = this.spans;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: pal.subtleFill,
        borderRadius: BorderRadius.circular(_radius),
        border: Border.all(color: pal.subtleBorder),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Icon(icon, size: _iconSize, color: pal.icon),
          ),
          const SizedBox(width: 8),
          Expanded(
            child:
                spans == null
                    ? Text(text!, style: style)
                    : Text.rich(TextSpan(children: spans), style: style),
          ),
        ],
      ),
    );
  }
}

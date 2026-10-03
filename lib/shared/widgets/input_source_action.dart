import 'package:flutter/material.dart';

import 'package:mostro/core/app_theme.dart';
import 'package:mostro/core/settings_palette.dart';

/// `Paste` and `Scan QR` under a field that takes a pasted or scanned value
/// (the NWC wallet, handoff 10c; the Cashu wallet): same shape, different
/// weight — [accent] carries the lime tint of the path the user is meant to
/// take.
class InputSourceAction extends StatelessWidget {
  const InputSourceAction({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
    this.accent = false,
  });

  final IconData icon;
  final String label;

  /// Null disables the action: neutral, in the faint ink, whatever [accent]
  /// says — a lime tint on something that cannot be pressed reads as a go.
  final VoidCallback? onTap;
  final bool accent;

  @override
  Widget build(BuildContext context) {
    final book = OrderBookPalette.of(context);
    final pal = SettingsPalette.of(context);
    final enabled = onTap != null;
    final lime = accent && enabled;
    final ink =
        !enabled
            ? book.textFaint
            : lime
            ? book.limeInk
            : book.textBody;
    return Semantics(
      button: true,
      enabled: enabled,
      child: Material(
        color: lime ? pal.scanFill : pal.buttonFill,
        borderRadius: const BorderRadius.all(Radius.circular(14)),
        child: InkWell(
          onTap: onTap,
          borderRadius: const BorderRadius.all(Radius.circular(14)),
          child: Container(
            decoration: BoxDecoration(
              borderRadius: const BorderRadius.all(Radius.circular(14)),
              border: Border.all(
                color: lime ? pal.scanBorder : pal.buttonBorder,
              ),
            ),
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, size: 14, color: ink),
                const SizedBox(width: 6),
                // Half a 360 px screen is tight for `Escanear QR` and tighter
                // for the longer translations: ellipsize rather than overflow.
                Flexible(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: lime ? FontWeight.w600 : FontWeight.w500,
                      color: ink,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

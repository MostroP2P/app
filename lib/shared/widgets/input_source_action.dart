import 'package:flutter/material.dart';

import 'package:mostro/core/app_theme.dart';
import 'package:mostro/core/settings_palette.dart';

/// `Paste` and `Scan QR` under a field that takes a pasted or scanned value
/// on a screen (the NWC wallet, handoff 10c; the QR scanner's paste form):
/// same shape, different weight — [accent] carries the lime tint of the path
/// the user is meant to take. Inside a modal they are `ModalLink`s instead
/// (DS-CMP-1), as in the Cashu wallet's dialogs.
class InputSourceAction extends StatelessWidget {
  const InputSourceAction({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
    this.accent = false,
    this.tooltip,
  });

  final IconData icon;
  final String label;

  /// Null disables the action: neutral, in the faint ink, whatever [accent]
  /// says — a lime tint on something that cannot be pressed reads as a go.
  final VoidCallback? onTap;
  final bool accent;

  /// Shown on hover or long press, and read by screen readers: why a
  /// disabled action cannot be used.
  final String? tooltip;

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
    // DS-A11Y-1: the node is named by [label] itself, not by whatever text
    // sits inside it, which is excluded so it is not read twice.
    final action = Semantics(
      button: true,
      enabled: enabled,
      label: label,
      child: Material(
        color: lime ? pal.scanFill : pal.buttonFill,
        borderRadius: const BorderRadius.all(Radius.circular(14)),
        child: InkWell(
          onTap: onTap,
          borderRadius: const BorderRadius.all(Radius.circular(14)),
          child: Container(
            // DS-CMP-6: the padding and a 13 sp label alone come to 46 dp.
            constraints: const BoxConstraints(minHeight: 48),
            decoration: BoxDecoration(
              borderRadius: const BorderRadius.all(Radius.circular(14)),
              border: Border.all(
                color: lime ? pal.scanBorder : pal.buttonBorder,
              ),
            ),
            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
            // Half a 320 dp screen is tight for `Escanear QR`, and German at
            // a large text size does not fit at all: one line, shrunk to fit,
            // rather than cutting or wrapping the label (DS-TYP-7, DS-L10N-2).
            child: Center(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(icon, size: 14, color: ink),
                    const SizedBox(width: 6),
                    ExcludeSemantics(
                      child: Text(
                        label,
                        maxLines: 1,
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
        ),
      ),
    );
    if (tooltip == null) return action;
    return Tooltip(message: tooltip, child: action);
  }
}

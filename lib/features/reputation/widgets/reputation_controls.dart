import 'package:flutter/material.dart';

import 'package:mostro/core/app_theme.dart';
import 'package:mostro/core/settings_palette.dart';

const _shape = RoundedRectangleBorder(
  borderRadius: BorderRadius.all(Radius.circular(16)),
);
const _label = TextStyle(
  fontFamily: AppFonts.ui,
  fontSize: 15,
  fontWeight: FontWeight.w600,
);

/// The reputation screens' main action: lime, radius 16 (DS-CMP-3), styled
/// like the NWC connect button.
class ReputationPrimaryButton extends StatelessWidget {
  const ReputationPrimaryButton({
    super.key,
    required this.label,
    required this.onPressed,
  });

  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final book = OrderBookPalette.of(context);
    final pal = SettingsPalette.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: const BorderRadius.all(Radius.circular(16)),
        boxShadow: onPressed != null ? pal.ctaShadow : const [],
      ),
      child: FilledButton(
        onPressed: onPressed,
        style: FilledButton.styleFrom(
          backgroundColor: book.lime,
          foregroundColor: book.onLime,
          disabledBackgroundColor: pal.ctaDisabledBg,
          disabledForegroundColor: pal.ctaDisabledInk,
          minimumSize: const Size.fromHeight(50),
          shape: _shape,
          textStyle: _label,
        ),
        child: Text(label),
      ),
    );
  }
}

/// A secondary action: outlined in the palette's border, radius 16 (DS-CMP-4).
class ReputationSecondaryButton extends StatelessWidget {
  const ReputationSecondaryButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final book = OrderBookPalette.of(context);
    final style = OutlinedButton.styleFrom(
      foregroundColor: book.textPrimary,
      side: BorderSide(color: book.border),
      minimumSize: const Size.fromHeight(50),
      shape: _shape,
      textStyle: _label,
    );
    final icon = this.icon;
    if (icon == null) {
      return OutlinedButton(
        onPressed: onPressed,
        style: style,
        child: Text(label),
      );
    }
    return OutlinedButton.icon(
      onPressed: onPressed,
      style: style,
      icon: Icon(icon, size: 18),
      label: Text(label),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:mostro/core/app_theme.dart';
import 'package:mostro/core/automation/automation_id.dart';
import 'package:mostro/core/settings_palette.dart';
import 'package:mostro/features/settings/models/settings_rows.dart';

/// Building blocks of the settings redesign (handoff 10a–10e): the group card
/// with its uppercase header, the setting row whose right-hand value carries
/// the state, the toggle that replaces Material's switch, and the footnote.

const _cardRadius = BorderRadius.all(Radius.circular(18));

/// Gap between one group and the next.
const double settingsGroupGap = 16;

// ── Group ─────────────────────────────────────────────────────────────────────

/// An uppercase header and a card holding [rows], separated by hairlines.
///
/// Nine same-sized cards became four groups: the whole of 10a fits on one
/// screen, and a header says what its rows have in common.
class SettingsGroup extends StatelessWidget {
  const SettingsGroup({super.key, this.header, required this.rows});

  /// `APLICACIÓN`, `PAGOS`, … Omitted by the screens that show a single
  /// unlabelled card (10b's relay list, 10d's events).
  final String? header;

  final List<Widget> rows;

  @override
  Widget build(BuildContext context) {
    final book = OrderBookPalette.of(context);
    final pal = SettingsPalette.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (header != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(2, 4, 2, 10),
            child: Text(
              header!.toUpperCase(),
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w600,
                letterSpacing: 1.0,
                color: pal.groupHeader,
              ),
            ),
          ),
        DecoratedBox(
          decoration: BoxDecoration(
            color: book.surface,
            borderRadius: _cardRadius,
            border: Border.all(color: book.border),
          ),
          child: Column(
            children: [
              for (var i = 0; i < rows.length; i++)
                DecoratedBox(
                  decoration: BoxDecoration(
                    border:
                        i == rows.length - 1
                            ? null
                            : Border(bottom: BorderSide(color: pal.rowDivider)),
                  ),
                  child: rows[i],
                ),
            ],
          ),
        ),
      ],
    );
  }
}

// ── Row ───────────────────────────────────────────────────────────────────────

/// One setting: icon, label, the current value flush right, and a chevron.
///
/// The value replaces the old subtitle, which repeated the title
/// (`Relays · Administrar conexiones de relay`). It is what the user came to
/// see, and its [tone] is the only place the list can warn from.
class SettingsRow extends StatelessWidget {
  const SettingsRow({
    super.key,
    required this.icon,
    required this.label,
    this.value,
    this.tone = SettingsValueTone.neutral,
    this.valueIsData = false,
    this.trailing,
    this.onTap,
    this.semanticValue,
    this.valueAutomationId,
  });

  final IconData icon;
  final String label;

  /// `Español`, `3 de 4 conectados`, `Sin conectar`. Null leaves the chevron
  /// alone on the row.
  final String? value;

  final SettingsValueTone tone;

  /// Keys and URLs are set in Manrope, so they line up from row to row.
  final bool valueIsData;

  /// Replaces the chevron — a toggle on 10b and 10d.
  final Widget? trailing;

  final VoidCallback? onTap;

  /// What a screen reader reads in place of an abbreviated visible value —
  /// a truncated key, a URL without its scheme.
  final String? semanticValue;

  /// Names the value as a state readout for automation, which compares the
  /// full [semanticValue] rather than the localized label or the truncation
  /// the row shows. See `docs/automation-contract.md`.
  final String? valueAutomationId;

  @override
  Widget build(BuildContext context) {
    final book = OrderBookPalette.of(context);
    final pal = SettingsPalette.of(context);
    final valueColor = switch (tone) {
      SettingsValueTone.neutral => book.textMuted,
      SettingsValueTone.good => book.limeInk,
      SettingsValueTone.warn => pal.warnInk,
    };

    final content = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
      child: Row(
        children: [
          Icon(icon, size: 16, color: book.textTertiary),
          const SizedBox(width: 11),
          // The label takes the width it needs up to two lines; the value
          // drops to the next line, still flush right, when both cannot fit.
          Expanded(
            child: Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 11,
              runSpacing: 2,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: book.textStrong,
                  ),
                ),
                if (value != null)
                  _maybeNamed(
                    Text(
                      value!,
                      semanticsLabel: semanticValue,
                      style: TextStyle(
                        fontFamily:
                            valueIsData ? AppFonts.figures : AppFonts.ui,
                        fontSize: 12,
                        fontWeight:
                            valueIsData ? FontWeight.w500 : FontWeight.w400,
                        color: valueColor,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          if (trailing != null) ...[
            const SizedBox(width: 11),
            trailing!,
          ] else if (onTap != null) ...[
            const SizedBox(width: 11),
            Icon(Icons.chevron_right, size: 15, color: pal.dotOffline),
          ],
        ],
      ),
    );

    // No container label here: the label and value Texts announce themselves,
    // and a container would read the row twice. `semanticValue` rides on the
    // value Text instead.
    final row =
        onTap == null
            ? content
            : InkWell(
              // The whole row is the target, and the ink follows the card's
              // corners on the first and last row of a group.
              onTap: () {
                HapticFeedback.selectionClick();
                onTap!();
              },
              borderRadius: _cardRadius,
              child: content,
            );
    return Material(type: MaterialType.transparency, child: row);
  }

  /// Names the value as a readout when an identifier was given; returns it
  /// untouched otherwise, so rows without one keep their exact widget tree.
  Widget _maybeNamed(Widget child) =>
      valueAutomationId == null
          ? child
          : child.withAutomationId(valueAutomationId!, label: semanticValue);
}

// ── Toggle ────────────────────────────────────────────────────────────────────

/// The redesign's toggle: 40 × 23, lime-tinted and bordered when on.
///
/// Replaces the Material switch, whose olive thumb on green track read the
/// same off as on at a glance.
class MostroToggle extends StatelessWidget {
  const MostroToggle({
    super.key,
    required this.value,
    required this.onChanged,
    this.semanticLabel,
  });

  final bool value;

  /// Null disables the toggle — 10d's rows when the system permission is off.
  final ValueChanged<bool>? onChanged;

  final String? semanticLabel;

  static const _duration = Duration(milliseconds: 160);

  @override
  Widget build(BuildContext context) {
    final pal = SettingsPalette.of(context);
    return Semantics(
      label: semanticLabel,
      toggled: value,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap:
            onChanged == null
                ? null
                : () {
                  HapticFeedback.selectionClick();
                  onChanged!(!value);
                },
        child: AnimatedContainer(
          duration: _duration,
          curve: Curves.easeOut,
          width: 40,
          height: 23,
          padding: const EdgeInsets.symmetric(horizontal: 2),
          decoration: BoxDecoration(
            color: value ? pal.toggleOnBg : pal.toggleOffBg,
            borderRadius: const BorderRadius.all(Radius.circular(999)),
            border: Border.all(
              color: value ? pal.toggleOnBorder : pal.toggleOffBorder,
            ),
          ),
          alignment: value ? Alignment.centerRight : Alignment.centerLeft,
          child: AnimatedContainer(
            duration: _duration,
            curve: Curves.easeOut,
            width: 17,
            height: 17,
            decoration: BoxDecoration(
              color: value ? pal.toggleOnThumb : pal.toggleOffThumb,
              shape: BoxShape.circle,
            ),
          ),
        ),
      ),
    );
  }
}

// ── Footnote ──────────────────────────────────────────────────────────────────

/// The sentence below a card that answers what the screen leaves unsaid — why
/// two relays matter, where the NWC URI is stored, what a push does not carry.
class SettingsFootnote extends StatelessWidget {
  const SettingsFootnote({super.key, required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final book = OrderBookPalette.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 1),
            child: Icon(icon, size: 13, color: book.textTertiary),
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                fontSize: 11,
                height: 1.5,
                color: book.textTertiary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

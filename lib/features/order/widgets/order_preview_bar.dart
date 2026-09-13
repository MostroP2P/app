import 'package:flutter/material.dart';

import 'package:mostro/core/app_theme.dart';
import 'package:mostro/core/automation/automation_id.dart';
import 'package:mostro/core/automation/automation_ids.dart';
import 'package:mostro/core/create_order_palette.dart';
import 'package:mostro/features/order/models/create_order_rules.dart';
import 'package:mostro/l10n/app_localizations.dart';

/// Bottom bar of the create-order screen: the live preview line pinned above
/// `Cancel` and `Publish order`, always visible and rising with the
/// keyboard.
///
/// The line has three states: the hint while there is no amount, the
/// sentence once there is, and — in place of the sentence — a validation
/// [error] in coral. It reserves two lines of height so none of them shifts
/// the buttons.
class OrderPreviewBar extends StatelessWidget {
  const OrderPreviewBar({
    super.key,
    required this.fragments,
    required this.error,
    this.notice,
    required this.premiumFavour,
    required this.canSubmit,
    required this.isSubmitting,
    required this.onCancel,
    required this.onSubmit,
  });

  /// The sentence, or null while there is no amount to describe.
  final List<PreviewFragment>? fragments;
  final String? error;

  /// A sentence worth reading before the tap that is not an error (the
  /// node's maker deposit); shown under the preview line.
  final String? notice;

  /// Colours the premium fragment with the same rule as the premium block.
  final PremiumFavour premiumFavour;
  final bool canSubmit;
  final bool isSubmitting;
  final VoidCallback onCancel;
  final VoidCallback onSubmit;

  static const _fade = Duration(milliseconds: 100);

  @override
  Widget build(BuildContext context) {
    final palette = OrderBookPalette.of(context);
    final create = CreateOrderPalette.of(context);
    final l10n = AppLocalizations.of(context);

    return DecoratedBox(
      decoration: BoxDecoration(
        color: palette.surfaceNav,
        border: Border(top: BorderSide(color: palette.navBorder)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 12, 18, 18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 36),
                child: AnimatedSwitcher(
                  duration: _fade,
                  child: _line(context, palette, create, l10n),
                ),
              ),
              if (notice case final notice? when error == null) ...[
                const SizedBox(height: 6),
                _IconLine(
                  key: const ValueKey('preview-notice'),
                  icon: Icons.shield_outlined,
                  iconColor: palette.textFaint,
                  child: Text(
                    notice,
                    style: TextStyle(
                      fontSize: 11,
                      height: 1.5,
                      color: palette.textTertiary,
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    flex: 10,
                    child: OutlinedButton(
                      onPressed: onCancel,
                      style: OutlinedButton.styleFrom(
                        foregroundColor: palette.textBody,
                        side: BorderSide(color: create.fieldUnderline),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                        textStyle: const TextStyle(
                          fontFamily: AppFonts.ui,
                          fontSize: 15,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      child: Text(l10n.cancel),
                    ).withAutomationId(AutomationIds.orderCreateCancel),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    flex: 14,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(16),
                        boxShadow:
                            canSubmit && !isSubmitting
                                ? create.ctaShadow
                                : const [],
                      ),
                      child: FilledButton(
                        onPressed: canSubmit && !isSubmitting ? onSubmit : null,
                        style: FilledButton.styleFrom(
                          backgroundColor: palette.lime,
                          foregroundColor: palette.onLime,
                          disabledBackgroundColor: create.ctaDisabledBg,
                          disabledForegroundColor: create.ctaDisabledInk,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                          textStyle: const TextStyle(
                            fontFamily: AppFonts.ui,
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        child:
                            isSubmitting
                                ? SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: palette.onLime,
                                  ),
                                )
                                : Text(l10n.publishOrder),
                      ),
                    ).withAutomationId(AutomationIds.orderCreateSubmit),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _line(
    BuildContext context,
    OrderBookPalette palette,
    CreateOrderPalette create,
    AppLocalizations l10n,
  ) {
    final error = this.error;
    if (error != null) {
      return _IconLine(
        key: const ValueKey('preview-error'),
        icon: Icons.info_outline,
        iconColor: create.error,
        child: Text(
          error,
          style: TextStyle(fontSize: 12, height: 1.5, color: create.error),
        ),
      );
    }

    final fragments = this.fragments;
    if (fragments == null) {
      return _IconLine(
        key: const ValueKey('preview-hint'),
        icon: Icons.info_outline,
        iconColor: palette.textFaint,
        child: Text(
          l10n.previewHintNoAmount,
          style: TextStyle(
            fontSize: 12,
            height: 1.5,
            color: palette.textTertiary,
          ),
        ),
      );
    }

    final premiumColor = switch (premiumFavour) {
      PremiumFavour.good => create.premiumGoodValue,
      PremiumFavour.bad => create.premiumBadValue,
      PremiumFavour.zero => create.premiumZeroValue,
    };
    final base = TextStyle(fontSize: 12, height: 1.5, color: palette.textMuted);
    TextStyle figure(Color color) => base.copyWith(
          fontFamily: AppFonts.figures,
          fontWeight: FontWeight.w600,
          color: color,
        );

    return _IconLine(
      key: const ValueKey('preview-sentence'),
      icon: Icons.check,
      iconColor: palette.limeText,
      child: Text.rich(
        TextSpan(
          style: base,
          children: [
            for (final fragment in fragments)
              TextSpan(
                text: fragment.text,
                style: switch (fragment.role) {
                  PreviewRole.text => null,
                  PreviewRole.amount => figure(palette.textPrimary),
                  PreviewRole.sats => figure(palette.limeInk),
                  PreviewRole.premium => figure(premiumColor),
                  PreviewRole.duration => figure(palette.textBody),
                },
              ),
          ],
        ),
      ),
    );
  }
}

class _IconLine extends StatelessWidget {
  const _IconLine({
    super.key,
    required this.icon,
    required this.iconColor,
    required this.child,
  });

  final IconData icon;
  final Color iconColor;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 2),
          child: Icon(icon, size: 14, color: iconColor),
        ),
        const SizedBox(width: 9),
        Expanded(child: child),
      ],
    );
  }
}

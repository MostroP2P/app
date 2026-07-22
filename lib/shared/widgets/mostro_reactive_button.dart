import 'package:flutter/material.dart';

import 'package:mostro/core/app_theme.dart';
import 'package:mostro/l10n/app_localizations.dart';

enum MostroButtonVariant { primary, destructive }

/// Thrown by an onPressed handler when the user aborts before any work
/// starts, for example declining a confirmation dialog. Not a failure.
class MostroActionAborted implements Exception {
  const MostroActionAborted();
}

/// Button that shows a spinner while waiting, then a success check.
class MostroReactiveButton extends StatefulWidget {
  const MostroReactiveButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.variant = MostroButtonVariant.primary,
    this.icon,
    this.onError,
    this.outlined = false,
  });

  final String label;
  final Future<void> Function() onPressed;

  final MostroButtonVariant variant;
  final IconData? icon;
  final void Function(Object error)? onError;
  final bool outlined;

  @override
  State<MostroReactiveButton> createState() => _MostroReactiveButtonState();
}

enum _ButtonState { idle, loading, success, cooldown }

class _MostroReactiveButtonState extends State<MostroReactiveButton> {
  _ButtonState _state = _ButtonState.idle;

  static const _kSuccessDisplay = Duration(milliseconds: 1500);

  /// Matches SnackBar's default display duration, so the button re-enables
  /// as the failure message disappears.
  static const _kErrorCooldown = Duration(seconds: 4);

  Future<void> _handlePress() async {
    if (_state != _ButtonState.idle) return;
    setState(() => _state = _ButtonState.loading);

    try {
      await widget.onPressed();
      if (!mounted) return;
      setState(() => _state = _ButtonState.success);

      await Future.delayed(_kSuccessDisplay);
      if (mounted) setState(() => _state = _ButtonState.idle);
    } on MostroActionAborted {
      if (mounted) setState(() => _state = _ButtonState.idle);
    } catch (e) {
      widget.onError?.call(e);
      if (!mounted) return;
      setState(() => _state = _ButtonState.cooldown);

      await Future.delayed(_kErrorCooldown);
      if (mounted) setState(() => _state = _ButtonState.idle);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppColors>();
    final green = colors?.mostroGreen ?? const Color(0xFF8CC63F);
    final destructiveRed = colors?.destructiveRed ?? const Color(0xFFD84D4D);
    final accent = switch (widget.variant) {
      MostroButtonVariant.primary => green,
      MostroButtonVariant.destructive => destructiveRed,
    };

    if (widget.outlined) {
      return OutlinedButton(
        onPressed: _state == _ButtonState.idle ? _handlePress : null,
        style: OutlinedButton.styleFrom(
          side: BorderSide(color: accent),
          foregroundColor: accent,
          minimumSize: const Size(0, 48),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.button),
          ),
        ),
        child: _buildChild(),
      );
    }

    return FilledButton(
      onPressed: _state == _ButtonState.idle ? _handlePress : null,
      style: FilledButton.styleFrom(
        backgroundColor: accent,
        foregroundColor: Colors.black,
        minimumSize: const Size(0, 48),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.button),
        ),
      ),
      child: _buildChild(),
    );
  }

  Widget _buildChild() {
    switch (_state) {
      case _ButtonState.loading:
        return Semantics(
          label: AppLocalizations.of(context).loading,
          liveRegion: true,
          child: const SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        );
      case _ButtonState.success:
        return Semantics(
          label: AppLocalizations.of(context).successLabel,
          liveRegion: true,
          child: const Icon(Icons.check, size: 20),
        );
      case _ButtonState.idle:
        return _buildLabel();
      case _ButtonState.cooldown:
        // No visual error styling — the SnackBar already reported the
        // failure. This announcement keeps the state change perceivable to
        // screen-reader users, who would otherwise get no signal at all
        // while the button sits disabled for the cooldown.
        return Semantics(
          liveRegion: true,
          label: AppLocalizations.of(context).actionFailedAnnouncement,
          child: _buildLabel(),
        );
    }
  }

  Widget _buildLabel() {
    if (widget.icon != null) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(widget.icon, size: 18),
          const SizedBox(width: AppSpacing.sm),
          Flexible(
            child: Text(
              widget.label,
              maxLines: 2,
              textAlign: TextAlign.center,
              softWrap: true,
            ),
          ),
        ],
      );
    }
    return Text(
      widget.label,
      maxLines: 2,
      textAlign: TextAlign.center,
      softWrap: true,
    );
  }
}

import 'package:flutter/material.dart';

import 'package:mostro/core/app_theme.dart';

enum MostroButtonVariant { primary, destructive }

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

enum _ButtonState { idle, loading, success, error }

class _MostroReactiveButtonState extends State<MostroReactiveButton> {
  _ButtonState _state = _ButtonState.idle;

  Future<void> _handlePress() async {
    if (_state != _ButtonState.idle) return;
    setState(() => _state = _ButtonState.loading);

    try {
      await widget.onPressed();
      if (!mounted) return;
      setState(() => _state = _ButtonState.success);

      await Future.delayed(const Duration(milliseconds: 1500));
      if (mounted) setState(() => _state = _ButtonState.idle);
    } catch (e) {
      widget.onError?.call(e);
      if (!mounted) return;
      setState(() => _state = _ButtonState.error);

      await Future.delayed(const Duration(seconds: 4));
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
          label: 'Loading',
          liveRegion: true,
          child: const SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        );
      case _ButtonState.success:
        return Semantics(
          label: 'Success',
          liveRegion: true,
          child: const Icon(Icons.check, size: 20),
        );
      case _ButtonState.idle || _ButtonState.error:
        if (widget.icon != null) {
          return Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(widget.icon, size: 18),
              const SizedBox(width: AppSpacing.sm),
              Text(widget.label),
            ],
          );
        }
        return Text(widget.label);
    }
  }
}

import 'package:flutter/material.dart';

import 'package:mostro/core/app_theme.dart';

/// Button that shows a spinner while waiting for a Mostro response,
/// a success check on completion, and an error state on failure.
class MostroReactiveButton extends StatefulWidget {
  const MostroReactiveButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.backgroundColor,
    this.foregroundColor,
    this.icon,
    this.onError,
  });

  final String label;
  final Future<void> Function() onPressed;
  final Color? backgroundColor;
  final Color? foregroundColor;
  final IconData? icon;
  final void Function(Object error)? onError;

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

      await Future.delayed(const Duration(milliseconds: 2000));
      if (mounted) setState(() => _state = _ButtonState.idle);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppColors>();
    final green = colors?.mostroGreen ?? const Color(0xFF8CC63F);
    final bg = widget.backgroundColor ?? green;
    final fg = widget.foregroundColor ?? Colors.black;

    return FilledButton(
      onPressed: _state == _ButtonState.idle ? _handlePress : null,
      style: FilledButton.styleFrom(
        backgroundColor: _state == _ButtonState.error
            ? colors?.destructiveRed ?? const Color(0xFFD84D4D)
            : bg,
        foregroundColor: fg,
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
      case _ButtonState.error:
        return Semantics(
          label: 'Error',
          liveRegion: true,
          child: const Icon(Icons.error_outline, size: 20),
        );
      case _ButtonState.idle:
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

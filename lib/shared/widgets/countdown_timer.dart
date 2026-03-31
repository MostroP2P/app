import 'dart:async';

import 'package:flutter/material.dart';

import 'package:mostro/core/app_theme.dart';

/// Circular countdown timer widget.
///
/// Displays remaining time as "HH:MM:SS" centred inside a
/// [CircularProgressIndicator].  The progress arc transitions:
///   - green  (> 33 % remaining)
///   - yellow (10 %–33 % remaining)
///   - red    (≤ 10 % remaining or expired)
///
/// Used on the Take Order screen (order expiry) and Trade Detail screen
/// (trade step timeout).
class CountdownTimer extends StatefulWidget {
  const CountdownTimer({
    super.key,
    required this.duration,
    this.onExpired,
  });

  /// Total countdown duration.
  final Duration duration;

  /// Called once when the timer reaches zero.
  final VoidCallback? onExpired;

  @override
  State<CountdownTimer> createState() => _CountdownTimerState();
}

class _CountdownTimerState extends State<CountdownTimer> {
  late Duration _remaining;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _remaining = widget.duration;
    _start();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _start() {
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() {
        _remaining -= const Duration(seconds: 1);
        if (_remaining <= Duration.zero) {
          _remaining = Duration.zero;
          _timer?.cancel();
          widget.onExpired?.call();
        }
      });
    });
  }

  Color _color(AppColors colors) {
    final total = widget.duration.inSeconds;
    if (total == 0) return colors.destructiveRed;
    final ratio = _remaining.inSeconds / total;
    if (ratio > 0.33) return colors.mostroGreen;
    if (ratio > 0.10) return const Color(0xFFFFD700);
    return colors.destructiveRed;
  }

  String _label() {
    final d = _remaining.isNegative ? Duration.zero : _remaining;
    final h = d.inHours.toString().padLeft(2, '0');
    final m = (d.inMinutes % 60).toString().padLeft(2, '0');
    final s = (d.inSeconds % 60).toString().padLeft(2, '0');
    return '$h:$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppColors>();
    if (colors == null) {
      throw StateError('AppColors theme extension must be registered');
    }
    final total = widget.duration.inSeconds;
    final progress = total > 0 ? _remaining.inSeconds / total : 0.0;

    return SizedBox(
      width: 80,
      height: 80,
      child: Stack(
        alignment: Alignment.center,
        children: [
          CircularProgressIndicator(
            value: progress.clamp(0.0, 1.0),
            strokeWidth: 5,
            backgroundColor: colors.backgroundCard,
            valueColor: AlwaysStoppedAnimation<Color>(_color(colors)),
          ),
          Text(
            _label(),
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  fontFamily: 'monospace',
                  fontWeight: FontWeight.w600,
                ),
          ),
        ],
      ),
    );
  }
}

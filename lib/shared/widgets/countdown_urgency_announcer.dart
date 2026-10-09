import 'package:flutter/semantics.dart';
import 'package:flutter/widgets.dart';

/// Says [message] once, the moment its countdown turns [urgent] on screen
/// (DS-CMP-21, DS-A11Y-2).
///
/// The figure itself is no live region: it changes every second, so a screen
/// reader would read each tick. A countdown already urgent when first shown
/// is not announced; its label is read on focus, and announcing on every
/// mount would repeat it whenever a list or a screen rebuilds.
class CountdownUrgencyAnnouncer extends StatefulWidget {
  const CountdownUrgencyAnnouncer({
    super.key,
    required this.urgent,
    required this.message,
    required this.child,
  });

  /// Whether the countdown reads urgent (`countdownTone`).
  final bool urgent;

  /// The label with the time left, as the screen shows it.
  final String message;

  final Widget child;

  @override
  State<CountdownUrgencyAnnouncer> createState() =>
      _CountdownUrgencyAnnouncerState();
}

class _CountdownUrgencyAnnouncerState extends State<CountdownUrgencyAnnouncer> {
  @override
  void didUpdateWidget(CountdownUrgencyAnnouncer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.urgent && !oldWidget.urgent) {
      SemanticsService.sendAnnouncement(
        View.of(context),
        widget.message,
        Directionality.of(context),
      );
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

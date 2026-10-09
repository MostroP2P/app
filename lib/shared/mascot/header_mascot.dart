import 'dart:async';

import 'package:flutter/material.dart' hide ConnectionState;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:mostro/shared/mascot/mascot_cues.dart';
import 'package:mostro/shared/mascot/mostro_mascot.dart';
import 'package:mostro/shared/mascot/mostro_mood.dart';
import 'package:mostro/shared/providers/connection_state_provider.dart';
import 'package:mostro/src/rust/api/types.dart' show ConnectionState;

/// The Mostro in every tab's app bar: tap it and it reacts, and it picks up
/// the mood of the app around it.
///
/// v1 hid an easter egg in the order book's logo, so this is where v2 keeps
/// its own, now in all three tabs so the bar does not change as the user
/// moves between them (#770). The tab hands in whether it is [waiting]; the
/// trade steps and app events arrive as cues ([mascotCueProvider]), taken
/// only while this mascot is on screen; and an outage longer than
/// [mostroOfflineGrace] scares it until a relay is back. When several apply,
/// [pickMood] decides.
class HeaderMascot extends ConsumerStatefulWidget {
  const HeaderMascot({super.key, this.waiting = false});

  /// Height of the artwork in the app bar.
  static const double height = 26;

  /// Whether the tab is waiting on something the user is watching (the
  /// order book's first load). Kept up long enough, Mostro shuffles.
  final bool waiting;

  @override
  ConsumerState<HeaderMascot> createState() => _HeaderMascotState();
}

class _HeaderMascotState extends ConsumerState<HeaderMascot> {
  /// How long a tab may wait before Mostro starts shuffling.
  static const Duration _patienceRunsOut = Duration(seconds: 6);

  Timer? _patience;
  Timer? _outage;
  Timer? _hold;
  bool _impatient = false;
  bool _offline = false;

  /// The cue on show, while it lasts ([mostroCueHold]).
  MostroMood? _cue;

  /// Whether the user is looking at this mascot: its tickers run (no opaque
  /// route covers the tab) and its route is the current one (no dialog over
  /// it, and not the page a navigation is leaving).
  bool _visible = false;

  @override
  void initState() {
    super.initState();
    ref.listenManual(
      connectionStateProvider,
      (_, next) => _syncConnection(next.valueOrNull),
      fireImmediately: true,
    );
    ref.listenManual(mascotCueProvider, (_, next) {
      if (next != null) scheduleMicrotask(_takeCue);
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final visible =
        TickerMode.valuesOf(context).enabled &&
        (ModalRoute.of(context)?.isCurrent ?? true);
    if (visible && !_visible) scheduleMicrotask(_takeCue);
    _visible = visible;
  }

  @override
  void dispose() {
    _patience?.cancel();
    _outage?.cancel();
    _hold?.cancel();
    super.dispose();
  }

  /// Starts the clock while the tab waits and stops it when the wait ends.
  /// Never calls `setState` itself: it runs from `build`, and the timer's
  /// callback does not.
  void _syncPatience(bool waiting) {
    if (waiting) {
      _patience ??= Timer(_patienceRunsOut, () {
        if (mounted) setState(() => _impatient = true);
      });
      return;
    }
    _patience?.cancel();
    _patience = null;
    if (!_impatient) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(() => _impatient = false);
    });
  }

  /// Scared once the relays have been out of reach for the grace period;
  /// calm, and ready for the cue that waited, as soon as one is back. An
  /// unknown state (no pool yet) is not an outage.
  void _syncConnection(ConnectionState? state) {
    if (state != null && isDisconnected(state)) {
      _outage ??= Timer(mostroOfflineGrace, () {
        if (mounted) setState(() => _offline = true);
      });
      return;
    }
    _outage?.cancel();
    _outage = null;
    if (!_offline) return;
    setState(() => _offline = false);
    scheduleMicrotask(_takeCue);
  }

  /// Shows the waiting cue, if this mascot is on screen to show it.
  ///
  /// Out of sight, or scared by an outage, the cue stays where it is and
  /// waits.
  void _takeCue() {
    if (!mounted || !_visible || _offline) return;
    final mood = ref.read(mascotCueProvider.notifier).take();
    if (mood == null) return;
    final showing = _cue;
    // The same step told twice (a local write, then the daemon's echo) is
    // already on show; a weaker one would be over by the time it is.
    if (showing == mood) return;
    if (showing != null && pickMood([showing, mood]) != mood) return;
    _hold?.cancel();
    setState(() => _cue = mood);
    _hold = Timer(mostroCueHold, () {
      if (mounted) setState(() => _cue = null);
    });
  }

  @override
  Widget build(BuildContext context) {
    _syncPatience(widget.waiting);

    final mood = pickMood([
      if (_impatient) MostroMood.impatient,
      if (_cue case final cue?) cue,
      if (_offline) MostroMood.offline,
    ]);

    return MostroMascot(
      height: HeaderMascot.height,
      mood: mood,
      interactive: true,
    );
  }
}

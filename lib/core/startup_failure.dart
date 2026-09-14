import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Painted instead of the app when startup fails before it can be.
///
/// Deliberately dependency-free: no localization, no app theme, no Rust, no
/// SharedPreferences. Any of those can be the thing that failed, and a rescue
/// surface that needs what broke is a second blank page (#227, #389).
///
/// [step] names the startup step that threw, phrased to read inside the
/// sentence below ("It failed while loading the engine."). That name is the
/// whole point of this screen: "Mostro won't open" is unactionable, "it failed
/// loading the engine" is a starting point — both for the person reporting it
/// and for whoever reads the report.
class StartupFailureApp extends StatelessWidget {
  const StartupFailureApp({super.key, required this.step, this.error});

  final String step;

  /// What was thrown, rendered as a second, selectable line.
  ///
  /// On Android, iOS and Linux there is no console for the person hitting this
  /// to read, so the step name alone is all they could report. Selectable so it
  /// can be copied into that report, and capped so a runaway toString does not
  /// bury the sentence above it — the screen scrolls, but the first thing on it
  /// should still be the one line that says what failed.
  final Object? error;

  static const int _maxErrorChars = 300;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      // On the web the initial route is the browser's URL, and a startup
      // failure is usually met on a reload of some deep path. Flutter's default
      // handling walks that path segment by segment and pushes one route per
      // segment, so `/orders/abc/detail` answered by `onGenerateRoute` alone
      // stacks four identical copies of this screen: `canPop()` is true and
      // browser or Android back "navigates" to a clone. Returning the list
      // directly yields exactly one route for any URL (#405 review).
      //
      // `onGenerateRoute` still has to be here — MaterialApp requires a way to
      // build routes for anything after the first, and refuses to construct
      // without one.
      onGenerateInitialRoutes:
          (_) => [MaterialPageRoute<void>(builder: _buildBody)],
      onGenerateRoute: (_) => MaterialPageRoute<void>(builder: _buildBody),
    );
  }

  /// Both lines as one block, so a pasted report carries the step as well as
  /// the cause. The cause alone loses half of what makes it actionable.
  String _report() {
    final cause = error == null ? '' : '\n${_shortError(error!)}';
    return 'Mostro could not start: $step$cause';
  }

  static String _shortError(Object error) {
    final text = error.toString();
    return text.length <= _maxErrorChars
        ? text
        : '${text.substring(0, _maxErrorChars)}…';
  }

  Widget _buildBody(BuildContext context) {
    return Scaffold(
      // Hard-coded rather than taken from the app theme: the theme is built
      // from settings this screen exists to survive the loss of.
      backgroundColor: const Color(0xFF1D212C),
      body: Center(
        // Scrollable so a long cause on a short screen moves out of the way
        // instead of overflowing: an unhandled overflow paints the striped
        // warning over the top of this, which is the one screen that has to
        // stay readable when everything else has gone wrong.
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Mostro could not start',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'It failed while $step.',
                textAlign: TextAlign.center,
                style: const TextStyle(color: Color(0xFFB0B6C3), fontSize: 15),
              ),
              if (error != null) ...[
                const SizedBox(height: 20),
                SelectableText(
                  _shortError(error!),
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Color(0xFF7A8296),
                    fontSize: 12,
                  ),
                ),
              ],
              const SizedBox(height: 24),
              // A tap rather than a text selection: on a phone there is no
              // console and dragging to select inside a scrolling view is
              // fiddly, so the one action this screen offers is handing the
              // whole report over in a form that can be pasted into a message.
              TextButton.icon(
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: _report()));
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Copied'),
                      duration: Duration(seconds: 2),
                    ),
                  );
                },
                icon: const Icon(Icons.copy, size: 16),
                label: const Text('Copy details'),
                style: TextButton.styleFrom(
                  foregroundColor: const Color(0xFFB0B6C3),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

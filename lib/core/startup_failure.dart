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
    // Counted in characters, not UTF-16 units: cutting inside an emoji leaves
    // half of it, which renders as a replacement glyph (#405 review).
    final text = error.toString().characters;
    return text.length <= _maxErrorChars
        ? text.toString()
        : '${text.take(_maxErrorChars)}…';
  }

  Widget _buildBody(BuildContext context) {
    const muted = Color(0xFFB0B6C3);
    final cause =
        error == null
            ? null
            : SelectableText(
              _shortError(error!),
              textAlign: TextAlign.center,
              style: const TextStyle(
                // 5.3:1 on the background, above the 4.5:1 WCAG AA minimum for
                // small text: this is the line people read out.
                color: Color(0xFF8C94A8),
                fontSize: 12,
              ),
            );
    final sentence = Text(
      'It failed while $step.',
      textAlign: TextAlign.center,
      style: const TextStyle(color: muted, fontSize: 15),
    );

    final main = Column(
      children: [
        const Text(
          'Mostro could not start',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: Colors.white,
            fontSize: _titleSize,
            height: _titleLineHeight,
            fontWeight: FontWeight.w600,
          ),
        ),
        // Air under the title: one title line more than the base gap,
        // derived from the same numbers that size the title.
        const SizedBox(height: 12 + _titleSize * _titleLineHeight),
        if (cause != null) ...[sentence, const SizedBox(height: 8)],
        // The copy buttons sit next to what they copy — the cause when there
        // is one, otherwise the step — and in one shared column, so they line
        // up vertically. The link has its own: typing a URL off a failure
        // screen, often on a phone, is where a report gets abandoned.
        _copyTable(context, [
          ('Copy details', _report(), cause ?? sentence),
          (
            'Copy link',
            _issuesUrl,
            const Text(
              'Please report this at\ngithub.com/MostroP2P/app/issues',
              textAlign: TextAlign.center,
              style: TextStyle(color: muted, fontSize: 13),
            ),
          ),
        ]),
      ],
    );

    // Clearing app data is deliberately not suggested as a fix, and the reason
    // not to is spelled out: "it removes your account" does not say what that
    // costs, and the cost is what lets someone decide (#405 review).
    const footer = Padding(
      padding: EdgeInsets.only(top: 32),
      child: Text(
        'If you don\'t have your secret words, don\'t uninstall the app or '
        'clear its data: they are the only way back into your account, and '
        'without them you lose access to any open trade or dispute, and to '
        'your reputation.',
        textAlign: TextAlign.center,
        style: TextStyle(color: Color(0xFF8C94A8), fontSize: 12),
      ),
    );

    return Scaffold(
      // Hard-coded rather than taken from the app theme: the theme is built
      // from settings this screen exists to survive the loss of.
      backgroundColor: const Color(0xFF1D212C),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, viewport) {
            const vertical = 32.0;
            return SingleChildScrollView(
              // Scrollable so a long cause on a short screen moves out of the
              // way instead of overflowing: an unhandled overflow paints the
              // striped warning over the one screen that has to stay readable.
              //
              // Side padding grows on wide windows so lines stay at most 520
              // wide; a Center would drop the minimum height the footer needs.
              padding: EdgeInsets.symmetric(
                horizontal: ((viewport.maxWidth - 520) / 2).clamp(
                  24.0,
                  double.infinity,
                ),
                vertical: vertical,
              ),
              child: ConstrainedBox(
                // At least the screen's height, so the warning sits at the
                // bottom as a footer when there is room, and below everything
                // else when there is not.
                constraints: BoxConstraints(
                  minHeight: (viewport.maxHeight - 2 * vertical).clamp(
                    0.0,
                    double.infinity,
                  ),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  // The empty first slot centres the main block between the
                  // top and the footer.
                  children: [const SizedBox.shrink(), main, footer],
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  static const _titleSize = 26.0;
  static const _titleLineHeight = 1.4;

  static const _issuesUrl = 'https://github.com/MostroP2P/app/issues';

  /// Each row's content with a copy button to its right.
  ///
  /// A table with three columns: the side columns share the leftover width
  /// equally, so the contents are centred on the screen by construction, and
  /// every button lives in the same right-hand column, so they line up
  /// vertically. The middle column is as wide as the widest content but never
  /// wider than the screen minus a tap target (kMinInteractiveDimension, what
  /// IconButton needs) on each side, so a long text wraps instead of pushing
  /// the buttons off the screen.
  Widget _copyTable(
    BuildContext context,
    List<(String tooltip, String text, Widget content)> rows,
  ) {
    return LayoutBuilder(
      builder:
          (context, box) => Table(
            defaultVerticalAlignment: TableCellVerticalAlignment.middle,
            columnWidths: {
              0: const FlexColumnWidth(),
              1: MinColumnWidth(
                const IntrinsicColumnWidth(),
                FixedColumnWidth(box.maxWidth - 2 * kMinInteractiveDimension),
              ),
              2: const FlexColumnWidth(),
            },
            children: [
              for (final (tooltip, text, content) in rows)
                TableRow(
                  children: [
                    const SizedBox.shrink(),
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: content,
                    ),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: _copyButton(context, tooltip, text),
                    ),
                  ],
                ),
            ],
          ),
    );
  }

  /// Awaited: on the web the write can be refused (no permission, not a secure
  /// context), and "Copied" over an empty clipboard sends someone off with
  /// nothing to paste.
  Widget _copyButton(BuildContext context, String tooltip, String text) {
    return IconButton(
      tooltip: tooltip,
      icon: const Icon(Icons.copy, size: 18),
      color: const Color(0xFFB0B6C3),
      onPressed: () async {
        final messenger = ScaffoldMessenger.of(context);
        try {
          await Clipboard.setData(ClipboardData(text: text));
          messenger.showSnackBar(
            const SnackBar(
              content: Text('Copied'),
              duration: Duration(seconds: 2),
            ),
          );
        } catch (_) {
          messenger.showSnackBar(
            const SnackBar(
              content: Text('Could not copy. Select the text instead.'),
            ),
          );
        }
      },
    );
  }
}

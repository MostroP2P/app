@TestOn('vm')
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../tool/design/design_check.dart';

/// The "Design guide" CI job runs `tool/design_check.dart` on the lines a
/// pull request adds or changes under `lib/`, and fails on every break of a
/// rule `.specify/DESIGN_SYSTEM.md` marks *auto*. A rule that misses a break
/// lets a second design system in; one that flags a legal line blocks a
/// pull request for nothing. Both are tested here, rule by rule.
void main() {
  /// The rules [source] breaks, as `rule@line`.
  List<String> breaks(String source, {Set<int>? lines}) => [
    for (final v in scan('lib/features/x/x.dart', source, lines: lines))
      '${v.rule}@${v.line}',
  ];

  group('which lines a diff adds', () {
    test('reads the new-side range of every hunk', () {
      const diff = '''
diff --git a/lib/a.dart b/lib/a.dart
index 1..2 100644
--- a/lib/a.dart
+++ b/lib/a.dart
@@ -3,0 +4,2 @@ class A {
+  x
+  y
@@ -10 +12 @@ class A {
-  old
+  new
@@ -20,3 +23,0 @@ class A {
-  gone
-  gone
-  gone
diff --git a/lib/b.dart b/lib/b.dart
new file mode 100644
--- /dev/null
+++ b/lib/b.dart
@@ -0,0 +1,3 @@
+a
+b
+c
diff --git a/lib/c.dart b/lib/c.dart
deleted file mode 100644
--- a/lib/c.dart
+++ /dev/null
@@ -1 +0,0 @@
-x
''';
      expect(addedLines(diff), {
        'lib/a.dart': {4, 5, 12},
        'lib/b.dart': {1, 2, 3},
      });
    });

    test('keeps a file it only removes lines from, with none', () {
      const diff = '''
diff --git a/lib/a.dart b/lib/a.dart
index 1..2 100644
--- a/lib/a.dart
+++ b/lib/a.dart
@@ -2 +1,0 @@ class A {
-  gone
''';
      expect(addedLines(diff), {'lib/a.dart': <int>{}});
    });

    test('keeps a file it only renames, with none', () {
      const diff = '''
diff --git a/lib/a.dart b/lib/b.dart
similarity index 100%
rename from lib/a.dart
rename to lib/b.dart
''';
      expect(addedLines(diff), {'lib/b.dart': <int>{}});
    });
  });

  group('which files it reads', () {
    test('UI source under lib/', () {
      expect(isChecked('lib/features/order/widgets/x.dart'), isTrue);
      expect(isChecked('lib/shared/widgets/x.dart'), isTrue);
    });

    test('not the token layer, generated code or other files', () {
      expect(isChecked('lib/core/order_book_palette.dart'), isFalse);
      expect(isChecked('lib/src/rust/api/orders.dart'), isFalse);
      expect(isChecked('lib/l10n/app_localizations_de.dart'), isFalse);
      expect(isChecked('lib/features/x/model.g.dart'), isFalse);
      expect(isChecked('lib/features/x/model.freezed.dart'), isFalse);
      expect(isChecked('test/features/x_test.dart'), isFalse);
      expect(isChecked('lib/features/x/README.md'), isFalse);
    });
  });

  group('which files it reads whole', () {
    test('a screen', () {
      expect(
        isScreen('lib/features/cashu/screens/cashu_wallet_screen.dart'),
        isTrue,
      );
      expect(
        isScreen('lib/features/order/screens/take/take_screen.dart'),
        isTrue,
      );
    });

    test('not a widget or anything else', () {
      expect(isScreen('lib/features/order/widgets/amount_field.dart'), isFalse);
      expect(isScreen('lib/shared/widgets/mostro_modal.dart'), isFalse);
      expect(isScreen('lib/features/x/screens_helper.dart'), isFalse);
    });
  });

  /// The CI job's own run, against a throwaway repository whose `main`
  /// already holds a break outside the declaration a change touches: a
  /// pull request that touches a screen answers for all of it, one that
  /// touches any other file for the declarations it touched.
  group('a pull request', skip: Platform.isWindows, () {
    const screen = 'lib/features/x/screens/x_screen.dart';
    const widget = 'lib/features/x/widgets/x_widget.dart';
    const legacy = 'final a = Colors.white;\nfinal b = 1;\n';
    final tool = File('tool/design_check.dart').absolute.path;
    late Directory repo;

    final env = {
      'GIT_CONFIG_GLOBAL': '/dev/null',
      'GIT_CONFIG_NOSYSTEM': '1',
      'GIT_AUTHOR_NAME': 'Test',
      'GIT_AUTHOR_EMAIL': 'test@example.com',
      'GIT_COMMITTER_NAME': 'Test',
      'GIT_COMMITTER_EMAIL': 'test@example.com',
    };

    void git(List<String> args) {
      final result = Process.runSync(
        'git',
        args,
        workingDirectory: repo.path,
        environment: env,
      );
      expect(
        result.exitCode,
        0,
        reason: 'git ${args.join(' ')}: ${result.stderr}',
      );
    }

    void commit(Map<String, String> files) {
      for (final MapEntry(key: path, value: source) in files.entries) {
        File('${repo.path}/$path')
          ..createSync(recursive: true)
          ..writeAsStringSync(source);
      }
      git(['add', '-A']);
      git(['commit', '-qm', 'change']);
    }

    // Not in annotation mode, which CI's own GITHUB_ACTIONS would turn on:
    // these tests read the plain `path:line: RULE` lines.
    ProcessResult check() => Process.runSync(
      'dart',
      [tool, '--base', 'main'],
      workingDirectory: repo.path,
      environment: {'GITHUB_ACTIONS': 'false'},
    );

    setUp(() {
      repo = Directory.systemTemp.createTempSync('design_check_');
      git(['init', '-q', '-b', 'main']);
      commit({screen: legacy, widget: legacy});
      git(['switch', '-q', '-c', 'pr']);
    });

    tearDown(() => repo.deleteSync(recursive: true));

    test('fails on a break anywhere in a screen it touches', () {
      commit({screen: 'final a = Colors.white;\nfinal b = 2;\n'});

      final result = check();

      expect(result.exitCode, 1, reason: '${result.stdout}');
      expect(result.stdout, contains('$screen:1: DS-COL-1'));
    });

    test('fails when it only removes lines from such a screen', () {
      commit({screen: 'final a = Colors.white;\n'});

      final result = check();

      expect(result.exitCode, 1, reason: '${result.stdout}');
      expect(result.stdout, contains('$screen:1: DS-COL-1'));
    });

    test('fails when it only renames such a screen', () {
      git(['mv', screen, 'lib/features/x/screens/y_screen.dart']);
      git(['commit', '-qm', 'rename']);

      final result = check();

      expect(result.exitCode, 1, reason: '${result.stdout}');
      expect(
        result.stdout,
        contains('lib/features/x/screens/y_screen.dart:1: DS-COL-1'),
      );
    });

    test('reads a widget only where it touches it', () {
      commit({widget: 'final a = Colors.white;\nfinal b = 2;\n'});

      final result = check();

      expect(result.exitCode, 0, reason: '${result.stdout}');
    });
  });

  group('DS-COL-1: no color literal', () {
    test('flags hex colors, ARGB/RGBO and Material swatches', () {
      expect(
        breaks('''
final a = Color(0xFF92D64F);
final b = const Color(0x80FFFFFF);
final c = Color.fromARGB(255, 1, 2, 3);
final d = Color.fromRGBO(1, 2, 3, 1);
final e = Colors.white;
final f = Colors.red.shade200;
final g = material.Colors.black54;
'''),
        [
          'DS-COL-1@1',
          'DS-COL-1@2',
          'DS-COL-1@3',
          'DS-COL-1@4',
          'DS-COL-1@5',
          'DS-COL-1@6',
          'DS-COL-1@7',
        ],
      );
    });

    test('allows transparent and palette tokens', () {
      expect(
        breaks('''
final a = Colors.transparent;
final c = pal.lime;
final d = MyColor(1);
'''),
        isEmpty,
      );
    });
  });

  group('DS-TYP-1: fonts through AppFonts', () {
    test('flags a family named in a string, and Google Fonts', () {
      expect(
        breaks('''
final a = TextStyle(fontFamily: 'Manrope');
final b = TextStyle(fontFamily: "Roboto");
final c = GoogleFonts.inter();
'''),
        ['DS-TYP-1@1', 'DS-TYP-1@2', 'DS-TYP-1@3'],
      );
    });

    test('allows the tokens and monospace for machine strings', () {
      expect(
        breaks('''
final a = TextStyle(fontFamily: AppFonts.figures);
final b = TextStyle(fontFamily: 'monospace');
'''),
        isEmpty,
      );
    });
  });

  group('DS-TYP-4: font sizes on the scale', () {
    test('allows every size of the scale', () {
      for (final size in fontSizes) {
        expect(breaks('final s = TextStyle(fontSize: $size);'), isEmpty);
      }
      expect(breaks('final s = TextStyle(fontSize: 13.0);'), isEmpty);
    });

    test('flags half points, sizes under 10 and sizes off the scale', () {
      expect(
        breaks('''
final a = TextStyle(fontSize: 12.5);
final b = TextStyle(fontSize: 9);
final c = TextStyle(fontSize: 16);
final d = TextStyle(fontSize: alone ? 15 : 18);
'''),
        ['DS-TYP-4@1', 'DS-TYP-4@2', 'DS-TYP-4@3', 'DS-TYP-4@4'],
      );
    });

    test('leaves derived sizes to review', () {
      expect(
        breaks('''
final a = TextStyle(fontSize: base * 0.8);
final b = TextStyle(fontSize: theme.fontSize);
'''),
        isEmpty,
      );
    });
  });

  group('DS-TYP-7: text scaling stays on', () {
    test('flags turning it off or clamping it', () {
      expect(
        breaks('''
final a = MediaQuery.of(c).copyWith(textScaler: TextScaler.noScaling);
final b = Text('x', textScaleFactor: 1);
final c = s.clamp(maxScaleFactor: 1.3);
final d = MediaQuery.of(c).copyWith(textScaler: const TextScaler.linear(1));
final e = MediaQuery.of(c).copyWith(
  padding: p,
  textScaler: fixed,
);
'''),
        ['DS-TYP-7@1', 'DS-TYP-7@2', 'DS-TYP-7@3', 'DS-TYP-7@4', 'DS-TYP-7@7'],
      );
    });

    test('allows reading the scaler, and a framework signature naming it', () {
      expect(
        breaks('''
final p = TextPainter(textScaler: MediaQuery.textScalerOf(c));
void paint(PaintingContext c, {required double textScaleFactor}) {}
'''),
        isEmpty,
      );
    });
  });

  group('DS-SHP-1: radii on the scale', () {
    test('allows the scale, square corners and tokens', () {
      expect(
        breaks('''
final a = BorderRadius.circular(18);
final b = Radius.circular(999);
final c = BorderRadius.all(Radius.circular(14));
final d = Radius.circular(0);
final e = BorderRadius.circular(AppRadius.modal);
final f = Radius.circular(AppRadius.bubble - 4);
'''),
        isEmpty,
      );
    });

    test('flags any other radius', () {
      expect(
        breaks('''
final a = BorderRadius.circular(13);
final b = BorderRadius.only(topLeft: Radius.circular(20));
'''),
        ['DS-SHP-1@1', 'DS-SHP-1@2'],
      );
    });
  });

  group('DS-SPC-2: spacing on the 2-pt scale', () {
    test('allows the scale, hairlines and tokens', () {
      expect(
        breaks('''
final a = EdgeInsets.symmetric(horizontal: 18, vertical: 14);
final b = EdgeInsets.fromLTRB(0, 1, 2, 32);
final c = EdgeInsets.only(left: redesignSidePadding);
const d = SizedBox(height: 12);
final e = Row(spacing: 8, children: []);
final f = EdgeInsetsDirectional.only(start: 4);
'''),
        isEmpty,
      );
    });

    test('flags odd and off-scale values in paddings, gaps and spacing', () {
      expect(
        breaks('''
final a = EdgeInsets.symmetric(horizontal: 14, vertical: 13);
final b = EdgeInsets.all(22);
const c = SizedBox(width: 5);
final d = Wrap(runSpacing: 7, children: []);
final e = BackupFillViewport(gap: 13, children: []);
'''),
        ['DS-SPC-2@1', 'DS-SPC-2@2', 'DS-SPC-2@3', 'DS-SPC-2@4', 'DS-SPC-2@5'],
      );
    });

    test('reads a constructor split over several lines', () {
      expect(
        breaks('''
final a = EdgeInsets.fromLTRB(
  18,
  11,
  18,
  14,
);
'''),
        ['DS-SPC-2@3'],
      );
    });

    test('a SizedBox with a child or both sides is a size, not a gap', () {
      expect(
        breaks('''
final a = SizedBox(width: 300, child: x);
final b = SizedBox(width: 38, height: 4);
'''),
        isEmpty,
      );
    });
  });

  group('DS-SPC-4: breakpoints through AppBreakpoints', () {
    test('flags a width compared with a number', () {
      expect(
        breaks('''
final a = constraints.maxWidth < 700;
final b = MediaQuery.sizeOf(c).width >= 900;
'''),
        ['DS-SPC-4@1', 'DS-SPC-4@2'],
      );
    });

    test('allows the tokens and a zero check', () {
      expect(
        breaks('''
final a = constraints.maxWidth >= AppBreakpoints.desktop;
final b = width <= 0;
'''),
        isEmpty,
      );
    });
  });

  group('DS-ICO-3: icon sizes', () {
    test('allows the scale', () {
      expect(
        breaks('''
final a = Icon(Icons.bolt, size: 16);
final b = Icon(Icons.check, color: c, size: 44);
final c = IconButton(iconSize: 24, onPressed: f, icon: x);
'''),
        isEmpty,
      );
    });

    test('flags any other size', () {
      expect(
        breaks('''
final a = Icon(Icons.bolt, size: 13);
final b = IconButton(iconSize: 17, onPressed: f, icon: x);
'''),
        ['DS-ICO-3@1', 'DS-ICO-3@2'],
      );
    });
  });

  group('DS-COL-11: no v1 color layer', () {
    test('flags reading AppColors in any form', () {
      expect(
        breaks('''
final colors = Theme.of(context).extension<AppColors>()!;
final (bg, ink) = AppColors.statusPending;
'''),
        ['DS-COL-11@1', 'DS-COL-11@2'],
      );
    });

    test('allows the redesign palettes', () {
      expect(
        breaks('''
final book = OrderBookPalette.of(context);
// Was AppColors before the redesign.
'''),
        isEmpty,
      );
    });
  });

  /// What makes a screen look like v1 is mostly what it leaves out: a
  /// Material widget with no style of its own takes the theme's defaults,
  /// and the theme still carries v1's (#657).
  group('DS-CMP-17: Material buttons carry their own style', () {
    test('flags a button that leaves its style to the theme', () {
      expect(
        breaks('''
final a = OutlinedButton.icon(onPressed: f, icon: i, label: l);
final b = FilledButton(onPressed: f, child: Text('x', style: s));
final c = TextButton(onPressed: f, child: c);
final e = TextButton.icon(
  onPressed: f,
  icon: Icon(i, color: pal.limeIcon),
  label: Text(t),
);
final d = ElevatedButton(onPressed: f, child: c);
'''),
        [
          'DS-CMP-17@1',
          'DS-CMP-17@2',
          'DS-CMP-17@3',
          'DS-CMP-17@4',
          'DS-CMP-17@9',
        ],
      );
    });

    test('allows a styled button and an icon button', () {
      expect(
        breaks('''
final a = FilledButton(
  onPressed: f,
  style: FilledButton.styleFrom(backgroundColor: book.lime),
  child: c,
);
final b = IconButton(onPressed: f, icon: i);
final l = TextButton(
  onPressed: f,
  child: Text(t, style: TextStyle(color: pal.textSecondary)),
);
final s = FilledButton.styleFrom(backgroundColor: book.lime);
'''),
        isEmpty,
      );
    });
  });

  group('DS-CMP-12: app bars', () {
    test('flags an AppBar that takes the theme background', () {
      expect(
        breaks('''
final a = AppBar(title: Text(t));
final b = SliverAppBar.large(title: Text(t));
'''),
        ['DS-CMP-12@1', 'DS-CMP-12@2'],
      );
    });

    test('allows one on a palette background, and the shared builders', () {
      expect(
        breaks('''
final a = AppBar(backgroundColor: book.bg, title: t);
final b = redesignAppBar(context, title: t);
'''),
        isEmpty,
      );
    });
  });

  group('DS-CMP-18: scaffolds', () {
    test('flags a Scaffold that takes the theme background', () {
      expect(breaks('final a = Scaffold(body: b);'), ['DS-CMP-18@1']);
    });

    test('allows one on a palette background', () {
      expect(
        breaks('final a = Scaffold(backgroundColor: book.bg, body: b);'),
        isEmpty,
      );
    });
  });

  /// Measured under the app theme (#673): every decoration below still
  /// paints v1's #252A3A fill and #9A9A9C underline. `border:` is only the
  /// fallback for states the theme leaves unset, and the theme sets
  /// `enabledBorder`, `focusedBorder` and `filled: true`.
  group('DS-CMP-19: text fields', () {
    test('flags a field that leaves any of them to the theme', () {
      expect(
        breaks('''
final a = TextField(controller: c);
final b = TextField(decoration: InputDecoration(hintText: h));
final c = TextField(decoration: InputDecoration(border: InputBorder.none));
final d = TextField(
  decoration: const InputDecoration(
    isCollapsed: true,
    border: InputBorder.none,
  ),
);
final e = TextField(decoration: const InputDecoration.collapsed(hintText: h));
final f = TextField(
  decoration: InputDecoration(focusedBorder: InputBorder.none, filled: false),
);
final g = TextField(
  decoration: InputDecoration(
    enabledBorder: InputBorder.none,
    focusedBorder: InputBorder.none,
  ),
);
'''),
        [
          'DS-CMP-19@1',
          'DS-CMP-19@2',
          'DS-CMP-19@3',
          'DS-CMP-19@4',
          'DS-CMP-19@10',
          'DS-CMP-19@11',
          'DS-CMP-19@14',
        ],
      );
    });

    test('allows a field that sets its borders and fill, or delegates', () {
      expect(
        breaks('''
final a = TextField(
  decoration: InputDecoration(
    filled: false,
    border: InputBorder.none,
    enabledBorder: InputBorder.none,
    focusedBorder: InputBorder.none,
  ),
);
final b = TextField(
  decoration: InputDecoration(
    filled: true,
    fillColor: pal.inset,
    enabledBorder: OutlineInputBorder(borderSide: side),
    focusedBorder: OutlineInputBorder(borderSide: focus),
  ),
);
final c = TextField(decoration: _fieldDecoration(pal));
'''),
        isEmpty,
      );
    });
  });

  /// The code of #657 (Cashu "Receive": scan or paste a token), the pull
  /// request that passed the first version of this check while looking like
  /// v1: a theme-default scaffold and app bar, the v1 color layer, two
  /// stadium-shaped outlined buttons and a theme-default field.
  test('catches what made #657 look like v1', () {
    expect(
      breaks('''
Future<String?> _scanToken() {
  return Navigator.of(context).push<String>(
    MaterialPageRoute(
      builder: (routeContext) {
        final l10n = AppLocalizations.of(routeContext);
        return Scaffold(
          appBar: AppBar(title: Text(l10n.scanQrCodeTitle)),
          body: PlatformAwareQrScanner(
            hint: l10n.cashuReceiveHint,
            onDetected: (value) => Navigator.of(routeContext).pop(value),
          ),
        );
      },
    ),
  );
}
Widget build(BuildContext context) {
  final l10n = AppLocalizations.of(context);
  final colors = Theme.of(context).extension<AppColors>()!;
  return Row(
    children: [
      OutlinedButton.icon(
        onPressed: canScan ? () => Navigator.of(context).pop(scan) : null,
        icon: const Icon(Icons.qr_code_scanner),
        label: Text(l10n.scanQrButtonLabel),
      ),
      Text(
        l10n.cashuScanUnavailable,
        style: TextStyle(color: colors.textSubtle, fontSize: 12),
      ),
      OutlinedButton.icon(
        onPressed: () => Navigator.of(context).pop(paste),
        icon: const Icon(Icons.content_paste),
        label: Text(l10n.pasteButtonLabel),
      ),
    ],
  );
}
final field = TextField(
  controller: _controller,
  style: const TextStyle(fontSize: 12),
  decoration: InputDecoration(
    hintText: l10n.cashuPasteTokenHint,
    errorText: _error,
  ),
);
'''),
      [
        'DS-CMP-18@6',
        'DS-CMP-12@7',
        'DS-COL-11@19',
        'DS-CMP-17@22',
        'DS-CMP-17@31',
        'DS-CMP-19@39',
      ],
    );
  });

  /// The theme's radius tokens carry v1's roles: a card at 12, a button and
  /// an input at 8, a chip at 6. On the scale or not, each is the wrong
  /// shape for the job its name promises.
  group('DS-SHP-4: no v1 radius token', () {
    test('flags the tokens whose role the redesign changed', () {
      expect(
        breaks('''
final a = BorderRadius.circular(AppRadius.card);
final b = BorderRadius.circular(AppRadius.button);
final c = BorderRadius.circular(AppRadius.input);
final d = BorderRadius.circular(AppRadius.chip);
'''),
        ['DS-SHP-4@1', 'DS-SHP-4@2', 'DS-SHP-4@3', 'DS-SHP-4@4'],
      );
    });

    test('allows the redesign tokens', () {
      expect(
        breaks('''
final a = BorderRadius.circular(AppRadius.modal);
final b = BorderRadius.circular(AppRadius.cta);
final c = BorderRadius.circular(AppRadius.bubble);
'''),
        isEmpty,
      );
    });
  });

  /// A `textTheme` role is a font size that never appears as a literal:
  /// the theme's are v1's scale, and a role it leaves out is Material's.
  group('DS-TYP-4: textTheme roles on the scale', () {
    test('flags a role the theme sets off the scale, or not at all', () {
      expect(
        breaks('''
final a = Theme.of(context).textTheme.headlineSmall;
final b = theme.textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w600);
final c = Theme.of(context).textTheme.titleMedium;
'''),
        ['DS-TYP-4@1', 'DS-TYP-4@2', 'DS-TYP-4@3'],
      );
    });

    test('allows the roles the theme sets on the scale', () {
      expect(
        breaks('''
final a = Theme.of(context).textTheme.bodyMedium;
final b = theme.textTheme.bodySmall;
final c = theme.textTheme.labelLarge;
final d = theme.textTheme.labelSmall;
final e = theme.textTheme.apply(bodyColor: pal.textBody);
final f = theme.textTheme.copyWith(bodySmall: s);
final g = Theme.of(context).textTheme.merge(other);
'''),
        isEmpty,
      );
    });
  });

  /// A break is reported on the line of the widget call. A pull request that
  /// edits an argument of a theme-default button leaves that line untouched,
  /// and the first version of the check let it through (#657). Outside a
  /// class, the top-level function or variable is read whole, like a class.
  group('a call a changed line falls inside', () {
    const source = '''
final a = FilledButton.icon(
  onPressed: f,
  icon: const Icon(Icons.download_outlined),
  label: Text(l),
);
final b = Text(t);
''';

    test('is checked whole', () {
      expect(breaks(source, lines: {3}), ['DS-CMP-17@1']);
    });

    test('is not reported for a change outside it', () {
      expect(breaks(source, lines: {6}), isEmpty);
    });

    test('is read for every rule, not only a missing style', () {
      const helper = '''
Widget framed(Widget child) {
  return Padding(
    padding: const EdgeInsets.all(13),
    child: child,
  );
}
final pad = EdgeInsets.all(11);
''';
      expect(breaks(helper, lines: {4}), ['DS-SPC-2@3']);
    });
  });

  /// A class with one changed line is read whole (guide §0): touching a
  /// legacy screen means leaving the class it touched free of *auto* breaks.
  group('a class a changed line falls inside', () {
    const source = '''
class _ScreenState extends State<Screen> with TickerProviderStateMixin {
  void _receive() {
    _prompt(_askForToken);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Padding(padding: const EdgeInsets.all(13), child: c),
    );
  }
}

final top = EdgeInsets.all(13);

class _Card<T extends Object> extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Scaffold(body: b);
}
''';

    test('is checked whole', () {
      expect(breaks(source, lines: {3}), ['DS-CMP-18@8', 'DS-SPC-2@9']);
    });

    test('leaves the code around it alone', () {
      expect(breaks(source, lines: {18}), ['DS-CMP-18@18']);
      expect(breaks(source, lines: {14}), ['DS-SPC-2@14']);
    });

    test('is found past mixin applications and extension reads', () {
      const tricky = '''
class _Mixed = Base with Mixin;
Widget helper(BuildContext context) {
  final colors = Theme.of(context).extension<Palette>()!;
  return Scaffold(body: b);
}
mixin _Look on Widget {
  Widget frame() => Scaffold(body: b);
  void touched() {}
}
extension _Pad on Widget {
  Widget pad() => Padding(padding: const EdgeInsets.all(13), child: this);
}
enum _Kind { a, b }
''';
      expect(breaks(tricky, lines: {1}), isEmpty);
      expect(breaks(tricky, lines: {3}), ['DS-CMP-18@4']);
      expect(breaks(tricky, lines: {8}), ['DS-CMP-18@7']);
      expect(breaks(tricky, lines: {12}), ['DS-SPC-2@11']);
    });
  });

  /// The Cashu wallet screen as #657 left it: the pull request changed one
  /// icon and the `_receive` body inside a v1 screen, and the check, reading
  /// only those lines, approved a theme-default scaffold, app bar, two
  /// stadium buttons, a v1 card radius and an 18-sp headline.
  test('catches the legacy screen #657 changed one line of', () {
    const source = '''
class _CashuWalletScreenState extends ConsumerState<CashuWalletScreen> {
  Future<void> _receive() async {
    final token = await _prompt(_askForToken);
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppColors>()!;
    return Scaffold(
      appBar: AppBar(title: Text(l10n.cashuWalletTitle)),
      body: ListView(
        children: [
          Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(AppRadius.card),
            ),
            child: Text(
              balance,
              style: Theme.of(context).textTheme.headlineSmall,
            ),
          ),
          FilledButton.icon(
            onPressed: _receive,
            icon: const Icon(Icons.download_outlined),
            label: Text(l10n.cashuReceiveButton),
          ),
          OutlinedButton.icon(
            onPressed: _send,
            icon: const Icon(Icons.upload_outlined),
            label: Text(l10n.cashuSendButton),
          ),
        ],
      ),
    );
  }
}
''';
    expect(breaks(source, lines: {3, 24}), [
      'DS-COL-11@8',
      'DS-CMP-18@9',
      'DS-CMP-12@10',
      'DS-SHP-4@15',
      'DS-TYP-4@19',
      'DS-CMP-17@22',
      'DS-CMP-17@27',
    ]);
  });

  group('what it does not read', () {
    test('comments and strings', () {
      expect(
        breaks('''
// Color(0xFF000000) was the v1 green.
/* BorderRadius.circular(13) */
/// Uses `Colors.white` on purpose.
final s = 'EdgeInsets.all(13) Colors.red';
final t = """fontSize: 9""";
'''),
        isEmpty,
      );
    });

    test('lines the pull request did not touch', () {
      const source = '''
final a = EdgeInsets.all(13);
final b = EdgeInsets.all(11);
''';
      expect(breaks(source, lines: {2}), ['DS-SPC-2@2']);
      expect(breaks(source, lines: {}), isEmpty);
    });
  });

  group('an ignore comment', () {
    test('silences one rule on its own line, or on the next when alone', () {
      expect(
        breaks('''
final a = EdgeInsets.all(13); // design-check: ignore DS-SPC-2 — optical centre of the glyph
// design-check: ignore DS-COL-1 — QR codes must be pure black on white
final b = Colors.black;
'''),
        isEmpty,
      );
    });

    test(
      'does nothing without a reason, for another rule, or further down',
      () {
        expect(
          breaks('''
final a = EdgeInsets.all(13); // design-check: ignore DS-SPC-2
final b = EdgeInsets.all(13); // design-check: ignore DS-COL-1 — wrong rule
final c = EdgeInsets.all(13); // design-check: ignore DS-SPC-2 — only this line
final d = EdgeInsets.all(13);
'''),
          ['DS-SPC-2@1', 'DS-SPC-2@2', 'DS-SPC-2@4'],
        );
      },
    );
  });

  /// The guide is what a reviewer reads; the scales below are what CI
  /// enforces. A value added to one and not the other makes the guide lie.
  group('agrees with .specify/DESIGN_SYSTEM.md', () {
    final guide = File('.specify/DESIGN_SYSTEM.md').readAsStringSync();

    Set<num> numbersIn(String text) => {
      for (final m in RegExp(r'\b\d+(?:\.\d+)?\b').allMatches(text))
        num.parse(m[0]!),
    };

    /// The first cell of every row of the table that follows [heading].
    Set<num> firstColumn(String heading) {
      final start = guide.indexOf(heading);
      expect(start, isNot(-1), reason: 'guide has no "$heading"');
      final rows = guide
          .substring(start)
          .split('\n')
          .skipWhile((l) => !l.startsWith('|'))
          .takeWhile((l) => l.startsWith('|'))
          .skip(2);
      return {for (final row in rows) ...numbersIn(row.split('|')[1])};
    }

    String ruleRow(String id) =>
        guide.split('\n').firstWhere((l) => l.startsWith('| $id |'));

    test('font sizes (§3.2)', () {
      expect(firstColumn('### 3.2 Scale'), fontSizes);
    });

    test('radii (§4)', () {
      expect(firstColumn('## 4. Shape and elevation'), radii.difference({0}));
    });

    test('spacing (DS-SPC-2)', () {
      final bold = RegExp(r'\*\*([\d, ]+)\*\*').firstMatch(ruleRow('DS-SPC-2'));
      expect({...numbersIn(bold![1]!), 0, 1}, spacing);
    });

    test('icon sizes (DS-ICO-3)', () {
      final row = ruleRow('DS-ICO-3').split('|')[2];
      expect(numbersIn(row.substring(row.indexOf('sizes:'))), iconSizes);
    });

    /// A rule marked *auto* that the check never reports is a promise CI
    /// does not keep; one it reports unmarked is a break nobody can look up.
    test('the rules marked auto are the ones it reports', () {
      final marked = {
        for (final row in guide.split('\n'))
          if (RegExp(
            r'^\| DS-[A-Z0-9]+-\d+ \|.*\|\s*[^|]*\bauto\b[^|]*\|$',
          ).hasMatch(row))
            row.split('|')[1].trim(),
      };
      final checker = File('tool/design/design_check.dart').readAsStringSync();
      final reported = {
        for (final m in RegExp(r"'(DS-[A-Z0-9]+-\d+)'").allMatches(checker))
          m[1]!,
      };
      expect(reported, marked);
    });
  });

  /// The `textTheme` roles the check allows are the ones the theme sets on
  /// the type scale. A theme change that moves one must move the check too.
  test('agrees with the textTheme in lib/core/app_theme.dart', () {
    final theme = File('lib/core/app_theme.dart').readAsStringSync();
    final block = theme.substring(theme.indexOf('textTheme: TextTheme('));
    final onScale = {
      for (final m in RegExp(
        r'(\w+): TextStyle\(\s*fontSize: (\d+)',
      ).allMatches(block.substring(0, block.indexOf('\n    ),'))))
        if (fontSizes.contains(num.parse(m[2]!))) m[1]!,
    };
    expect(onScale, textThemeRoles);
  });
}

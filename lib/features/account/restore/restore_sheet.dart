import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:mostro/core/app_theme.dart';
import 'package:mostro/core/restore_palette.dart';
import 'package:mostro/features/account/restore/restore_run.dart';
import 'package:mostro/features/trades/models/trades_list_rules.dart';
import 'package:mostro/features/trades/providers/trade_rows_provider.dart';
import 'package:mostro/l10n/app_localizations.dart';
import 'package:mostro/shared/widgets/mostro_modal.dart';

/// Opens the restore sheet (design 20a–20d) and runs [run] in it, resolving
/// once the user closes it.
///
/// It cannot be dismissed by a tap outside or a drag: while the restore runs
/// the way out is `Cancelar`, and in the final states the buttons.
Future<void> showRestoreSheet(BuildContext context, {required RestoreRun run}) {
  return showMostroSheet<void>(
    context: context,
    bare: true,
    isDismissible: false,
    enableDrag: false,
    builder: (_) => RestoreSheet(run: run),
  );
}

/// What the finished restore adds up to (20d).
@immutable
class RestoreSummary {
  const RestoreSummary({required this.inProgress, required this.needsAction});

  /// Trades not closed yet.
  final int inProgress;

  /// Trades whose next step is the user's.
  final int needsAction;
}

/// Read once the restore finished: what the trade list holds.
final restoreSummaryProvider = Provider.autoDispose<RestoreSummary>((ref) {
  final rows = ref.watch(tradeRowsProvider).valueOrNull ?? const [];
  return RestoreSummary(
    inProgress: rows.where((r) => r.state.group != TradeGroup.closed).length,
    needsAction: rows.where((r) => r.state.needsAction).length,
  );
});

/// The restore sheet itself. Starts [run] when it opens and disposes it when
/// it closes: a closed sheet stops following the restore, which the core
/// finishes on its own (see the Account screen).
class RestoreSheet extends ConsumerStatefulWidget {
  const RestoreSheet({super.key, required this.run});

  final RestoreRun run;

  @override
  ConsumerState<RestoreSheet> createState() => _RestoreSheetState();
}

class _RestoreSheetState extends ConsumerState<RestoreSheet> {
  /// The stage label last announced to a screen reader.
  String? _announced;

  @override
  void initState() {
    super.initState();
    widget.run.addListener(_onChange);
    unawaited(widget.run.start());
  }

  @override
  void dispose() {
    widget.run.removeListener(_onChange);
    widget.run.dispose();
    super.dispose();
  }

  void _onChange() {
    if (!mounted) return;
    setState(() {});
    _announce();
  }

  /// Say the stage in flight when it changes, the way the screen shows it.
  void _announce() {
    final l10n = AppLocalizations.of(context);
    final state = widget.run.state;
    final active = state.stages.indexOf(RestoreStage.active);
    final String? text = switch (state.outcome) {
      RestoreOutcome.failed => l10n.restoreFailedTitle,
      RestoreOutcome.restored => l10n.restoreDoneTitle,
      RestoreOutcome.running when active >= 0 => _stageLabel(
        l10n,
        state,
        active,
      ),
      _ => null,
    };
    if (text == null || text == _announced) return;
    _announced = text;
    // `sendAnnouncement` replaces this on newer SDKs; the 3.38.2 that
    // `ci.yml` pins is the floor, so this stays until that pin moves.
    // ignore: deprecated_member_use
    SemanticsService.announce(text, Directionality.of(context));
  }

  void _close() => Navigator.of(context).pop();

  @override
  Widget build(BuildContext context) {
    final pal = RestorePalette.of(context);
    final state = widget.run.state;
    final edge = switch (state.outcome) {
      RestoreOutcome.running => pal.borderRunning,
      RestoreOutcome.restored => pal.borderDone,
      RestoreOutcome.failed => pal.borderError,
    };
    const radius = BorderRadius.vertical(top: Radius.circular(28));

    // A 1px top edge on a rounded sheet: the edge colour behind, the sheet
    // one pixel lower (a one-sided border cannot follow a radius).
    return DecoratedBox(
      decoration: BoxDecoration(color: edge, borderRadius: radius),
      child: Padding(
        padding: const EdgeInsets.only(top: 1),
        child: DecoratedBox(
          decoration: BoxDecoration(color: pal.sheet, borderRadius: radius),
          child: Padding(
            padding: EdgeInsets.fromLTRB(
              20,
              12,
              20,
              26 + MediaQuery.of(context).viewPadding.bottom,
            ),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: _gapped([
                  Center(
                    child: Container(
                      width: 38,
                      height: 4,
                      decoration: BoxDecoration(
                        color: pal.handle,
                        borderRadius: BorderRadius.circular(999),
                      ),
                    ),
                  ),
                  _Header(state: state),
                  if (state.outcome == RestoreOutcome.running)
                    _Bar(progress: state.progress),
                  _Stages(state: state),
                  ..._footer(context, state),
                ]),
              ),
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _footer(BuildContext context, RestoreRunState state) {
    final l10n = AppLocalizations.of(context);
    final pal = RestorePalette.of(context);
    switch (state.outcome) {
      case RestoreOutcome.running:
        return [
          Center(
            child: TextButton(
              key: const Key('restore.cancel'),
              onPressed: _close,
              child: Text(
                l10n.cancel,
                style: TextStyle(
                  color: pal.textSecondary,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ];
      case RestoreOutcome.failed:
        return [
          _FailureParagraph(),
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _LimeButton(
                key: const Key('restore.retry'),
                label: l10n.retry,
                icon: Icons.sync,
                onPressed: () => unawaited(widget.run.start()),
              ),
              const SizedBox(height: 10),
              _OutlineButton(
                key: const Key('restore.continue'),
                label: l10n.restoreContinueWithout,
                onPressed: _close,
              ),
            ],
          ),
        ];
      case RestoreOutcome.restored:
        final summary = ref.watch(restoreSummaryProvider);
        return [
          _Summary(found: state.found ?? 0, summary: summary),
          if (state.unloaded > 0)
            _Notice(
              key: const Key('restore.partial'),
              icon: Icons.warning_amber_rounded,
              color: pal.amber,
              fill: pal.amberFill,
              border: pal.amberBorder,
              text: l10n.restorePartialNotice(state.unloaded, state.toLoad!),
              action: TextButton(
                key: const Key('restore.partial.retry'),
                onPressed: () => unawaited(widget.run.start()),
                child: Text(
                  l10n.retry,
                  style: TextStyle(
                    color: pal.amber,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
          if (summary.needsAction > 0)
            _Notice(
              key: const Key('restore.action'),
              icon: Icons.shield_outlined,
              color: pal.lime,
              textColor: pal.limeSoft,
              fill: pal.noticeFill,
              border: pal.noticeBorder,
              text: l10n.restoreActionNotice(summary.needsAction),
            ),
          _LimeButton(
            key: const Key('restore.close'),
            label: l10n.closeButtonLabel,
            onPressed: _close,
          ),
        ];
    }
  }
}

/// Space the sheet's sections 18 apart (the handoff's `gap: 18`).
List<Widget> _gapped(List<Widget> children) => [
  for (var i = 0; i < children.length; i++) ...[
    if (i > 0) const SizedBox(height: 18),
    children[i],
  ],
];

String _stageLabel(AppLocalizations l10n, RestoreRunState state, int stage) {
  final done = state.stages[stage] == RestoreStage.done;
  return switch (stage) {
    0 => done ? l10n.restoreStageConnected : l10n.restoreStageConnecting,
    1 =>
      done && state.found != null
          ? l10n.restoreStageFound(state.found!)
          : l10n.restoreStageRequesting,
    _ => l10n.restoreStageLoading,
  };
}

class _Header extends StatelessWidget {
  const _Header({required this.state});

  final RestoreRunState state;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final pal = RestorePalette.of(context);
    final (String title, String subtitle) = switch (state.outcome) {
      RestoreOutcome.failed => (
        l10n.restoreFailedTitle,
        l10n.restoreFailedSubtitle,
      ),
      RestoreOutcome.restored => (
        l10n.restoreDoneTitle,
        state.found == 0
            ? l10n.restoreDoneEmptySubtitle
            : l10n.restoreDoneSubtitle,
      ),
      RestoreOutcome.running => (
        l10n.restoreSheetTitle,
        state.found != null && (state.toLoad ?? 0) > 0
            ? l10n.restoreSheetLoading(state.loaded, state.toLoad!)
            : l10n.restoreSheetWaiting,
      ),
    };
    final Widget icon = switch (state.outcome) {
      RestoreOutcome.running => _Disc(
        fill: pal.iconFill,
        border: pal.iconBorder,
        child: Icon(Icons.sync, size: 20, color: pal.lime),
      ),
      RestoreOutcome.failed => _Disc(
        fill: pal.errorIconFill,
        child: Icon(Icons.error_outline, size: 20, color: pal.error),
      ),
      RestoreOutcome.restored => _Disc(
        fill: pal.lime,
        child: Icon(Icons.check_rounded, size: 21, color: pal.onLime),
      ),
    };
    return Row(
      children: [
        icon,
        const SizedBox(width: 13),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(
                  color: pal.text,
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: TextStyle(color: pal.textSecondary, fontSize: 13),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _Disc extends StatelessWidget {
  const _Disc({required this.fill, required this.child, this.border});

  final Color fill;
  final Color? border;
  final Widget child;

  @override
  Widget build(BuildContext context) => Container(
    width: 42,
    height: 42,
    alignment: Alignment.center,
    decoration: BoxDecoration(
      color: fill,
      shape: BoxShape.circle,
      border: border == null ? null : Border.all(color: border!),
    ),
    child: child,
  );
}

/// One bar for the whole restore, never moving back (the run guarantees it).
class _Bar extends StatelessWidget {
  const _Bar({required this.progress});

  final double progress;

  @override
  Widget build(BuildContext context) {
    final pal = RestorePalette.of(context);
    final still = MediaQuery.of(context).disableAnimations;
    return TweenAnimationBuilder<double>(
      tween: Tween(end: progress),
      duration: still ? Duration.zero : const Duration(milliseconds: 300),
      curve: Curves.easeOut,
      builder:
          (_, value, __) => ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              value: value,
              minHeight: 4,
              color: pal.lime,
              backgroundColor: pal.barTrack,
            ),
          ),
    );
  }
}

class _Stages extends StatelessWidget {
  const _Stages({required this.state});

  final RestoreRunState state;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final stages = state.stages;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < stages.length; i++) ...[
          if (i > 0) const SizedBox(height: 4),
          _StageRow(
            key: Key('restore.stage.$i'),
            stage: stages[i],
            label: _stageLabel(l10n, state, i),
            // The counter lives in the loading row, once the total is known.
            counter:
                i == 2 &&
                        stages[i] == RestoreStage.active &&
                        state.toLoad != null
                    ? (state.loaded, state.toLoad!)
                    : null,
          ),
        ],
      ],
    );
  }
}

class _StageRow extends StatelessWidget {
  const _StageRow({
    super.key,
    required this.stage,
    required this.label,
    this.counter,
  });

  final RestoreStage stage;
  final String label;
  final (int, int)? counter;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final pal = RestorePalette.of(context);
    final still = MediaQuery.of(context).disableAnimations;
    final (Color? fill, Color? border) = switch (stage) {
      RestoreStage.active => (pal.activeFill, pal.activeBorder),
      RestoreStage.failed => (pal.errorFill, pal.errorBorder),
      _ => (null, null),
    };
    final emphasised =
        stage == RestoreStage.active || stage == RestoreStage.failed;
    final counter = this.counter;
    return AnimatedContainer(
      duration: still ? Duration.zero : const Duration(milliseconds: 200),
      padding: const EdgeInsets.symmetric(vertical: 11, horizontal: 12),
      decoration: BoxDecoration(
        color: fill ?? Colors.transparent,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: border ?? Colors.transparent),
      ),
      child: Row(
        children: [
          SizedBox(width: 22, height: 22, child: _indicator(pal, still)),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 14,
                fontWeight: emphasised ? FontWeight.w600 : FontWeight.w400,
                color: switch (stage) {
                  RestoreStage.pending => pal.textPending,
                  RestoreStage.done => pal.textSecondary,
                  _ => pal.text,
                },
              ),
            ),
          ),
          if (counter != null)
            Semantics(
              label: l10n.restoreLoadingCountSemantics(counter.$1, counter.$2),
              excludeSemantics: true,
              child: Text(
                '${counter.$1}/${counter.$2}',
                style: TextStyle(
                  fontFamily: AppFonts.figures,
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: pal.limeSoft,
                ),
              ),
            ),
          if (stage == RestoreStage.failed)
            Text(
              l10n.restoreStageNoResponse,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: pal.errorDetail,
              ),
            ),
        ],
      ),
    );
  }

  Widget _indicator(RestorePalette pal, bool still) {
    switch (stage) {
      case RestoreStage.pending:
        return DecoratedBox(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: pal.pendingRing, width: 1.5),
          ),
        );
      case RestoreStage.active:
        // Without animations the ring stands still, all lime.
        if (still) {
          return DecoratedBox(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: pal.lime, width: 2),
            ),
          );
        }
        return CircularProgressIndicator(
          strokeWidth: 2,
          color: pal.lime,
          backgroundColor: pal.ringTrack,
        );
      case RestoreStage.done:
        return DecoratedBox(
          decoration: BoxDecoration(color: pal.lime, shape: BoxShape.circle),
          child: Icon(Icons.check_rounded, size: 13, color: pal.onLime),
        );
      case RestoreStage.failed:
        return DecoratedBox(
          decoration: BoxDecoration(
            color: pal.errorMarkFill,
            shape: BoxShape.circle,
          ),
          child: Icon(Icons.close_rounded, size: 12, color: pal.error),
        );
    }
  }
}

/// `Revisa tu conexión… desde Cuenta.` with the screen's name in bold.
class _FailureParagraph extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final pal = RestorePalette.of(context);
    const mark = '\u0000';
    final parts = l10n.restoreFailedBody(mark).split(mark);
    final base = TextStyle(color: pal.textSecondary, fontSize: 13, height: 1.55);
    return Text.rich(
      TextSpan(
        style: base,
        children: [
          for (var i = 0; i < parts.length; i++) ...[
            if (i > 0)
              TextSpan(
                text: l10n.accountScreenTitle,
                style: TextStyle(
                  color: pal.emphasis,
                  fontWeight: FontWeight.w600,
                ),
              ),
            TextSpan(text: parts[i]),
          ],
        ],
      ),
    );
  }
}

class _Summary extends StatelessWidget {
  const _Summary({required this.found, required this.summary});

  final int found;
  final RestoreSummary summary;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Row(
      children: [
        _Figure(value: '$found', label: l10n.restoreSummaryOrders),
        const SizedBox(width: 8),
        _Figure(
          value: '${summary.inProgress}',
          label: l10n.restoreSummaryInProgress,
        ),
      ],
    );
  }
}

class _Figure extends StatelessWidget {
  const _Figure({required this.value, required this.label});

  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    final pal = RestorePalette.of(context);
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 13, horizontal: 14),
        decoration: BoxDecoration(
          color: pal.card,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: pal.cardBorder),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              value,
              style: TextStyle(
                fontFamily: AppFonts.figures,
                fontSize: 22,
                fontWeight: FontWeight.w700,
                color: pal.text,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: pal.textSecondary, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }
}

class _Notice extends StatelessWidget {
  const _Notice({
    super.key,
    required this.icon,
    required this.color,
    required this.fill,
    required this.border,
    required this.text,
    this.textColor,
    this.action,
  });

  final IconData icon;
  final Color color;
  final Color? textColor;
  final Color fill;
  final Color border;
  final String text;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 11, horizontal: 13),
      decoration: BoxDecoration(
        color: fill,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: border),
      ),
      child: Row(
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: TextStyle(color: textColor ?? color, fontSize: 13),
            ),
          ),
          if (action != null) action!,
        ],
      ),
    );
  }
}

class _LimeButton extends StatelessWidget {
  const _LimeButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
  });

  final String label;
  final IconData? icon;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final pal = RestorePalette.of(context);
    return FilledButton(
      onPressed: onPressed,
      style: FilledButton.styleFrom(
        backgroundColor: pal.lime,
        foregroundColor: pal.onLime,
        padding: const EdgeInsets.all(15),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (icon != null) ...[Icon(icon, size: 16), const SizedBox(width: 8)],
          Text(label),
        ],
      ),
    );
  }
}

class _OutlineButton extends StatelessWidget {
  const _OutlineButton({
    super.key,
    required this.label,
    required this.onPressed,
  });

  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final pal = RestorePalette.of(context);
    return OutlinedButton(
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        foregroundColor: pal.emphasis,
        side: BorderSide(color: pal.outlineBorder),
        padding: const EdgeInsets.all(13),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        textStyle: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600),
      ),
      child: Text(label),
    );
  }
}

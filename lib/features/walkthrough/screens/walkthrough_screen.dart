import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:mostro/core/app_routes.dart';
import 'package:mostro/core/app_theme.dart';
import 'package:mostro/core/automation/automation_id.dart';
import 'package:mostro/core/automation/automation_ids.dart';
import 'package:mostro/features/order/widgets/order_detail_cards.dart';
import 'package:mostro/features/walkthrough/providers/node_prefetch_provider.dart';
import 'package:mostro/features/walkthrough/walkthrough_slides.dart';
import 'package:mostro/features/walkthrough/widgets/walkthrough_art.dart';
import 'package:mostro/l10n/app_localizations.dart';
import 'package:mostro/shared/widgets/redesign_app_bar.dart';

/// First-run walkthrough: six slides explaining Mostro.
///
/// Shown once, while `firstRunComplete` is `false`. Done (last slide) and
/// Skip (any other) lead to the node choice ([AppRoute.chooseNode]), which
/// completes the first run. Next and Back, a horizontal swipe and the arrow
/// keys move between slides. Meanwhile the nodes' data downloads in the
/// background ([firstRunNodePrefetchProvider]), so that choice opens filled.
class WalkthroughScreen extends ConsumerStatefulWidget {
  const WalkthroughScreen({super.key});

  @override
  ConsumerState<WalkthroughScreen> createState() => _WalkthroughScreenState();
}

/// A horizontal drag at least this long turns the slide, as in the handoff.
const _swipeDistance = 40.0;

/// The handoff draws a 184 px illustration on a 340 x 720 screen. Every slide
/// keeps that proportion, on whichever side of the screen binds first, and a
/// slide with more text scrolls rather than shrinking its art.
const _artWidthShare = 184 / 340;
const _artHeightShare = 184 / 720;

/// Thickness of a progress segment.
const _progressHeight = 4.0;

const _backSize = 48.0;
const _pill = Radius.circular(999);
const _cardRadius = BorderRadius.all(Radius.circular(18));

class _WalkthroughScreenState extends ConsumerState<WalkthroughScreen> {
  int _index = 0;
  double _dragDx = 0;

  void _go(int index, int count) {
    if (index < 0 || index >= count || index == _index) return;
    setState(() => _index = index);
  }

  void _onDragEnd(DragEndDetails _, int count) {
    if (_dragDx.abs() >= _swipeDistance) {
      _go(_dragDx < 0 ? _index + 1 : _index - 1, count);
    }
    _dragDx = 0;
  }

  void _finish() => context.go(AppRoute.chooseNode);

  @override
  Widget build(BuildContext context) {
    ref.watch(firstRunNodePrefetchProvider);
    final book = OrderBookPalette.of(context);
    final l10n = AppLocalizations.of(context);
    final slides = walkthroughSlides(l10n);
    final count = slides.length;
    final isFirst = _index == 0;
    final isLast = _index == count - 1;

    return Scaffold(
      backgroundColor: book.bg,
      body: SafeArea(
        child: CallbackShortcuts(
          bindings: {
            const SingleActivator(LogicalKeyboardKey.arrowRight):
                () => _go(_index + 1, count),
            const SingleActivator(LogicalKeyboardKey.arrowLeft):
                () => _go(_index - 1, count),
          },
          child: Focus(
            autofocus: true,
            child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              onHorizontalDragStart: (_) => _dragDx = 0,
              onHorizontalDragUpdate: (d) => _dragDx += d.delta.dx,
              onHorizontalDragEnd: (d) => _onDragEnd(d, count),
              onHorizontalDragCancel: () => _dragDx = 0,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: redesignSidePadding,
                ),
                child: Column(
                  children: [
                    const SizedBox(height: 6),
                    _Progress(current: _index, total: count),
                    Expanded(
                      child: SingleChildScrollView(
                        // A new slide starts at its top.
                        key: ValueKey(_index),
                        child: _SlideBody(slide: slides[_index]),
                      ),
                    ),
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        if (!isFirst) ...[
                          _BackButton(onPressed: () => _go(_index - 1, count)),
                          const SizedBox(width: 10),
                        ],
                        Expanded(
                          child: OrderPrimaryButton(
                            label: isLast ? l10n.done : l10n.walkthroughNext,
                            onPressed:
                                isLast ? _finish : () => _go(_index + 1, count),
                          ).withAutomationId(
                            isLast
                                ? AutomationIds.walkthroughDone
                                : AutomationIds.walkthroughNext,
                          ),
                        ),
                      ],
                    ),
                    // Skipping leaves without consequence: a link under the
                    // actions (DS-CMP-20). The last slide has nothing left to
                    // skip, and keeps the space so the button does not jump.
                    Visibility(
                      visible: !isLast,
                      maintainSize: true,
                      maintainAnimation: true,
                      maintainState: true,
                      child: _SkipLink(
                        label: l10n.skip,
                        onPressed: _finish,
                      ).withAutomationId(AutomationIds.walkthroughSkip),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// One segment per slide, filled up to the current one, over the "n / N"
/// counter. A screen reader hears "Step n of N" instead.
class _Progress extends StatelessWidget {
  const _Progress({required this.current, required this.total});

  final int current;
  final int total;

  @override
  Widget build(BuildContext context) {
    final book = OrderBookPalette.of(context);
    final l10n = AppLocalizations.of(context);
    return Semantics(
      label: l10n.walkthroughStepSemantics(current + 1, total),
      child: ExcludeSemantics(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                for (var i = 0; i < total; i++) ...[
                  if (i > 0) const SizedBox(width: 6),
                  Expanded(
                    child: Container(
                      height: _progressHeight,
                      decoration: BoxDecoration(
                        color: i <= current ? book.limeText : book.divider,
                        borderRadius: const BorderRadius.all(_pill),
                      ),
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 14),
            Text(
              l10n.walkthroughStepCounter(current + 1, total),
              style: TextStyle(
                fontFamily: AppFonts.figures,
                fontSize: 13,
                fontWeight: FontWeight.w500,
                fontFeatures: const [FontFeature.tabularFigures()],
                color: book.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SlideBody extends StatelessWidget {
  const _SlideBody({required this.slide});

  final WalkthroughSlide slide;

  @override
  Widget build(BuildContext context) {
    final book = OrderBookPalette.of(context);
    final screen = MediaQuery.sizeOf(context);
    final artSize = math.min(
      screen.width * _artWidthShare,
      screen.height * _artHeightShare,
    );
    final body = TextStyle(fontSize: 14, height: 1.5, color: book.textBody);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // The handoff's margins around the art.
        const SizedBox(height: 18),
        Center(
          child: WalkthroughArt(
            key: ValueKey(slide.art),
            asset: slide.art,
            size: artSize,
            flow: slide.flow,
            bolt: slide.bolt,
          ),
        ),
        const SizedBox(height: 20),
        // Announced when the slide changes under a screen reader.
        Semantics(
          header: true,
          liveRegion: true,
          child: Text(
            slide.title,
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w600,
              height: 1.15,
              color: book.textPrimary,
            ),
          ),
        ),
        const SizedBox(height: 14),
        for (final paragraph in slide.paragraphs)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Text(paragraph, style: body),
          ),
        for (final mode in slide.modes)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: _ModeCard(mode: mode),
          ),
        if (slide.footer case final footer?)
          Padding(
            padding: const EdgeInsets.only(top: 6, bottom: 10),
            child: Text(footer, style: body),
          ),
      ],
    );
  }
}

/// A privacy mode: its name in lime over what it means.
class _ModeCard extends StatelessWidget {
  const _ModeCard({required this.mode});

  final WalkthroughMode mode;

  @override
  Widget build(BuildContext context) {
    final book = OrderBookPalette.of(context);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: book.surface,
        border: Border.all(color: book.border),
        borderRadius: _cardRadius,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            mode.name,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: book.limeText,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            mode.description,
            style: TextStyle(
              fontSize: 13,
              height: 1.4,
              color: book.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

/// The round, outlined way back to the previous slide.
class _BackButton extends StatelessWidget {
  const _BackButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final book = OrderBookPalette.of(context);
    return IconButton(
      onPressed: onPressed,
      tooltip: MaterialLocalizations.of(context).backButtonTooltip,
      icon: Icon(Icons.chevron_left_rounded, size: 24, color: book.textPrimary),
      style: IconButton.styleFrom(
        fixedSize: const Size.square(_backSize),
        shape: CircleBorder(side: BorderSide(color: book.border)),
      ),
    ).withAutomationId(AutomationIds.walkthroughBack);
  }
}

/// Skip, as a full-width text link with a 48 dp target (DS-CMP-6).
class _SkipLink extends StatelessWidget {
  const _SkipLink({required this.label, required this.onPressed});

  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final book = OrderBookPalette.of(context);
    return TextButton(
      onPressed: onPressed,
      style: TextButton.styleFrom(
        foregroundColor: book.textSecondary,
        minimumSize: const Size.fromHeight(_backSize),
        // A button's textStyle replaces the theme's: name the family.
        textStyle: const TextStyle(
          fontFamily: AppFonts.ui,
          fontSize: 13,
          fontWeight: FontWeight.w500,
        ),
      ),
      child: Text(label),
    );
  }
}

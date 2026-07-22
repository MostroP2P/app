import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:introduction_screen/introduction_screen.dart';

import 'package:mostro/core/app_routes.dart';
import 'package:mostro/core/app_theme.dart';
import 'package:mostro/features/walkthrough/providers/first_run_provider.dart';
import 'package:mostro/features/walkthrough/utils/highlight_config.dart';
import 'package:mostro/l10n/app_localizations.dart';

/// First-run walkthrough. Six slides explaining Mostro concepts.
///
/// Shown once: when `firstRunComplete` is `false`.
/// After Done or Skip → marks first run complete → navigates to home.
class WalkthroughScreen extends ConsumerWidget {
  const WalkthroughScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final colors = theme.extension<AppColors>();
    final green = colors?.mostroGreen ?? const Color(0xFF8CC63F);
    final l10n = AppLocalizations.of(context);
    final screenWidth = MediaQuery.sizeOf(context).width;
    final bodyPadding = screenWidth * 0.06;

    final baseBodyStyle = theme.textTheme.bodyMedium!.copyWith(
      fontSize: 16,
      color: Colors.white70,
      height: 1.5,
    );
    final titleStyle = theme.textTheme.titleLarge!.copyWith(
      fontSize: 22,
      fontWeight: FontWeight.bold,
      color: Colors.white,
    );

    final pages = _buildPages(
      context: context,
      green: green,
      bodyPadding: bodyPadding,
      baseBodyStyle: baseBodyStyle,
      titleStyle: titleStyle,
    );

    return IntroductionScreen(
      pages: pages,
      onDone: () => _onIntroEnd(context, ref),
      onSkip: () => _onIntroEnd(context, ref),
      showSkipButton: true,
      showBackButton: true,
      back: const Icon(Icons.arrow_back, color: Colors.white),
      next: const Icon(Icons.arrow_forward, color: Colors.white),
      skip: Text(
        l10n.skip,
        style: theme.textTheme.labelLarge!.copyWith(color: Colors.white),
      ),
      done: Text(
        l10n.done,
        style: theme.textTheme.labelLarge!.copyWith(
          color: green,
          fontWeight: FontWeight.bold,
        ),
      ),
      dotsDecorator: DotsDecorator(
        activeColor: theme.primaryColor,
        color: theme.cardColor,
        size: const Size(8, 8),
        activeSize: const Size(16, 8),
        activeShape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(4),
        ),
        shape: const CircleBorder(),
      ),
      globalBackgroundColor: theme.scaffoldBackgroundColor,
    );
  }

  List<PageViewModel> _buildPages({
    required BuildContext context,
    required Color green,
    required double bodyPadding,
    required TextStyle baseBodyStyle,
    required TextStyle titleStyle,
  }) {
    final l10n = AppLocalizations.of(context);
    final slides = [
      (
        title: l10n.walkthroughSlideOneTitle,
        body: l10n.walkthroughSlideOneBody,
        image: 'assets/images/wt-1.png',
      ),
      (
        title: l10n.walkthroughSlideTwoTitle,
        body: l10n.walkthroughSlideTwoBody,
        image: 'assets/images/wt-2.png',
      ),
      (
        title: l10n.walkthroughSlideThreeTitle,
        body: l10n.walkthroughSlideThreeBody,
        image: 'assets/images/wt-3.png',
      ),
      (
        title: l10n.walkthroughSlideFourTitle,
        body: l10n.walkthroughSlideFourBody,
        image: 'assets/images/wt-4.png',
      ),
      (
        title: l10n.walkthroughSlideFiveTitle,
        body: l10n.walkthroughSlideFiveBody,
        image: 'assets/images/wt-5.png',
      ),
      (
        title: l10n.walkthroughSlideSixTitle,
        body: l10n.walkthroughSlideSixBody,
        image: 'assets/images/wt-6.png',
      ),
    ];

    return List.generate(slides.length, (i) {
      final slide = slides[i];
      final highlightedBody = HighlightConfig.buildHighlighted(
        slide.body,
        i,
        green,
        baseBodyStyle,
      );

      return PageViewModel(
        titleWidget: Padding(
          padding: EdgeInsets.symmetric(horizontal: bodyPadding),
          child: Text(slide.title, style: titleStyle, textAlign: TextAlign.center),
        ),
        bodyWidget: Padding(
          padding: EdgeInsets.symmetric(
            horizontal: bodyPadding,
            vertical: AppSpacing.sm,
          ),
          child: RichText(
            text: highlightedBody,
            textAlign: TextAlign.center,
          ),
        ),
        image: Padding(
          padding: const EdgeInsets.only(top: 30),
          child: Image.asset(
            slide.image,
            height: 200,
            fit: BoxFit.contain,
            errorBuilder: (_, __, ___) => const SizedBox(height: 200),
          ),
        ),
      );
    });
  }

  Future<void> _onIntroEnd(BuildContext context, WidgetRef ref) async {
    await ref.read(firstRunProvider.notifier).markFirstRunComplete();
    ref.read(backupReminderProvider.notifier).showBackupReminder();
    if (context.mounted) {
      context.go(AppRoute.home);
    }
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:introduction_screen/introduction_screen.dart';

import 'package:mostro/core/app_routes.dart';
import 'package:mostro/core/app_theme.dart';
import 'package:mostro/features/walkthrough/providers/first_run_provider.dart';
import 'package:mostro/features/walkthrough/utils/highlight_config.dart';

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
        'Skip',
        style: theme.textTheme.labelLarge!.copyWith(color: Colors.white),
      ),
      done: Text(
        'Done',
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
    const slides = [
      (
        title: 'Trade Bitcoin freely — no KYC',
        body:
            'Mostro is a peer-to-peer exchange that lets you trade Bitcoin for any currency and payment method — no KYC, and no need to give your data to anyone. It\'s built on Nostr, which makes it censorship-resistant. No one can stop you from trading.',
        image: 'assets/images/wt-1.png',
      ),
      (
        title: 'Privacy by default',
        body:
            'Mostro generates a new identity for every exchange, so your trades can\'t be linked. You can also decide how private you want to be:\n• Reputation mode – Lets others see your successful trades and trust level.\n• Full privacy mode – No reputation is built, but your activity is completely anonymous.\nSwitch modes anytime from the Account screen, where you should also save your secret words — they\'re the only way to recover your account.',
        image: 'assets/images/wt-2.png',
      ),
      (
        title: 'Security at every step',
        body:
            'Mostro uses Hold Invoices: sats stay in the seller\'s wallet until the end of the trade. This protects both sides. The app is also designed to be intuitive and easy for all kinds of users.',
        image: 'assets/images/wt-3.png',
      ),
      (
        title: 'Fully encrypted chat',
        body:
            'Each trade has its own private chat, end-to-end encrypted. Only the two users involved can read it. In case of a dispute, you can give the shared key to an admin to help resolve the issue.',
        image: 'assets/images/wt-4.png',
      ),
      (
        title: 'Take an offer',
        body:
            'Browse the order book, choose an offer that works for you, and follow the trade flow step by step. You\'ll be able to check the other user\'s profile, chat securely, and complete the trade with ease.',
        image: 'assets/images/wt-5.png',
      ),
      (
        title: 'Can\'t find what you need?',
        body:
            'You can also create your own offer and wait for someone to take it. Set the amount and preferred payment method — Mostro handles the rest.',
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

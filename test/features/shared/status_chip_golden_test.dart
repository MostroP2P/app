import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mostro/core/app_theme.dart';
import 'package:mostro/shared/widgets/status_chip.dart';

import '../../support/golden_harness.dart';

/// Every status palette paired with a representative label.
const _statusVariants = <(String, (Color, Color))>[
  ('Pending', AppColors.statusPending),
  ('Waiting', AppColors.statusWaiting),
  ('Active', AppColors.statusActive),
  ('Success', AppColors.statusSuccess),
  ('Dispute', AppColors.statusDispute),
  ('Settled', AppColors.statusSettled),
  ('Inactive', AppColors.statusInactive),
];

/// Gallery of every chip variant, keyed so the golden captures just the chips.
Widget _gallery() {
  return Padding(
    key: const ValueKey('chip-gallery'),
    padding: const EdgeInsets.all(AppSpacing.md),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final (label, (bg, fg)) in _statusVariants)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.xs),
            child: StatusChip(label: label, background: bg, foreground: fg),
          ),
        const SizedBox(height: AppSpacing.sm),
        const RoleBadge(label: 'Created by you'),
        const SizedBox(height: AppSpacing.xs),
        const RoleBadge(label: 'Taken by you'),
      ],
    ),
  );
}

void main() {
  group('StatusChip / RoleBadge goldens', () {
    testWidgets('dark theme', (tester) async {
      await pumpForGolden(tester, _gallery(), brightness: Brightness.dark);
      await expectLater(
        find.byKey(const ValueKey('chip-gallery')),
        matchesGoldenFile('goldens/chip_gallery_dark.png'),
      );
    });

    testWidgets('light theme', (tester) async {
      await pumpForGolden(tester, _gallery(), brightness: Brightness.light);
      await expectLater(
        find.byKey(const ValueKey('chip-gallery')),
        matchesGoldenFile('goldens/chip_gallery_light.png'),
      );
    });
  });
}

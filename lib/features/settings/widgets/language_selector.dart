import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:mostro/core/app_theme.dart';
import 'package:mostro/features/settings/providers/settings_provider.dart';
import 'package:mostro/l10n/app_localizations.dart';

// ── Language data ─────────────────────────────────────────────────────────────

typedef _LangEntry = ({String code, String name, String native});

const List<_LangEntry> _languages = [
  (code: 'en', name: 'English', native: 'English'),
  (code: 'es', name: 'Spanish', native: 'Español'),
  (code: 'it', name: 'Italian', native: 'Italiano'),
  (code: 'fr', name: 'French', native: 'Français'),
  (code: 'de', name: 'German', native: 'Deutsch'),
];

// ── Widget ────────────────────────────────────────────────────────────────────

/// Bottom-sheet language picker.
///
/// Show via [showLanguageSelector] from a [ConsumerWidget] callback.
class LanguageSelector extends ConsumerWidget {
  const LanguageSelector({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentCode = ref.watch(settingsProvider).language;
    final colorsRaw = Theme.of(context).extension<AppColors>();
    if (colorsRaw == null) throw StateError('AppColors theme extension must be registered');
    final colors = colorsRaw;

    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.lg,
              vertical: AppSpacing.md,
            ),
            child: Row(
              children: [
                Text(
                  AppLocalizations.of(context).selectLanguageTitle,
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          ...List.generate(_languages.length, (index) {
            final lang = _languages[index];
            final isSelected = lang.code == currentCode;
            return ListTile(
              title: Text(
                lang.native,
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: isSelected ? colors.mostroGreen : null,
                    ),
              ),
              subtitle: Text(
                lang.name,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              trailing: isSelected
                  ? Icon(Icons.check_circle, color: colors.mostroGreen)
                  : null,
              onTap: () {
                Navigator.of(context).pop();
                if (lang.code == currentCode) return;
                // Change locale after the sheet is gone. Changing it while the
                // bottom sheet is still mounted causes MostroApp to rebuild
                // with a new AppLocalizations before the sheet's widgets are
                // deactivated, triggering _dependents.isEmpty assertions.
                final notifier = ref.read(settingsProvider.notifier);
                WidgetsBinding.instance.addPostFrameCallback(
                  (_) => notifier.setLanguage(lang.code),
                );
              },
            );
          }),
          const SizedBox(height: AppSpacing.md),
        ],
      ),
    );
  }
}

// ── Helper ────────────────────────────────────────────────────────────────────

/// Show the [LanguageSelector] as a modal bottom sheet.
void showLanguageSelector(BuildContext context) {
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.card)),
    ),
    builder: (_) => const LanguageSelector(),
  );
}

/// Returns the native display name for a BCP-47 language code (e.g. "Español" for "es").
String languageNameForCode(String code) {
  final entry = _languages.firstWhere(
    (l) => l.code == code,
    orElse: () => (code: code, name: code, native: code),
  );
  return entry.native;
}

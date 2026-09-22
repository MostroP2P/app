import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:mostro/core/app_theme.dart';
import 'package:mostro/features/settings/providers/settings_provider.dart';
import 'package:mostro/l10n/app_localizations.dart';
import 'package:mostro/shared/widgets/mostro_modal.dart';

// ── Language data ─────────────────────────────────────────────────────────────

typedef _LangEntry = ({String code, String name, String native});

/// English and native name of every language the app ships, in picker order.
///
/// Only the names live here: which languages the picker lists comes from
/// [AppLocalizations.supportedLocales], i.e. from the `lib/l10n/app_*.arb`
/// files. A new ARB file therefore shows up in the picker (under its code)
/// even before it gets a row here, and `locale_lists_test.dart` fails until
/// it does.
const Map<String, ({String name, String native})> languageNames = {
  'en': (name: 'English', native: 'English'),
  'es': (name: 'Spanish', native: 'Español'),
  'it': (name: 'Italian', native: 'Italiano'),
  'fr': (name: 'French', native: 'Français'),
  'de': (name: 'German', native: 'Deutsch'),
  'nl': (name: 'Dutch', native: 'Nederlands'),
};

/// The picker rows: every supported locale, in [languageNames] order, with
/// any locale that has no names yet appended under its code.
final List<_LangEntry> _languages = () {
  final supported = {
    for (final l in AppLocalizations.supportedLocales) l.languageCode,
  };
  return [
    for (final MapEntry(key: code, value: n) in languageNames.entries)
      if (supported.contains(code))
        (code: code, name: n.name, native: n.native),
    for (final code in supported)
      if (!languageNames.containsKey(code))
        (code: code, name: code, native: code),
  ];
}();

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

    return MostroSheet(
      title: AppLocalizations.of(context).selectLanguageTitle,
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final lang in _languages)
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(
                lang.native,
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                      color:
                          lang.code == currentCode ? colors.mostroGreen : null,
                    ),
              ),
              subtitle: Text(
                lang.name,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              trailing: lang.code == currentCode
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
            ),
        ],
      ),
    );
  }
}

// ── Helper ────────────────────────────────────────────────────────────────────

/// Show the [LanguageSelector] as a modal bottom sheet.
void showLanguageSelector(BuildContext context) {
  showMostroSheet<void>(
    context: context,
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

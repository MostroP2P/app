import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:mostro/core/app_theme.dart';
import 'package:mostro/features/settings/providers/settings_provider.dart';

// ── Model ─────────────────────────────────────────────────────────────────────

class _FiatEntry {
  const _FiatEntry({
    required this.code,
    required this.name,
    required this.flag,
  });

  final String code;
  final String name;
  final String flag;

  factory _FiatEntry.fromJson(Map<String, dynamic> json) => _FiatEntry(
        code: (json['code'] as String?) ?? '',
        name: (json['name'] as String?) ?? '',
        flag: (json['flag'] as String?) ?? '',
      );
}

// ── Widget ────────────────────────────────────────────────────────────────────

class CurrencySelectorDialog extends ConsumerStatefulWidget {
  const CurrencySelectorDialog({super.key});

  @override
  ConsumerState<CurrencySelectorDialog> createState() =>
      _CurrencySelectorDialogState();
}

class _CurrencySelectorDialogState
    extends ConsumerState<CurrencySelectorDialog> {
  List<_FiatEntry> _allEntries = [];
  List<_FiatEntry> _filtered = [];
  final TextEditingController _searchController = TextEditingController();
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadCurrencies();
    _searchController.addListener(_onSearch);
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadCurrencies() async {
    try {
      final raw = await rootBundle.loadString('assets/data/fiat.json');
      final List<dynamic> parsed = json.decode(raw) as List<dynamic>;
      final entries = parsed
          .cast<Map<String, dynamic>>()
          .map(_FiatEntry.fromJson)
          .where((e) => e.code.isNotEmpty)
          .toList();
      if (mounted) {
        setState(() {
          _allEntries = entries;
          _filtered = entries;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _onSearch() {
    final query = _searchController.text.toLowerCase();
    setState(() {
      _filtered = _allEntries.where((e) {
        return e.code.toLowerCase().contains(query) ||
            e.name.toLowerCase().contains(query);
      }).toList();
    });
  }

  void _select(_FiatEntry entry) {
    ref.read(settingsProvider.notifier).setDefaultFiatCode(entry.code);
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppColors>()!;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Select Currency'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'Search currencies…',
                prefixIcon: Icon(Icons.search, color: colors.textSubtle),
              ),
            ),
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _filtered.isEmpty
                    ? Center(
                        child: Text(
                          'No currencies found',
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                      )
                    : ListView.builder(
                        itemCount: _filtered.length,
                        itemBuilder: (context, index) {
                          final entry = _filtered[index];
                          return ListTile(
                            leading: Text(
                              entry.flag,
                              style: const TextStyle(fontSize: 24),
                            ),
                            title: Text(
                              '${entry.code} — ${entry.name}',
                              style: Theme.of(context).textTheme.bodyLarge,
                            ),
                            onTap: () => _select(entry),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }
}

// ── Helper ────────────────────────────────────────────────────────────────────

/// Push the [CurrencySelectorDialog] as a full-screen route.
Future<void> showCurrencySelector(BuildContext context) {
  return Navigator.of(context).push<void>(
    MaterialPageRoute<void>(
      builder: (_) => const CurrencySelectorDialog(),
      fullscreenDialog: true,
    ),
  );
}

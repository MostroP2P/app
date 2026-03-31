import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

import 'package:mostro/core/app_theme.dart';
import 'package:mostro/features/settings/providers/settings_provider.dart';

// ── Local log level enum (mirrors Rust LogLevel) ──────────────────────────────

enum _LogLevel { debug, info, warning, error }

// ── Local log entry model ─────────────────────────────────────────────────────

class _LogEntry {
  const _LogEntry({
    required this.id,
    required this.level,
    required this.tag,
    required this.message,
    required this.timestamp,
  });

  final int id;
  final _LogLevel level;
  final String tag;
  final String message;
  final int timestamp; // Unix seconds
}

// ── Screen ────────────────────────────────────────────────────────────────────

class LogReportScreen extends ConsumerStatefulWidget {
  const LogReportScreen({super.key});

  @override
  ConsumerState<LogReportScreen> createState() => _LogReportScreenState();
}

class _LogReportScreenState extends ConsumerState<LogReportScreen> {
  // Sample data shown when no bridge is connected.
  // TODO(bridge): replace with stream from Rust log sink.
  static final List<_LogEntry> _mockEntries = [
    _LogEntry(
      id: 1,
      level: _LogLevel.info,
      tag: 'App',
      message: 'Application started successfully',
      timestamp: DateTime.now().millisecondsSinceEpoch ~/ 1000 - 120,
    ),
    _LogEntry(
      id: 2,
      level: _LogLevel.warning,
      tag: 'Relay',
      message: 'Connection to wss://nos.lol timed out, retrying…',
      timestamp: DateTime.now().millisecondsSinceEpoch ~/ 1000 - 60,
    ),
    _LogEntry(
      id: 3,
      level: _LogLevel.debug,
      tag: 'Order',
      message: 'Fetched 42 orders from relay',
      timestamp: DateTime.now().millisecondsSinceEpoch ~/ 1000 - 10,
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final loggingEnabled = ref.watch(settingsProvider).loggingEnabled;
    final colors = Theme.of(context).extension<AppColors>()!;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Log Report'),
        actions: [
          // Share logs
          IconButton(
            icon: const Icon(Icons.share_outlined),
            tooltip: 'Share logs',
            onPressed: () => _shareLogs(),
          ),
          // Toggle logging
          IconButton(
            icon: Icon(
              loggingEnabled
                  ? Icons.toggle_on_outlined
                  : Icons.toggle_off_outlined,
              color: loggingEnabled ? colors.mostroGreen : colors.textDisabled,
            ),
            tooltip: loggingEnabled ? 'Disable logging' : 'Enable logging',
            onPressed: () {
              ref
                  .read(settingsProvider.notifier)
                  .setLoggingEnabled(!loggingEnabled);
            },
          ),
        ],
      ),
      body: Column(
        children: [
          // Logging status banner
          AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            color: loggingEnabled
                ? colors.mostroGreen.withAlpha(30)
                : colors.backgroundElevated,
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.lg,
              vertical: AppSpacing.sm,
            ),
            child: Row(
              children: [
                Icon(
                  loggingEnabled
                      ? Icons.fiber_manual_record
                      : Icons.fiber_manual_record_outlined,
                  size: 12,
                  color: loggingEnabled
                      ? colors.mostroGreen
                      : colors.textDisabled,
                ),
                const SizedBox(width: AppSpacing.sm),
                Text(
                  loggingEnabled ? 'Logging enabled' : 'Logging disabled',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: loggingEnabled
                            ? colors.mostroGreen
                            : colors.textDisabled,
                      ),
                ),
              ],
            ),
          ),
          // Log entries
          Expanded(
            child: _mockEntries.isEmpty
                ? Center(
                    child: Text(
                      'No log entries',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.all(AppSpacing.md),
                    itemCount: _mockEntries.length,
                    itemBuilder: (context, index) {
                      return _LogEntryTile(
                        entry: _mockEntries[index],
                        colors: colors,
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Future<void> _shareLogs() async {
    final lines = _mockEntries.map((e) {
      final time = _formatTimestamp(e.timestamp);
      final level = e.level.name.toUpperCase().padRight(7);
      return '$time [$level] ${e.tag}: ${e.message}';
    }).join('\n');

    final content = 'Mostro Log Report\n'
        '=================\n'
        '$lines';

    try {
      await SharePlus.instance.share(ShareParams(text: content));
    } catch (e) {
      debugPrint('Failed to share logs: $e');
    }
  }
}

// ── Log entry tile ────────────────────────────────────────────────────────────

class _LogEntryTile extends StatelessWidget {
  const _LogEntryTile({required this.entry, required this.colors});

  final _LogEntry entry;
  final AppColors colors;

  @override
  Widget build(BuildContext context) {
    final (chipBg, chipFg) = _levelColors(entry.level);

    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: colors.backgroundCard,
        borderRadius: BorderRadius.circular(AppRadius.card),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              // Level chip
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.sm,
                  vertical: 2,
                ),
                decoration: BoxDecoration(
                  color: chipBg,
                  borderRadius: BorderRadius.circular(AppRadius.chip),
                ),
                child: Text(
                  entry.level.name.toUpperCase(),
                  style: TextStyle(
                    color: chipFg,
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              // Tag
              Text(
                entry.tag,
                style: const TextStyle(
                  fontFamily: 'monospace',
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                ),
              ),
              const Spacer(),
              // Timestamp
              Text(
                _formatTimestamp(entry.timestamp),
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            entry.message,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ],
      ),
    );
  }

  (Color, Color) _levelColors(_LogLevel level) {
    return switch (level) {
      _LogLevel.debug => (const Color(0xFF374151), const Color(0xFFD1D5DB)),
      _LogLevel.info => (const Color(0xFF1E3A8A), const Color(0xFF93C5FD)),
      _LogLevel.warning => (const Color(0xFF854D0E), const Color(0xFFFCD34D)),
      _LogLevel.error => (const Color(0xFF7F1D1D), const Color(0xFFFCA5A5)),
    };
  }
}

// ── Helpers ───────────────────────────────────────────────────────────────────

String _formatTimestamp(int unixSeconds) {
  final dt = DateTime.fromMillisecondsSinceEpoch(unixSeconds * 1000);
  final h = dt.hour.toString().padLeft(2, '0');
  final m = dt.minute.toString().padLeft(2, '0');
  final s = dt.second.toString().padLeft(2, '0');
  return '$h:$m:$s';
}

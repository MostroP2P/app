import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:share_plus/share_plus.dart';

import 'package:mostro/core/app_routes.dart';
import 'package:mostro/core/app_theme.dart';
import 'package:mostro/core/settings_palette.dart';
import 'package:mostro/features/settings/models/log_export.dart';
import 'package:mostro/features/settings/models/settings_rows.dart';
import 'package:mostro/features/settings/providers/log_provider.dart';
import 'package:mostro/features/settings/providers/settings_provider.dart';
import 'package:mostro/features/settings/widgets/settings_section.dart';
import 'package:mostro/l10n/app_localizations.dart';
import 'package:mostro/shared/utils/platform_int64.dart';
import 'package:mostro/shared/widgets/redesign_app_bar.dart';
import 'package:mostro/src/rust/api/types.dart';

/// Logs — handoff 10e.
///
/// Three levels in colour instead of one blue `INFO`: an error is findable by
/// scanning the list, which is the whole point of a diagnostic screen.
/// Subsystem chips filter, and the verbose switch left the app bar (where it
/// was an unlabelled toggle) for a footer row that states its cost.
class LogReportScreen extends ConsumerStatefulWidget {
  const LogReportScreen({super.key});

  @override
  ConsumerState<LogReportScreen> createState() => _LogReportScreenState();
}

class _LogReportScreenState extends ConsumerState<LogReportScreen> {
  /// Null is `Todos`.
  LogSubsystem? _filter;

  final _scroll = ScrollController();

  /// True while the user is reading back through the list; the newest entries
  /// then arrive behind a chip instead of yanking the view.
  bool _pinnedToNewest = true;

  /// The newest entry the user had in view while pinned; the chip appears
  /// only once something newer arrives while they read back.
  int? _seenNewestId;

  /// Entries the user has tapped open, by id — the message is clamped to
  /// three lines until then.
  final _expanded = <int>{};

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scroll.removeListener(_onScroll);
    _scroll.dispose();
    super.dispose();
  }

  /// The list is reversed, so "newest" is offset zero.
  void _onScroll() {
    final pinned = _scroll.offset <= 24;
    if (pinned != _pinnedToNewest) setState(() => _pinnedToNewest = pinned);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final book = OrderBookPalette.of(context);
    final loggingEnabled = ref.watch(settingsProvider).loggingEnabled;
    final all = ref.watch(logEntriesProvider).valueOrNull ?? const <LogEntry>[];
    final entries = _visible(all, _filter);
    final newestId = entries.isEmpty ? null : entries.first.id;
    if (_pinnedToNewest) _seenNewestId = newestId;
    final hasUnseen =
        !_pinnedToNewest && newestId != null && newestId != _seenNewestId;

    return Scaffold(
      backgroundColor: book.bg,
      appBar: redesignAppBar(
        context,
        title: l10n.logsScreenTitle,
        onBack:
            () =>
                context.canPop()
                    ? context.pop()
                    : context.go(AppRoute.settings),
        actions: [
          IconButton(
            icon: Icon(Icons.ios_share, size: 19, color: book.limeIcon),
            tooltip:
                entries.isNotEmpty
                    ? l10n.shareLogsTooltip
                    : l10n.noLogsToShareTooltip,
            // Exports what the active filter shows, redacted — never the
            // whole buffer, which the user cannot see to check.
            onPressed: entries.isNotEmpty ? () => _shareLogs(entries) : null,
          ),
          // An IconButton pads itself by 8; the rest lines the glyph up with
          // the content below.
          const SizedBox(width: redesignSidePadding - 8),
        ],
      ),
      body: Column(
        children: [
          _FilterRow(
            active: _filter,
            onChanged:
                (next) => setState(() {
                  _filter = next;
                  // A different filter is not a new log.
                  final visible = _visible(all, next);
                  _seenNewestId = visible.isEmpty ? null : visible.first.id;
                }),
          ),
          Expanded(
            child:
                entries.isEmpty
                    ? Center(
                      child: Text(
                        _filter == null
                            ? l10n.noLogEntriesMessage
                            : l10n.noLogsForFilter,
                        style: TextStyle(
                          fontSize: 12,
                          color: book.textSecondary,
                        ),
                      ),
                    )
                    : Stack(
                      children: [
                        ListView.separated(
                          controller: _scroll,
                          // `logEntriesProvider` yields newest first, so the
                          // list is reversed and offset zero is the newest.
                          reverse: true,
                          padding: const EdgeInsets.symmetric(
                            horizontal: redesignSidePadding,
                            vertical: 12,
                          ),
                          itemCount: entries.length,
                          separatorBuilder:
                              (_, __) => const SizedBox(height: 8),
                          itemBuilder: (context, index) {
                            final entry = entries[index];
                            // Reversed, so the "previous" entry in time is the
                            // one at the higher index.
                            final older =
                                index + 1 < entries.length
                                    ? entries[index + 1]
                                    : null;
                            return Column(
                              children: [
                                if (_startsNewMinute(entry, older))
                                  _TimeSeparator(entry: entry),
                                _LogEntryTile(
                                  entry: entry,
                                  expanded: _expanded.contains(entry.id),
                                  onTap:
                                      () => setState(() {
                                        _expanded.contains(entry.id)
                                            ? _expanded.remove(entry.id)
                                            : _expanded.add(entry.id);
                                      }),
                                ),
                              ],
                            );
                          },
                        ),
                        if (hasUnseen)
                          Positioned(
                            left: 0,
                            right: 0,
                            bottom: 12,
                            child: Center(
                              child: _NewLogsChip(
                                onTap:
                                    () => _scroll.animateTo(
                                      0,
                                      duration: const Duration(
                                        milliseconds: 240,
                                      ),
                                      curve: Curves.easeOut,
                                    ),
                              ),
                            ),
                          ),
                      ],
                    ),
          ),
          _VerboseBar(
            value: loggingEnabled,
            onChanged:
                (v) => ref.read(settingsProvider.notifier).setLoggingEnabled(v),
          ),
        ],
      ),
    );
  }

  static List<LogEntry> _visible(List<LogEntry> all, LogSubsystem? filter) =>
      filter == null
          ? all
          : all.where((e) => logSubsystem(e.tag) == filter).toList();

  /// One separator per minute with activity.
  static bool _startsNewMinute(LogEntry entry, LogEntry? older) {
    if (older == null) return true;
    return _minuteOf(entry) != _minuteOf(older);
  }

  static int _minuteOf(LogEntry entry) =>
      platformInt64ToInt(entry.timestamp) ~/ 60;

  Future<void> _shareLogs(List<LogEntry> entries) async {
    final heading = AppLocalizations.of(context).logReportShareHeading;
    final lines = entries
        .map((e) {
          final time = formatLogTimestamp(platformInt64ToInt(e.timestamp));
          final level = e.level.name.toUpperCase().padRight(7);
          return '$time [$level] ${sanitizeForShare(e.tag)}: '
              '${sanitizeForShare(e.message)}';
        })
        .join('\n');

    try {
      await SharePlus.instance.share(
        ShareParams(text: '$heading\n${'=' * heading.length}\n$lines'),
      );
    } catch (e) {
      debugPrint('Failed to share logs: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(AppLocalizations.of(context).failedToShareLogsMessage),
        ),
      );
    }
  }
}

// ── Filter row ────────────────────────────────────────────────────────────────

class _FilterRow extends StatelessWidget {
  const _FilterRow({required this.active, required this.onChanged});

  /// Null is `Todos`.
  final LogSubsystem? active;
  final ValueChanged<LogSubsystem?> onChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final chips = <(LogSubsystem?, String)>[
      (null, l10n.logFilterAll),
      (LogSubsystem.relays, l10n.logFilterRelays),
      (LogSubsystem.orders, l10n.logFilterOrders),
      (LogSubsystem.payments, l10n.logFilterPayments),
    ];
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.fromLTRB(
        redesignSidePadding,
        0,
        redesignSidePadding,
        12,
      ),
      child: Row(
        children: [
          for (final (subsystem, label) in chips)
            Padding(
              padding: const EdgeInsets.only(right: 7),
              child: _FilterChip(
                label: label,
                selected: subsystem == active,
                onTap: () => onChanged(subsystem),
              ),
            ),
        ],
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final pal = SettingsPalette.of(context);
    return Material(
      color: selected ? pal.chipActiveBg : pal.chipIdleBg,
      borderRadius: const BorderRadius.all(Radius.circular(999)),
      child: InkWell(
        onTap: onTap,
        borderRadius: const BorderRadius.all(Radius.circular(999)),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: const BorderRadius.all(Radius.circular(999)),
            border: Border.all(
              color: selected ? pal.chipActiveBorder : pal.chipIdleBorder,
            ),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
              color: selected ? pal.chipActiveInk : pal.chipIdleInk,
            ),
          ),
        ),
      ),
    );
  }
}

// ── Time separator ────────────────────────────────────────────────────────────

class _TimeSeparator extends StatelessWidget {
  const _TimeSeparator({required this.entry});

  final LogEntry entry;

  @override
  Widget build(BuildContext context) {
    final book = OrderBookPalette.of(context);
    final pal = SettingsPalette.of(context);
    final at =
        DateTime.fromMillisecondsSinceEpoch(
          platformInt64ToInt(entry.timestamp) * 1000,
        ).toLocal();
    return Padding(
      padding: const EdgeInsets.fromLTRB(2, 2, 2, 4),
      child: Row(
        children: [
          Text(
            '${at.hour.toString().padLeft(2, '0')}:'
            '${at.minute.toString().padLeft(2, '0')}',
            style: TextStyle(
              fontFamily: AppFonts.figures,
              fontSize: 10,
              fontWeight: FontWeight.w500,
              color: pal.placeholder,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(child: Divider(height: 1, color: book.border)),
          const SizedBox(width: 8),
          Text(
            _relative(AppLocalizations.of(context), at),
            style: TextStyle(fontSize: 10, color: pal.placeholder),
          ),
        ],
      ),
    );
  }

  static String _relative(AppLocalizations l10n, DateTime at) {
    final diff = DateTime.now().difference(at);
    if (diff.isNegative || diff.inMinutes < 1) return l10n.justNow;
    if (diff.inMinutes < 60) return l10n.minutesAgo(diff.inMinutes);
    if (diff.inHours < 24) return l10n.hoursAgo(diff.inHours);
    return l10n.daysAgo(diff.inDays);
  }
}

// ── Log entry ─────────────────────────────────────────────────────────────────

class _LogEntryTile extends StatelessWidget {
  const _LogEntryTile({
    required this.entry,
    required this.expanded,
    required this.onTap,
  });

  final LogEntry entry;
  final bool expanded;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final book = OrderBookPalette.of(context);
    final pal = SettingsPalette.of(context);
    final (chipBg, chipInk) = _levelColors(pal, entry.level);

    return Material(
      color: book.surface,
      borderRadius: const BorderRadius.all(Radius.circular(14)),
      child: InkWell(
        onTap: onTap,
        borderRadius: const BorderRadius.all(Radius.circular(14)),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: const BorderRadius.all(Radius.circular(14)),
            border: Border.all(color: pal.rowDivider),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  DecoratedBox(
                    decoration: BoxDecoration(
                      color: chipBg,
                      borderRadius: const BorderRadius.all(Radius.circular(6)),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      child: Text(
                        _levelLabel(entry.level),
                        style: TextStyle(
                          fontFamily: AppFonts.figures,
                          fontSize: 9,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.54,
                          color: chipInk,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      entry.tag,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                        color: book.textSecondary,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    formatLogTimestamp(platformInt64ToInt(entry.timestamp)),
                    style: TextStyle(
                      fontFamily: AppFonts.figures,
                      fontSize: 10,
                      fontWeight: FontWeight.w500,
                      color: pal.placeholder,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                entry.message,
                maxLines: expanded ? null : 3,
                overflow: expanded ? null : TextOverflow.ellipsis,
                style: TextStyle(
                  fontFamily: AppFonts.figures,
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                  height: 1.45,
                  color: pal.textMono,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// `WARNING` and `ERROR` shorten to the handoff's three-level chip; the
  /// shared export keeps the full name.
  static String _levelLabel(LogLevel level) => switch (level) {
    LogLevel.debug => 'DEBUG',
    LogLevel.info => 'INFO',
    LogLevel.warning => 'WARN',
    LogLevel.error => 'ERR',
  };

  static (Color, Color) _levelColors(SettingsPalette pal, LogLevel level) =>
      switch (level) {
        LogLevel.debug => (pal.logDebugBg, pal.logDebugInk),
        LogLevel.info => (pal.logInfoBg, pal.logInfoInk),
        LogLevel.warning => (pal.logWarnBg, pal.logWarnInk),
        LogLevel.error => (pal.logErrBg, pal.logErrInk),
      };
}

// ── Chrome ────────────────────────────────────────────────────────────────────

/// Returns the list to the newest entry after the user has scrolled back.
class _NewLogsChip extends StatelessWidget {
  const _NewLogsChip({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final pal = SettingsPalette.of(context);
    return Material(
      color: pal.chipActiveBg,
      borderRadius: const BorderRadius.all(Radius.circular(999)),
      child: InkWell(
        onTap: onTap,
        borderRadius: const BorderRadius.all(Radius.circular(999)),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: const BorderRadius.all(Radius.circular(999)),
            border: Border.all(color: pal.chipActiveBorder),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.arrow_downward, size: 12, color: pal.chipActiveInk),
              const SizedBox(width: 6),
              Text(
                AppLocalizations.of(context).newLogsChipLabel,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: pal.chipActiveInk,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// `Registro detallado` with its consequence in writing. It used to be an
/// unlabelled switch in the app bar, which nothing explained.
class _VerboseBar extends StatelessWidget {
  const _VerboseBar({required this.value, required this.onChanged});

  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final book = OrderBookPalette.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: book.surfaceNav,
        border: Border(top: BorderSide(color: book.navBorder)),
      ),
      child: Padding(
        // #267: bottom system-bar inset so the toggle clears the gesture /
        // 3-button navigation bar.
        padding: EdgeInsets.fromLTRB(
          redesignSidePadding,
          12,
          redesignSidePadding,
          18 + MediaQuery.of(context).viewPadding.bottom,
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    l10n.verboseLoggingTitle,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: book.textStrong,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    l10n.verboseLoggingSubtitle,
                    style: TextStyle(fontSize: 10, color: book.textTertiary),
                  ),
                ],
              ),
            ),
            MostroToggle(
              value: value,
              semanticLabel: l10n.verboseLoggingTitle,
              onChanged: onChanged,
            ),
          ],
        ),
      ),
    );
  }
}

# Logging System (v1 Reference)

> Centralized in-memory logging with privacy sanitization, background isolate support, and export capabilities.

## Overview

Mostro Mobile uses a singleton logger pattern with:
- In-memory buffer (`MemoryLogOutput`) for runtime capture
- Privacy sanitization (`cleanMessage()`) applied to all log entries
- Background isolate integration via `IsolateLogOutput`
- UI viewer (`LogsScreen`) with filtering, search, and export
- **User-controlled toggle** — logging is OFF by default, enabled only when user explicitly opts in

**Route:** `/logs` → `LogsScreen`

---

## Architecture

### Singleton Logger Pattern

All application logging goes through a single `logger` instance from `lib/services/logger_service.dart`.

**Benefits:**
- **Guaranteed capture** — single source of truth, no logs missed
- **Consistent privacy** — centralized `cleanMessage()` sanitization prevents sensitive data leaks
- **Memory safety** — centralized buffer with strict size limits prevents OOM
- **Simple API** — `logger.i()`, `logger.e()`, `logger.d()` — no per-service configuration

**Trade-off:** Application-wide adoption requires replacing direct `print()` calls with singleton logger calls.

### Multi-Output Architecture

```text
Main Isolate:
  logger (singleton) → MemoryLogOutput → UI (LogsScreen)
                     ↘ ConsoleOutput (debug builds only)

Background Isolate:
  logger → IsolateLogOutput → SendPort → Main Isolate ReceivePort → MemoryLogOutput
```

---

## Core Components

### 1. Logger Service (`lib/services/logger_service.dart`)

#### Singleton Instance
```dart
Logger get logger {
  _cachedLogger ??= Logger(
    printer: PrettyPrinter(...),  // or SimplePrinter based on Config.fullLogsInfo
    output: _MultiOutput(
      MemoryLogOutput.instance,
      Config.isDebug ? ConsoleOutput() : null,
    ),
    level: Config.isDebug ? Level.debug : Level.warning,
    filter: _ProductionOptimizedFilter(),
  );
  return _cachedLogger!;
}
```

**Usage:**
```dart
import 'package:mostro_mobile/services/logger_service.dart';

logger.i('Info message');
logger.e('Error occurred', error: e, stackTrace: stack);
logger.d('Debug value: $data');
logger.w('Warning condition detected');
```

**❌ Never do this:**
```dart
final myLogger = Logger();  // WRONG — use singleton
```

#### LogEntry Model
```dart
class LogEntry {
  final DateTime timestamp;
  final Level level;        // error, warning, info, debug, trace
  final String message;     // sanitized via cleanMessage()
  final String service;     // extracted from stack trace (e.g., "nostr_service")
  final String line;        // line number
  
  String format() {
    final time = timestamp.toString().substring(0, 19);
    final levelStr = level.toString().split('.').last.toUpperCase();
    return '[$levelStr]($service:$line) $time - $message';
  }
}
```

### 2. MemoryLogOutput (In-Memory Buffer)

**Implementation:**
- Extends `LogOutput` + `ChangeNotifier` (Riverpod integration).
- Maintains `_buffer: List<LogEntry>` with FIFO eviction.
- Global flag `MemoryLogOutput.isLoggingEnabled` gates capture.

**Buffer Management:**
```dart
static const int logMaxEntries = 1000;       // From Config
static const int logBatchDeleteSize = 100;

void _maintainBufferSize() {
  if (_buffer.length > Config.logMaxEntries) {
    final deleteCount = _buffer.length < Config.logBatchDeleteSize
        ? _buffer.length - Config.logMaxEntries
        : Config.logBatchDeleteSize;
    if (deleteCount > 0) {
      _buffer.removeRange(0, deleteCount);  // FIFO eviction
    }
  }
}
```

**Methods:**
- `output(OutputEvent event)` — called by logger, adds entry to buffer
- `addEntry(LogEntry entry)` — manual insertion (used by isolate logs)
- `getAllLogs()` — returns immutable list for UI
- `clear()` — empties buffer, notifies listeners
- `get logCount` — current buffer size

### 3. Privacy Sanitization (`cleanMessage()`)

Applied to **all** log messages before storage/display.

**Rules:**
1. Strip ANSI color codes / box-drawing characters
2. Remove emojis
3. **Redact private keys:** `nsec[0-9a-z]+` → `[PRIVATE_KEY]`
4. **Redact JSON fields:** `"privateKey":"..."` → `"privateKey":"[REDACTED]"`
5. **Redact mnemonics:** `"mnemonic":"..."` → `"mnemonic":"[REDACTED]"`
6. Replace non-printable chars with spaces
7. Collapse multiple spaces, trim

**Example:**
```dart
Input:  "User nsec1abc123xyz logged in with mnemonic 'word1 word2 ...'"
Output: "User [PRIVATE_KEY] logged in with [REDACTED]"
```

### 4. Background Isolate Support

#### Main Isolate Setup (`main.dart`)
```dart
void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  initIsolateLogReceiver(); // BEFORE starting background services
  // ...
}
```

**What it does:**
- Creates `ReceivePort` and registers it with `IsolateNameServer` under name `'mostro_logger_send_port'`.
- Listens for log messages from background isolates and forwards to `MemoryLogOutput`.

#### Background Isolate Logging
```dart
@pragma('vm:entry-point')
void backgroundServiceEntryPoint() async {
  final logSender = IsolateNameServer.lookupPortByName('mostro_logger_send_port');
  
  if (logSender == null) {
    // IsolateNameServer lookup failed — main isolate hasn't registered receiver
    backgroundLog('Background service started (fallback logging)');
    return;
  }
  
  final logger = Logger(
    printer: SimplePrinter(),
    output: IsolateLogOutput(logSender),
  );
  logger.i('Background service started');
}
```

**`IsolateLogOutput`:**
- Requires successful `IsolateNameServer.lookupPortByName()` lookup (returns `SendPort?`).
- Main isolate must have called `initIsolateLogReceiver()` before background service starts.
- Sends log data via `SendPort` as JSON: `{timestamp, level, message, service, line}`.
- Main isolate receives and reconstructs `LogEntry` via `addLogFromIsolate()`.

#### Fallback: `backgroundLog()`
For isolates where `IsolateNameServer.lookupPortByName()` returns `null` or is unavailable:
```dart
void backgroundLog(String message) {
  debugPrint('[BackgroundIsolate] ${cleanMessage(message)}');
}
```

---

## Configuration (`lib/core/config.dart`)

```dart
static const int logMaxEntries = 1000;       // Maximum logs in memory
static const int logBatchDeleteSize = 100;   // Batch delete when limit exceeded
static bool fullLogsInfo = true;             // true = PrettyPrinter, false = SimplePrinter
static bool isDebug = kDebugMode;            // Enables console output
```

---

## LogsScreen (`/logs`)

### Features

1. **Enable/Disable Toggle**
   - Master switch at top (Settings integrated via `settingsProvider`)
   - **Default: OFF** — resets on every app restart
   - Enable triggers performance warning dialog

2. **Stats Header**
   - Total logs / filtered count
   - Max entries indicator (`Config.logMaxEntries`)
   - Capture status (Capturing / Disabled)

3. **Search Bar**
   - Real-time text search across all messages
   - Clear button when active

4. **Filter Chips**
   - All Levels (default)
   - Error, Warning, Info, Debug
   - Single-select

5. **Log List**
   - Reverse chronological (newest at top)
   - Each item:
     - Level icon + badge color
     - Service:line identifier
     - Relative timestamp (e.g., "5m ago")
     - Full message text
   - Tap to select/copy (future enhancement)

6. **Scroll-to-Top Button**
   - Floating action button (mini, bottom-right)
   - Appears after scrolling >200px

7. **Actions Menu (⋮)**
   - Clear All (with confirmation dialog)
   - Export to File (via FilePicker)
   - Share (via system share sheet)

### Empty State
- Icon: `Icons.info_outline`
- Message: "No logs available" + "Logs will appear here"

### Log Item Styling

| Level | Color | Icon |
|-------|-------|------|
| Error | `AppTheme.statusError` | `Icons.error` |
| Warning | `AppTheme.statusWarning` | `Icons.warning` |
| Info | `AppTheme.statusInfo` | `Icons.info` |
| Debug | `AppTheme.textSecondary` | `Icons.bug_report` |

---

## Export Service (`lib/services/logger_export_service.dart`)

**Filename Format:** `mostro_logs_YYYY-MM-DD_HH-MM-SS.txt`

**Export Methods:**
1. **`exportLogsToFolder()`** — via FilePicker (save dialog)
2. **`exportLogsForSharing()`** — writes to temp file, returns `File` for share sheet

**Export Format:**
```text
Mostro Logs Report
Generated: 2026-03-25 01:00:00
Total: 150
============================================================

[ERROR](nostr_service:123) 2026-03-25 00:58:30 - Connection failed
[INFO](mostro_service:456) 2026-03-25 00:58:25 - Order created
...
```

---

## Logging Recording Indicator

**Widget:** `LogsRecordingIndicator` (`lib/features/logs/widgets/logs_recording_indicator.dart`)

- **Location:** Floating bottom-left corner (above system UI padding).
- **Visibility:** Only when `MemoryLogOutput.isLoggingEnabled == true`.
- **Appearance:** Red dot with pulse animation + "REC" text.
- **Interaction:** Tap navigates to `/logs`.

---

## State Management

### Provider (`lib/features/logs/logs_provider.dart`)

```dart
final logsProvider = ChangeNotifierProvider<MemoryLogOutput>((ref) {
  return MemoryLogOutput.instance;
});

final filteredLogsProvider = Provider.family<List<LogEntry>, LogsFilter>((ref, filter) {
  final logs = ref.watch(logsProvider).getAllLogs();
  return logs.where((log) {
    // Pseudocode: filter by levelFilter (if set) and searchQuery (if non-empty)
    // Real implementation checks log.level.name == filter.levelFilter
    // and log.message.contains(filter.searchQuery)
  }).toList();
});
```

**LogsFilter:**
```dart
class LogsFilter {
  final String? levelFilter;   // 'error', 'warning', 'info', 'debug', null = all
  final String searchQuery;
}
```

---

## Performance Considerations

### Why Logging is OFF by Default

1. **Memory overhead** — buffer stores up to 1000 entries (assuming ~100-500 bytes per entry: 1000 × 100-500 bytes ≈ 100-500 KB).
2. **CPU cost** — `cleanMessage()` regex + stack trace parsing on every log.
3. **Privacy risk** — user may share logs without realizing sensitive data could be present (sanitization reduces but doesn't eliminate risk).

### Performance Warning Dialog

When user enables logging:
```text
⚠️ Performance Warning

Enabling logs may impact app performance. 
Logs are stored in memory and will increase battery usage.
Only enable for debugging purposes.

[Cancel] [Enable]
```

---

## Integration Points

| Feature | Integration |
|---------|-------------|
| Settings | Toggle in Dev Tools card (`SETTINGS_SCREEN.md`), writes to `settingsProvider` |
| Notifications | Log notification registration/delivery events |
| Trades | Log order state transitions, Mostro message handling |
| Nostr | Log relay connections, subscriptions, gift wrap encryption |
| Background Services | Isolate log forwarding via SendPort |

---

## Cross-References

- [SETTINGS_SCREEN.md](./SETTINGS_SCREEN.md) — Dev Tools card with logging toggle.
- [NOTIFICATIONS_SYSTEM.md](./NOTIFICATIONS_SYSTEM.md) — Notification events logged for debugging.
- [NOSTR.md](./NOSTR.md) — Nostr service logging for relay connections and subscriptions.
- [NAVIGATION_ROUTES.md](./NAVIGATION_ROUTES.md) — Route `/logs`.
- [FCM_IMPLEMENTATION.md](./FCM_IMPLEMENTATION.md) — Background message handling logs.

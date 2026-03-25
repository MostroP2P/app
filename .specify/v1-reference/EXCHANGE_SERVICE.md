# ExchangeService (v1 Reference)

> Abstract service for fetching Bitcoin/fiat exchange rates from external APIs.

## Overview

`ExchangeService` (`lib/services/exchange_service.dart`) is an abstract base class defining the contract for exchange rate providers. It provides:
- HTTP client utilities (timeout, error handling)
- Abstract method `getExchangeRate(from, to)`
- Currency code discovery (`getCurrencyCodes()`)
- Riverpod integration via `ExchangeRateNotifier`

**Current Implementation:** `YadioExchangeService` (Yadio API)

---

## Architecture

### Abstract Base Class

```dart
abstract class ExchangeService {
  final String baseUrl;
  final Duration timeout;
  final Map<String, String> defaultHeaders;

  ExchangeService(
    this.baseUrl, {
    this.timeout = const Duration(seconds: 30),
    this.defaultHeaders = const {'Accept': 'application/json'},
  });

  Future<double> getExchangeRate(String fromCurrency, String toCurrency);
  Future<Map<String, String>> getCurrencyCodes();
  Future<Map<String, dynamic>> getRequest(String endpoint);
}
```

**Design:**
- Forces implementations to provide `baseUrl` (validated in constructor)
- Common HTTP utilities shared across providers
- Timeout protection (default 30s)
- Standard error handling

### Validation

```dart
if (baseUrl.isEmpty) {
  throw ArgumentError('baseUrl cannot be empty');
}
if (!baseUrl.startsWith('http')) {
  throw ArgumentError('baseUrl must start with http:// or https://');
}
```

---

## HTTP Utilities

### `getRequest(endpoint)`

```dart
Future<Map<String, dynamic>> getRequest(String endpoint) async {
  final url = Uri.parse('$baseUrl$endpoint');
  try {
    final response = await http.get(url, headers: defaultHeaders).timeout(timeout);

    if (response.statusCode == 200) {
      return json.decode(response.body) as Map<String, dynamic>;
    }

    throw HttpException('Failed to load data: ${response.statusCode}', uri: url);
  } on TimeoutException {
    throw HttpException('Request timed out', uri: url);
  } on FormatException catch (e) {
    throw HttpException('Invalid response format: ${e.message}', uri: url);
  } catch (e) {
    throw HttpException('Request failed: $e', uri: url);
  }
}
```

**Error Handling:**
- `TimeoutException` → `HttpException` with "Request timed out"
- `FormatException` → `HttpException` with "Invalid response format"
- Non-200 status → `HttpException` with status code
- Generic errors → `HttpException` with error details

---

## Riverpod Integration

### ExchangeRateNotifier

```dart
class ExchangeRateNotifier extends StateNotifier<AsyncValue<double>> {
  final ExchangeService exchangeService;

  ExchangeRateNotifier(this.exchangeService)
      : super(const AsyncValue.loading());

  Future<void> fetchExchangeRate(String currency) async {
    try {
      state = const AsyncValue.loading();
      final rate = await exchangeService.getExchangeRate(currency, 'BTC');
      state = AsyncValue.data(rate);
    } catch (error) {
      state = AsyncValue.error(error, StackTrace.current);
    }
  }
}
```

**State Management:**
- `AsyncValue<double>` represents loading/success/error states
- Always fetches rate to BTC (hardcoded `toCurrency`)
- UI observes state changes via Riverpod providers

---

## YadioExchangeService Implementation

**File:** `lib/services/yadio_exchange_service.dart`

```dart
class YadioExchangeService extends ExchangeService {
  YadioExchangeService() : super('https://api.yadio.io');

  @override
  Future<double> getExchangeRate(String fromCurrency, String toCurrency) async {
    final data = await getRequest('/exrates/$fromCurrency');
    final rate = data[toCurrency];
    if (rate == null) {
      throw Exception('Currency $toCurrency not found for $fromCurrency');
    }
    return (rate as num).toDouble();
  }

  @override
  Future<Map<String, String>> getCurrencyCodes() async {
    final data = await getRequest('/currencies');
    return Map<String, String>.from(data);
  }
}
```

**API Endpoints:**
- `/exrates/{currency}` — Returns rates for all currencies
- `/currencies` — Returns map of currency codes to names

**Example Response (`/exrates/USD`):**
```json
{
  "BTC": 0.000024,
  "EUR": 0.92,
  "GBP": 0.79,
  ...
}
```

---

## Usage in App

### Provider Setup

```dart
final exchangeServiceProvider = Provider<ExchangeService>((ref) {
  return YadioExchangeService();
});

final exchangeRateProvider = StateNotifierProvider.family<
    ExchangeRateNotifier,
    AsyncValue<double>,
    String>((ref, currency) {
  final service = ref.watch(exchangeServiceProvider);
  return ExchangeRateNotifier(service)..fetchExchangeRate(currency);
});
```

### UI Consumption

```dart
final rate = ref.watch(exchangeRateProvider('USD'));

rate.when(
  data: (value) => Text('1 BTC = ${value.toStringAsFixed(2)} USD'),
  loading: () => CircularProgressIndicator(),
  error: (err, stack) => Text('Error: $err'),
);
```

---

## Currency Code Discovery

**Method:** `getCurrencyCodes()`

**Purpose:** Fetch all supported currencies for UI pickers.

**Example Response (Yadio):**
```json
{
  "USD": "United States Dollar",
  "EUR": "Euro",
  "GBP": "British Pound",
  "VES": "Venezuelan Bolívar",
  ...
}
```

**UI Usage:**
- `CurrencySelectionDialog` fetches codes on first load
- Caches results for session lifetime
- Displays currency name + emoji flag in picker

---

## Error Scenarios

| Error | Cause | Resolution |
|-------|-------|------------|
| `HttpException: Request timed out` | Network slow or API down | Retry with exponential backoff |
| `HttpException: Failed to load data: 404` | Invalid currency code | Validate input against `getCurrencyCodes()` |
| `Exception: Currency BTC not found for XYZ` | API doesn't support XYZ/BTC pair | Show error message, suggest different currency |
| `FormatException: Invalid response format` | API changed schema | Update parsing logic, consider fallback provider |

---

## Extension Point: Multiple Providers

**Future Enhancement:** Support fallback providers (e.g., CoinGecko, Binance).

**Design Pattern:**
```dart
class FallbackExchangeService extends ExchangeService {
  final List<ExchangeService> providers;

  @override
  Future<double> getExchangeRate(String from, String to) async {
    for (final provider in providers) {
      try {
        return await provider.getExchangeRate(from, to);
      } catch (e) {
        logger.w('Provider ${provider.baseUrl} failed: $e');
        continue;
      }
    }
    throw Exception('All exchange providers failed');
  }
}
```

---

## Performance Considerations

### Caching

**Current:** No caching implemented in v1.

**Recommendation for v2:**
- Cache rates for 5-10 minutes
- Invalidate on user refresh action
- Store in memory (not persistent across app restarts)

### Rate Limiting

**Current:** No client-side rate limiting.

**Yadio API Limits:** Unknown (appears generous based on usage).

**Best Practice:**
- Only fetch when user views order creation screen
- Don't poll for rate updates in background
- Show stale rate with timestamp if fetch fails

---

## Cross-References

- [ORDER_CREATION.md](./ORDER_CREATION.md) — Uses exchange rates for sats amount validation
- [SETTINGS_SCREEN.md](./SETTINGS_SCREEN.md) — Currency selector uses `getCurrencyCodes()`
- [HOME_SCREEN.md](./HOME_SCREEN.md) — Order book displays fiat amounts based on rates

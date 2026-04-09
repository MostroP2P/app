import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mostro/l10n/app_localizations.dart';

import 'package:mostro/core/app_routes.dart';
import 'package:mostro/core/app_theme.dart';
import 'package:mostro/features/notifications/services/push_notification_service.dart';
import 'package:mostro/features/settings/providers/settings_provider.dart';
import 'package:mostro/features/trades/providers/trades_providers.dart';
import 'package:mostro/src/rust/api/orders.dart' as orders_api;

/// Root application widget.
///
/// Wraps the widget tree with [ProviderScope] and wires GoRouter +
/// localisation. RustLib initialisation is deferred to Phase 3 (US1)
/// when the identity API is ready.
class MostroApp extends ConsumerStatefulWidget {
  const MostroApp({super.key});

  @override
  ConsumerState<MostroApp> createState() => _MostroAppState();
}

/// Global key for showing snackbars from anywhere (e.g. Rust order events).
final rootScaffoldMessengerKey = GlobalKey<ScaffoldMessengerState>();

class _MostroAppState extends ConsumerState<MostroApp> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final container = ProviderScope.containerOf(context, listen: false);
      try {
        await PushNotificationService.instance.initialize(container: container);
      } catch (e) {
        debugPrint('[app] push notification init failed: $e');
      }
    });
    _listenOrderEvents();
  }

  /// Listen for daemon order rejection events and show a snackbar + refresh trades.
  ///
  /// Guarded by [_orderEventListenerActive] so hot reload/restart doesn't
  /// create duplicate listeners on the same broadcast channel.
  static bool _orderEventListenerActive = false;

  void _listenOrderEvents() {
    if (_orderEventListenerActive) return;
    _orderEventListenerActive = true;
    Future.microtask(() async {
      try {
        final stream = await orders_api.onOrderEvent();
        while (mounted) {
          final event = await stream.next();
          if (event == null || !mounted) break;
          debugPrint('[order-event] ${event.reason}: ${event.message}');
          rootScaffoldMessengerKey.currentState?.showSnackBar(
            SnackBar(
              content: Text(event.message),
              duration: const Duration(seconds: 4),
            ),
          );
          // Refresh the trades list so the removed/canceled order disappears.
          ref.invalidate(rawTradesProvider);
        }
      } catch (e) {
        debugPrint('[order-event] listener error: $e');
      } finally {
        _orderEventListenerActive = false;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    // Expose the Riverpod container to the router's redirect callback so it
    // can read firstRunProvider without a BuildContext.
    routerContainer = ProviderScope.containerOf(context, listen: false);

    // Watch locale from settings provider so language changes propagate.
    final locale = ref.watch(localeProvider);

    // Theme mode from settings; dark is the default.
    final themeMode = ref.watch(settingsProvider.select((s) => s.themeMode));

    return MaterialApp.router(
      scaffoldMessengerKey: rootScaffoldMessengerKey,
      title: 'Mostro',
      debugShowCheckedModeBanner: false,
      theme: buildLightTheme(),
      darkTheme: buildDarkTheme(),
      themeMode: themeMode,
      locale: locale,
      routerConfig: appRouter,
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      builder: (context, child) =>
          NotificationListenerWidget(child: child ?? const SizedBox.shrink()),
    );
  }
}

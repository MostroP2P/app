# Documentación de Referencia V1

> 🔴 **CRÍTICO: ¡Lee el Protocolo Primero!**
> 
> Antes de sumergirte en estos documentos, entiende el **Protocolo Mostro**:
> - **Repositorio del Protocolo**: https://github.com/MostroP2P/protocol
> - **Referencia Local**: [../PROTOCOL.md](../PROTOCOL.md)
> 
> El protocolo define TODA la comunicación entre clientes y mostrod. Es la fuente de verdad.

---

> ⚠️ **IMPORTANTE: Estos documentos son de Mostro Mobile v1 (implementación Dart/Flutter)**
>
> Úsalos **SOLO COMO REFERENCIA** para entender la lógica de negocio, protocolos y flujos.
> La implementación v2 usa **Rust core + flutter_rust_bridge**, así que los ejemplos de código
> en estos docs están en Dart y deben **adaptarse a Rust** para la capa de lógica core.

## Qué extraer de estos documentos

| De los Docs V1 | Usar en V2 |
|----------------|------------|
| Lógica de negocio y flujos | Implementar en Rust (`rust/src/api/`) |
| Detalles del protocolo (Nostr, NIP-59) | Implementar en Rust usando `nostr-sdk` |
| Máquinas de estado (status de orden) | Implementar en Rust, exponer a Flutter |
| Crypto (llaves, cifrado) | Implementar en Rust, **NO en Dart** |
| Patrones UI/UX | Mantener en Flutter |
| Específicos de plataforma (FCM, notificaciones) | Mantener en Flutter |

## Índice de Documentos

### Pantallas y Navegación

| Documento | Descripción | Relevancia V2 |
|-----------|-------------|---------------|
| [HOME_SCREEN.md](./HOME_SCREEN.md) | Pantalla principal, order book, filtros, FAB | Mantener en Flutter (UI) |
| [NAVIGATION_ROUTES.md](./NAVIGATION_ROUTES.md) | Rutas GoRouter, deep links, redirects | Adaptar navegación para Rust core |
| [ORDER_BOOK.md](./ORDER_BOOK.md) | Order book público vs Mis Trades, filtros | Mantener en Flutter |
| [ORDER_CREATION.md](./ORDER_CREATION.md) | AddOrderScreen, formulario y flujo de creación de orden | Mantener en Flutter (UI + flujo cliente) |
| [TAKE_ORDER.md](./TAKE_ORDER.md) | TakeOrderScreen, rutas `/take_sell` y `/take_buy`, acciones `take-sell`/`take-buy` | Mantener en Flutter (UI + flujo cliente) |
| [TRADE_EXECUTION.md](./TRADE_EXECUTION.md) | PayLightningInvoice, AddLightningInvoice, TradeDetail, acciones `pay-invoice`/`fiat-sent`/`release`, FSM de ejecución | UI en Flutter, máquina de estados en Rust |
| [MY_TRADES.md](./MY_TRADES.md) | `/order_book` (TradesScreen), filtro de status, providers de datos, items de lista, pull-to-refresh, navegación | Mantener en Flutter (UI + flujo cliente) |
| [DRAWER_MENU.md](./DRAWER_MENU.md) | Drawer lateral, barra de navegación inferior | Mantener en Flutter |

### Arquitectura Core

| Documento | Descripción | Relevancia V2 |
|-----------|-------------|---------------|
| [ARCHITECTURE.md](./ARCHITECTURE.md) | Arquitectura general de la app, capas | Adaptar capas para Rust core |
| [SESSION_AND_KEY_MANAGEMENT.md](./SESSION_AND_KEY_MANAGEMENT.md) | BIP-32/39, llaves de trade, mnemonic, restauración | **CRÍTICO** - Mover a Rust |
| [NOSTR.md](./NOSTR.md) | Protocolo Nostr, NIP-59 Gift Wrap, eventos | **CRÍTICO** - Usar nostr-sdk en Rust |

### Funcionalidades

| Documento | Descripción | Relevancia V2 |
|-----------|-------------|---------------|
| [ORDER_STATUS_HANDLING.md](./ORDER_STATUS_HANDLING.md) | Máquina de estados de orden, transiciones | Mover máquina de estados a Rust |
| [P2P_CHAT_SYSTEM.md](./P2P_CHAT_SYSTEM.md) | Chat cifrado, sharedKey, flujos `/chat_list` y `/chat_room` | **CRÍTICO** - Mover a Rust |
| [DISPUTE_SYSTEM.md](./DISPUTE_SYSTEM.md) | Lista de disputas, chat con admin, pipeline de creación/resolución | **CRÍTICO** - Mover lógica de disputas a Rust |
| [RATING_SYSTEM.md](./RATING_SYSTEM.md) | UX de calificación post-trade, payload `RatingUser`, visualización de reputación | Crypto en Rust; UI en Flutter |
| [NWC_ARCHITECTURE.md](./NWC_ARCHITECTURE.md) | Integración Nostr Wallet Connect | Mover a Rust |
| [ENCRYPTED_IMAGE_MESSAGING_IMPLEMENTATION.md](./ENCRYPTED_IMAGE_MESSAGING_IMPLEMENTATION.md) | ChaCha20-Poly1305, Blossom | Crypto en Rust, upload en Flutter |
| [AUTHENTICATION.md](./AUTHENTICATION.md) | Flujo de auth, desbloqueo biométrico | Adaptar para manejo de llaves en Rust |
| [ACCOUNT_SCREEN.md](./ACCOUNT_SCREEN.md) | Pantalla de cuenta, backup de mnemonic | Referencia desde navegación |
| [SETTINGS_SCREEN.md](./SETTINGS_SCREEN.md) | Pantalla de configuración, preferencias | Mantener en Flutter |
| [ORDER_STATES.md](./ORDER_STATES.md) | Enum de status de orden y valores | Mover a Rust |

### Plataforma e Infraestructura

| Documento | Descripción | Relevancia V2 |
|-----------|-------------|---------------|
| [FCM_IMPLEMENTATION.md](./FCM_IMPLEMENTATION.md) | Push notifications, servicio en segundo plano | Mantener en Flutter (específico de plataforma) |
| [RELAY_SYNC_IMPLEMENTATION.md](./RELAY_SYNC_IMPLEMENTATION.md) | Gestión de relays, kind 10002 | Mover lógica de relays a Rust |
| [LOGGING_SYSTEM.md](./LOGGING_SYSTEM.md) | Logging, exportación, privacidad | Adaptar para logging Rust + Flutter |

## Diferencias Clave: V1 vs V2

### V1 (Actual)
```
┌─────────────────────────────────────┐
│           Flutter/Dart              │
│  ┌─────────────────────────────┐    │
│  │   UI + Lógica de Negocio +  │    │
│  │   Crypto + Nostr (dart_nostr)│   │
│  └─────────────────────────────┘    │
└─────────────────────────────────────┘
```

### V2 (Objetivo)
```
┌─────────────────────────────────────┐
│           Flutter/Dart              │
│        (Solo UI + Plataforma)       │
├─────────────────────────────────────┤
│       flutter_rust_bridge           │
├─────────────────────────────────────┤
│              Rust Core              │
│  ┌─────────┐ ┌─────────┐ ┌───────┐  │
│  │ Orders  │ │  Chat   │ │ Keys  │  │
│  │ Nostr   │ │  NWC    │ │Crypto │  │
│  └─────────┘ └─────────┘ └───────┘  │
│            nostr-sdk                │
└─────────────────────────────────────┘
```

## Cómo Usar Estos Documentos

1. **Lee el documento** para entender la funcionalidad/flujo
2. **Extrae la lógica de negocio** (ignora detalles de implementación Dart)
3. **Diseña la API Rust** que expone la funcionalidad necesaria a Flutter
4. **Implementa en Rust** usando los crates apropiados (nostr-sdk, etc.)
5. **Expón vía flutter_rust_bridge** con tipos apropiados

## Prioridad de Migración

Basado en complejidad y dependencias:

1. **Fase 1**: Identidad y Llaves (SESSION_AND_KEY_MANAGEMENT.md)
2. **Fase 2**: Nostr Core (NOSTR.md, RELAY_SYNC_IMPLEMENTATION.md)
3. **Fase 3**: Órdenes (ORDER_STATUS_HANDLING.md)
4. **Fase 4**: Chat (P2P_CHAT_SYSTEM.md, ENCRYPTED_IMAGE_MESSAGING_IMPLEMENTATION.md)
5. **Fase 5**: NWC (NWC_ARCHITECTURE.md)
6. **Fase 6**: Notificaciones (FCM_IMPLEMENTATION.md) - se queda en Flutter

---

**Fuente**: https://github.com/MostroP2P/mobile/tree/main/docs/architecture
**Copiado**: Marzo 2026

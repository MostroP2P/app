# Reporte de estado — MostroP2P/app (v2)

**Fecha:** 2026-07-07
**Rama auditada:** `claude/project-audit-report-em9bjq`
**Método:** cada issue verificado contra el código fuente (Rust `rust/` + Flutter `lib/`), con evidencia `archivo:línea`. No se confió en el texto de los issues; se confirmó todo contra el código actual.

---

## Resumen ejecutivo

- **48 issues** en total: 3 cerrados (arreglados) + 45 abiertos.
- De los 45 abiertos: **~31 NO implementados**, **7 parciales**, **2 son tareas manuales de QA/a11y** (no features), y **1 (#163) parece ya resuelto** en el código pese a seguir abierto.
- **Núcleo funcional (trading) implementado y sólido.** Lo que falta es casi todo **infraestructura (CI/CD/tests inexistentes), wiring de features a medio conectar, y parity con la app v1**.

**Leyenda:** ✅ implementado · ⚠️ parcial · ❌ no implementado · 🔧 tarea manual (no es feature)

---

## ✅ Lo que SÍ está implementado

El núcleo del protocolo y del flujo de trading funciona. Confirmado por los 3 issues cerrados y la estructura del código:

- **Transporte v2** (NIP-44 / Kind 14 firmado al daemon; NIP-59 Gift Wrap para chat peer) — issue **#101 cerrado**.
- **Flujo de orden completo**: crear / tomar / fiat-sent / release, con hold invoices.
- **Order book en tiempo real** (Kind 38383) con filtros de moneda/método/rating/premium.
- **Órdenes con rango de precio** — el código ya renderiza `min – max` (ver nota sobre #163 abajo).
- **Cambio de nodo Mostro (single-node)** — bug **#158 cerrado**: persiste, rehidrata al arranque y refresca suscripciones (`set_active_mostro_node`).
- **Órdenes fantasma tras timeout** — bug **#157 cerrado**: el order book ya no se contamina con órdenes locales.
- **Identidad mnemónica** (BIP-39/32, NIP-06), almacenamiento seguro, **NWC**, gestión manual de relays, **PoW (NIP-13)**, pantalla About, chat peer-to-peer, rating de contraparte.
- **Blossom (adjuntos cifrados) en nativo**: upload/download con auth Kind-24242 firmada — funciona en native (`reqwest`).

---

## ❌ Lo que NO está implementado (por milestone)

### M2 — Infraestructura / CI (todo ausente)

| # | Tema | Estado | Evidencia |
|---|------|--------|-----------|
| #151 | CI (cargo build/test/clippy + flutter analyze/test) | ❌ | **No existe `.github/` en absoluto** |
| #152 | Base de tests Flutter | ❌ | Solo el `widget_test.dart` por defecto |
| #153 | Tests E2E de Rust | ❌ | No hay `rust/tests/`; solo unit tests inline |
| #154 | Build WASM + smoke test en CI | ❌ | No hay CI |
| #155 | Templates de issue/PR + CONTRIBUTING.md | ❌ | Ninguno existe |
| #156 | Manifiesto Zapstore | ❌ | No hay `zapstore.yaml` |
| #118 | Pipeline de release (APK/iOS/web/desktop) | ❌ | No hay workflows |
| #119 | Mutation testing | ❌ | Sin config |

> **El repo tiene cero infraestructura CI/CD.** El README afirma "todos los checks de CI deben pasar", pero ese gate no existe.

### M3 — Gaps de protocolo

| # | Tema | Estado | Evidencia |
|---|------|--------|-----------|
| #144 | Gestor central de suscripciones + tracking de `request_id` | ❌ | Suscripciones ad-hoc; `orders.rs:1141` pasa `request_id = None` |
| #145 | Anti-abuse bond (epic) | ❌ | Cero soporte; `orders.rs:1575` lo marca "out of scope" |
| #146 | Descubrimiento de relays desde evento del nodo | ❌ | `config.rs:9` aún hardcodea `DEFAULT_RELAYS` |
| #147 | Servicio en background para mantener subs vivas + wake por push | ❌ | Solo scaffolding FCM; el handler solo hace `debugPrint` |
| #148 | Detección de timeout + limpieza de sesiones | ⚠️ | `cleanup_stale_sessions()` (`session.rs:151`) existe pero **sin callers** (código muerto) |
| #149 | Monitor de salud de relays (latencia/reconexión) | ⚠️ | Hay estado/last_error, pero **sin RTT ni contador de reconexiones**; `last_error` nunca se puebla |
| #150 | Cliente Blossom para WASM/web | ⚠️ | Native completo; ramas WASM devuelven `Err("NotImplemented")` (`blossom.rs:117,214`) |

### M4 — Features a medio conectar (Rust listo, Dart sin cablear)

| # | Tema | Estado | Evidencia |
|---|------|--------|-----------|
| #138 | Routing entrante de chat admin (disputa) Kind 1059 | ❌ | Deriva `adminSharedKey` (`disputes.rs:250`) pero nadie se suscribe con ella |
| #139 | Paneles Trade/User Info con datos reales | ❌ | Guiones placeholder (`info_panels.dart:63-197`); shared key ECDH sin cablear |
| #140 | UI de adjuntos cifrados (picker→send_file→decrypt) | ❌ | Stubs; el "progreso" es un `Future.delayed` falso |
| #141 | Migrar `backup_confirmed` de SharedPreferences a Rust | ❌ | Sigue en SharedPreferences Dart (`backup_reminder_provider.dart`) |
| #142 | Restaurar sesiones/trades desde mnemónico | ❌ | No existe `lib/features/restore/` |
| #143 | Sistema de disputas end-to-end (lista + chat admin) | ⚠️ | Lista siempre vacía; enviar/adjuntar son stubs "coming soon" |

### M5 — Multi-nodo y descubrimiento

| # | Tema | Estado | Evidencia |
|---|------|--------|-----------|
| #135 | Gestión multi-nodo (lista comunidad, avatar, trusted badge) | ⚠️ | Solo pegar pubkey (`mostro_node_selector.dart`); sin lista de nodos ni avatares |
| #136 | Descubrimiento + selector de comunidad | ❌ | No existe `lib/features/community/` |
| #137 | Handler de deep link `mostro:` | ❌ | Solo routing de tap de push, no el esquema URI; `app_links` no está en deps |

### M6 — UX / parity con v1

| # | Tema | Estado | Evidencia |
|---|------|--------|-----------|
| #162 | i18n incompleto/inconsistente | ⚠️ | EN=316 keys vs ES/FR/DE/IT=296; muchos strings en inglés hardcodeados |
| #163 | Rango de precio mostrado como monto único | ✅ | **Parece ya resuelto** — el código renderiza `min – max` (ver nota) |
| #124 | Banner global de offline | ❌ | `_watchConnectionState` (`main.dart:182`) solo `debugPrint` en debug |
| #125 | UX contextual de cancelación cooperativa | ❌ | Solo estado terminal, sin botones Accept/Decline |
| #126 | Snackbar in-app de mensajes entrantes fuera del chat | ❌ | Solo badge de no-leídos |
| #127 | Filtro "Days of use" (antigüedad del maker) | ❌ | No existe en `order_filter.dart` |
| #128 | Validación LN address + resolución LNURL | ⚠️ | Solo check `name@domain`; sin resolución LNURL-pay |
| #129 | Filtros de logs por nivel y tag | ❌ | Lista plana sin filtros (`log_report_screen.dart`) |
| #130 | Imágenes cifradas: compresión/thumbnail/preview | ❌ | Stub |
| #131 | Retención de historial configurable | ❌ | No existe |
| #132 | Persistir métodos de pago custom como sugerencias | ❌ | Solo por-orden, en memoria |
| #133 | VAPID key real para Web Push | ❌ | Sigue el placeholder literal `'YOUR_VAPID_KEY'` (`push_notification_service.dart:64`) |
| #134 | Botones CONTACT/CANCEL/OPEN-DISPUTE visibles en Trade Detail | ❌ | Escondidos en menú ⋮ (`trade_detail_screen.dart:548`) |

### M7 — Refactors / docs

| # | Tema | Estado | Evidencia |
|---|------|--------|-----------|
| #120 | Dividir `orders.rs` | ❌ | Creció a **2393 LOC**, sigue monolítico |
| #121 | Dividir `trade_detail_screen.dart` | ❌ | Sigue en 1155 LOC |
| #122 | Sincronizar `tasks.md` de specs 004/005 | ❌ | Los 12 tasks de 005 siguen `[ ]` pese a estar mergeado |
| #123 | README: listar NIPs y BUDs soportados | ⚠️ | Los menciona en prosa; falta la lista explícita (NIP-47/17/40, BUDs) |

### M8 — Producto / seguridad / a11y · M9

| # | Tema | Estado | Evidencia |
|---|------|--------|-----------|
| #114 | Migrar estado per-trade de polling a push stream | ❌ | Sigue haciendo polling cada 1–2s; `on_trade_updated` no existe (el `onTradeUpdated` Dart está muerto) |
| #115 | Auth biométrica opcional | ❌ | `local_auth` ni está en `pubspec.yaml` |
| #116 | QA visual tema claro | 🔧 | Tarea manual — el tema claro sí está cableado |
| #117 | Auditoría de accesibilidad | 🔧 | Tarea incremental — `Semantics(` en 10 widgets |

---

## Nota importante sobre #163 (rango de precio)

El issue y el README dicen que un rango `20-60 USD` se muestra como `20 USD`, pero **en el código actual `OrderItem.displayAmount` ya renderiza `min – max`** (`home_order_providers.dart:104-109`), el modelo lleva `fiatAmountMin/Max`, y Rust parsea el rango del tag `fa` (`order_events.rs:64,121`). Tanto la tarjeta (`order_list_item.dart:129`) como el detalle (`trade_detail_screen.dart:644`) usan `displayAmount`. **Parece ya arreglado** — se recomienda una verificación visual rápida en la app antes de cerrarlo, porque puede haber un caso concreto (p. ej. detalle vs. tarjeta) que aún falle.

---

## Issues cerrados (ya resueltos)

| # | Tema | Estado |
|---|------|--------|
| #101 | Migrar transporte gift-wrap a mostro-core (wrap/unwrap/validate_response) | ✅ Cerrado |
| #157 | Órdenes fantasma tras timeout / CantDo tardío del daemon | ✅ Cerrado |
| #158 | Cambio de nodo Mostro no persistía / no rehidrataba / no refrescaba subs | ✅ Cerrado |

---

## Prioridades sugeridas

1. **Desbloqueante de credibilidad:** M2 (#151, #152, #153) — no hay CI ni tests; es el mayor riesgo estructural.
2. **Features "casi listas" (alto ROI):** M4 (#138–#143) — el Rust ya existe, solo falta cablear Dart. Disputas (#143/#138) y adjuntos (#140) son los más visibles.
3. **Parity crítica de UX:** #142 (restaurar desde mnemónico, bloquea la migración v1→v2), #134 (botones de acción visibles), #162 (i18n).
4. **Verificar y cerrar #163** si la revisión visual confirma que ya funciona.

# Especificación del Sistema de Disputas (Mostro Mobile v1)

> Referencia para la sección 8 (DISPUTES) que cubre la lista de disputas en la app, chat con admin, y pipeline de creación de disputas.

## Alcance

- Ruta `/dispute_details/:disputeId`
- Pantallas y widgets: `ChatRoomsScreen` (pestaña de disputas), `DisputesList`, `DisputeListItem`, `DisputeChatScreen`, `DisputeMessagesList`, `DisputeInfoCard`, `DisputeMessageInput`
- Providers y servicios: `chatTabProvider`, `userDisputeDataProvider`, `disputeDetailsProvider`, `disputeChatNotifierProvider`, `disputeReadStatusProvider`, `DisputeRepository`, `DisputeReadStatusService`
- Modelos de datos: `Dispute`, `DisputeData`, `Session.adminSharedKey`
- Almacenamiento y transporte: Sembast event store (`type: dispute_chat`), NIP-59 gift wrap, ECDH de admin shared-key

## Archivos fuente revisados

- `lib/features/chat/screens/chat_rooms_list.dart`
- `lib/features/chat/widgets/chat_tabs.dart`
- `lib/features/disputes/widgets/disputes_list.dart`
- `lib/features/disputes/widgets/dispute_list_item.dart`
- `lib/features/disputes/widgets/dispute_content.dart`
- `lib/features/disputes/widgets/dispute_info_card.dart`
- `lib/features/disputes/widgets/dispute_messages_list.dart`
- `lib/features/disputes/widgets/dispute_message_input.dart`
- `lib/features/disputes/widgets/dispute_message_bubble.dart`
- `lib/features/disputes/screens/dispute_chat_screen.dart`
- `lib/features/disputes/notifiers/dispute_chat_notifier.dart`
- `lib/features/disputes/providers/dispute_providers.dart`
- `lib/features/disputes/providers/dispute_read_status_provider.dart`
- `lib/services/dispute_read_status_service.dart`
- `lib/data/repositories/dispute_repository.dart`
- `lib/data/models/dispute.dart`
- `lib/features/order/models/order_state.dart`
- `lib/data/models/session.dart`
- `lib/features/trades/screens/trade_detail_screen.dart`

---

## 1) Puntos de entrada y navegación

### Integración de pestaña de chat (`/chat_list`)
- `ChatRoomsScreen` renderiza un layout de dos pestañas vía `ChatTabs`. Las pestañas mapean a `ChatTabType.messages` (chat P2P) y `ChatTabType.disputes`.
- Cambiar de pestaña actualiza `chatTabProvider`; los swipes horizontales también alternan las pestañas.
- La pestaña de disputas intercambia la lista principal por `DisputesList`, así los usuarios pueden acceder a disputas sin salir del módulo de chat.
- Se muestra una descripción contextual corta bajo las pestañas ("Aquí están tus disputas" vs "Aquí están tus chats").

### Trade Detail → Botón de disputa
- `TradeDetailScreen` muestra un botón **Disputa** cuando el conjunto de acciones contiene `actions.Action.dispute` y no hay una disputa ya en progreso.
- Al hacer tap en Disputa se muestra un diálogo de confirmación; si se confirma, llama a `DisputeRepository.createDispute(orderId)` (ver §2) y muestra un snackbar de éxito/error.
- Una vez que existe una disputa (`tradeState.dispute?.disputeId != null`), el CTA cambia a **Ver disputa** que enlaza a `/dispute_details/:disputeId`.

### Navegación automática vía eventos de Mostro
- `AbstractMostroNotifier` escucha acciones de DM de Mostro:
  - `disputeInitiatedByYou`, `disputeInitiatedByPeer`, `adminTookDispute`, `adminSettled`, `adminCanceled` todas hacen push a `/trade_detail/:orderId` para mantener a ambas partes en la pantalla de trade cuando cambia el estado de una disputa.
  - La asignación de admin (`adminTookDispute`) también actualiza la admin shared key de la sesión (ver §3), habilitando el chat de disputa para descifrar mensajes del admin.

---

## 2) Repositorio, modelo de datos y creación de disputas

### `DisputeRepository`
- `createDispute(orderId)` construye un `MostroMessage(action: Action.dispute, id: orderId)` y lo envuelve usando gift wrap NIP-59 con la `tradeKey` del usuario y la pubkey de Mostro configurada (`settingsProvider.mostroPublicKey`).
- La dificultad de proof-of-work usa `MostroInstance.pow`; si no está disponible loguea un warning y envía con dificultad 0.
- `NostrService.publishEvent` transmite el evento envuelto; el repositorio retorna `true/false` para mostrar snackbars.
- `getUserDisputes()` y `getDispute(disputeId)` nunca hacen llamadas a un endpoint remoto. Recorren todas las sesiones de `sessionNotifierProvider`, leen cada `orderNotifierProvider(orderId)` y recolectan objetos `OrderState.dispute`.

### Tipos de datos
- `Dispute` lleva campos a nivel de protocolo (IDs, status, pubkey del admin, timestamps, action) e implementa `Payload` para que los DMs de Mostro puedan embebarlo.
- `DisputeData` es el view model de la UI (order ID, contraparte, rol del usuario, `DisputeDescriptionKey`, etc.). Deriva `descriptionKey` de statuses normalizados y almacena si el usuario actual inició la disputa.
- `DisputeDescriptionKey` maneja el copy localizado ("Abriste una disputa", "Esperando asignación de admin", "Admin cerró la disputa"...).

### Normalización de status y action (desde `OrderState`)
- Las acciones `disputeInitiatedByYou`, `disputeInitiatedByPeer`, `dispute`, `adminTakeDispute`, `adminTookDispute` mapean a `Status.dispute`.
- `OrderState.updateWith()` enriquece las disputas:
  - Estampa `createdAt` del timestamp del DM para ordenamiento.
  - `adminTookDispute` establece `status: in-progress`, guarda `adminPubkey`, y dispara `Session.setAdminPeer`.
  - `adminSettled` ⇒ `status: resolved`, `action: admin-settled`.
  - `adminCanceled` ⇒ `status: seller-refunded`, `action: admin-canceled`.
  - Estados terminales de user-completed o cooperative-cancel auto-cierran la disputa (`status: closed`, `action: user-completed` o `cooperative-cancel`).

---

## 3) Sesión y handshake de admin shared key

- Las sesiones (`lib/data/models/session.dart`) almacenan tanto la shared key de la contraparte (`peer`) como una `adminSharedKey` opcional.
- Cuando llega `adminTookDispute`, `AbstractMostroNotifier` extrae la pubkey del admin del payload del evento (`Peer`) o del `Dispute.adminPubkey` existente, llama a `sessionNotifier.updateSession(orderId, setAdminPeer)` y recalcula la shared key vía ECDH.
- `DisputeChatNotifier` requiere `session.adminSharedKey` antes de suscribirse. Hasta que la key exista, escucha a `sessionNotifierProvider` y reintenta la suscripción automáticamente.
- Los adjuntos (`ChatFileUploadHelper`, `EncryptedImageUploadService`, `EncryptedFileUploadService`) llaman a `DisputeChatNotifier.getAdminSharedKey()` para obtener las keys ChaCha20 en raw para cifrado/descifrado.

---

## 4) UX de lista de disputas y estado de no leídos

### `DisputesList`
- Manejado por `userDisputeDataProvider`, que memoiza la lista de `DisputeData`, ordena por `createdAt` DESC, y se reconstruye cuando cambian las sesiones o estados de orden.
- Estado de carga: spinner centrado. Estado de error: icono + botón "Reintentar" que invalida el provider.
- Estado vacío: icono de mazo + texto de ayuda ("Tus disputas aparecerán aquí").

### `DisputeListItem`
- Envuelve `DisputeContent` y `DisputeIcon`; al hacer tap marca la disputa como leída vía `DisputeReadStatusService.markDisputeAsRead(disputeId)` y luego hace push a `/dispute_details/:id`.
- `DisputeContent` extrae:
  - `DisputeHeader` (badge de status con color vía `DisputeStatusBadge`).
  - Order ID (`DisputeOrderId`).
  - Texto de descripción (`DisputeDescription`) que, para `status == in-progress`, muestra el último mensaje admin/usuario obtenido de `disputeChatNotifierProvider`.
  - Punto de no leído: `FutureBuilder` llama a `DisputeReadStatusService.hasUnreadMessages(...)`, comparando timestamps de mensajes contra la key almacenada en `SharedPreferences` (`dispute_last_read_{id}`).
- `disputeReadStatusProvider` es un `StateProvider.family<int, String>` usado únicamente para disparar rebuilds cuando una disputa se marca como leída (bump de timestamp).

### Copy de descripción de pestaña
- Cuando `ChatTabType.disputes` está activo, `ChatRoomsScreen` muestra `S.disputesDescription` ("Aquí hablas con los admins"), reforzando que este es un espacio separado del chat P2P.

---

## 5) Pantalla de detalle de disputa y chat

### `DisputeChatScreen`
- Recibe `disputeId` desde GoRouter, `watch(disputeDetailsProvider(disputeId))` para cargar la última `Dispute` (o mostrar "no encontrada").
- En `initState`, marca la disputa como leída y actualiza `disputeReadStatusProvider`.
- Convierte el modelo de dominio (`Dispute`) a `DisputeData` usando tanto `sessionNotifierProvider` como `orderNotifierProvider` para extraer datos de rol/contraparte.
- Layout:
  1. `DisputeCommunicationSection` → `DisputeMessagesList`
  2. `DisputeMessageInput` renderizado **solo** cuando `DisputeData.status == 'in-progress'`. Las disputas iniciadas / resueltas se vuelven logs de solo lectura.

### `DisputeMessagesList`
- Combina UI informacional y mensajes de chat en un solo scroll view:
  - `SliverToBoxAdapter` muestra una card azul "Admin asignado" si status = `in-progress` y no hay mensajes aún.
  - El primer item de la lista siempre es `DisputeInfoCard` (order ID, dispute ID, rol del usuario, nickname de contraparte vía `nickNameProvider`).
  - Resto: entradas de `DisputeMessageBubble` ordenadas por timestamp, deduplicadas por message ID.
  - Para statuses resueltos (`resolved`, `seller-refunded`, `closed`), se agrega un banner extra "Chat cerrado" con candado.
- Maneja chat vacío elegantemente: copy de esperando-admin, placeholders de sin-mensajes-aún, etc.
- Auto-scroll al fondo cuando llegan nuevos mensajes y el usuario está cerca del fondo.

### `DisputeMessageInput`
- Comparte el mismo patrón UX que el chat P2P: botón de adjuntar (conectado a `ChatFileUploadHelper.selectAndUploadFile`), caja de texto, botón de enviar.
- El workflow de adjuntos usa la admin shared key en vez de la shared key de la contraparte.
- Mientras una subida de archivo está en progreso, el icono de adjuntar se reemplaza por un `CircularProgressIndicator`.

---

## 6) Pipeline de mensajería y almacenamiento

### Provider y estado
- `disputeChatNotifierProvider` es un `StateNotifierProvider.family<DisputeChatNotifier, DisputeChatState, String>`.
- `DisputeChatState` almacena `messages`, `isLoading`, y `error` (error global, ej., fallo al cargar historial). `DisputeChatMessage` envuelve `NostrEvent` con campos `isPending` y `error` por mensaje para UI optimista.

### Inicialización e historial
- `initialize()` carga el historial y suscribe una vez (guard idempotente `_isInitialized`).
- Los eventos históricos se almacenan en Sembast con `type: 'dispute_chat'` y `dispute_id: <id>`. Cada registro mantiene el payload completo del gift wrap (`kind`, `content`, `tags`, etc.).
- `_loadHistoricalMessages()` filtra por `type` + `dispute_id`, desenvuelve cada gift wrap con `session.adminSharedKey`, convierte a `DisputeChatMessage`, deduplica por inner event ID, y ordena ascendente.

### Suscripción en vivo
- `_subscribe()` construye un `NostrRequest` para eventos kind `1059` donde el tag `p` coincide con `session.adminSharedKey.public`.
- `NostrService.subscribeToEvents()` alimenta `_onChatEvent`:
  1. Verificar event kind y tag `p`.
  2. Saltar duplicados usando `eventStore.hasItem(wrapperEventId)`.
  3. Persistir el wrapper cifrado (`type: dispute_chat`).
  4. `p2pUnwrap` con la admin shared key (gift wrap de una capa).
  5. Saltar contenido vacío; crear `DisputeChatMessage` y agregar al estado (dedupe, sort).
  6. Fire-and-forget `_processMessageContent()` para pre-descargar archivos/imágenes Blossom.

### Envío de mensajes
- `sendMessage(text)` crea el inner rumor event (kind 1) **antes** de envolver para que la UI optimista use el message ID final.
- La UI agrega un bubble pendiente, envuelve el rumor con `session.adminSharedKey.public`, publica vía `nostrService.publishEvent`, y persiste el wrapper en Sembast.
- En fallo, el bubble pendiente cambia `error` y `isPending=false`.
- El eco del relay eventualmente llega vía `_onChatEvent`, que deduplica por ID.

### Soporte multimedia
- `DisputeMessageBubble` inspecciona el mensaje vía `MessageTypeUtils` (texto, imagen cifrada, archivo cifrado).
- Los widgets de imagen/archivo reusan el mixin de cache compartido (`MediaCacheMixin`) provisto por `DisputeChatNotifier`.
- La descarga de adjuntos requiere `getAdminSharedKey()`; shared keys faltantes lanzan una excepción y muestran errores en logs.

### Estado de lectura y badges
- `DisputeReadStatusService` almacena timestamps en `SharedPreferences` y expone `hasUnreadMessages(disputeId, messages, isFromUser)` para verificar si hay mensajes del admin más nuevos que el último tiempo de lectura.
- `DisputeChatScreen` marca la disputa como leída en `initState`; `DisputeListItem` también marca como leída al hacer tap desde la lista para mantener ambos puntos de entrada sincronizados.

---

## 7) Ciclo de vida de disputa e integración con status de orden

### Iniciación
1. Usuario hace tap en **Disputa** en Trade Detail.
2. `DisputeRepository.createDispute` envía el evento gift wrap.
3. Mostro responde con `disputeInitiatedByYou` (para el iniciador) y `disputeInitiatedByPeer` (para la contraparte).
4. `OrderState` almacena el payload de `Dispute`, `status` transiciona a `Status.dispute`, y la UI muestra el chip rojo "Disputa".

### Asignación de admin
1. Cuando un admin toma la disputa, Mostro envía `adminTookDispute` con un payload `Peer` representando al admin.
2. `OrderState.updateWith()` marca la disputa `status: in-progress` y copia la admin pubkey.
3. `Session.setAdminPeer` computa `adminSharedKey`, habilitando el cifrado del chat de disputa.
4. `DisputeMessagesList` muestra la card azul "Admin asignado" hasta que llega el primer mensaje.

### Caminos de resolución
- **Admin settled** (`adminSettled`): `Dispute.status = resolved`, `action = admin-settled`. `DisputeMessagesList` oculta el input y muestra el banner de candado. `DisputeStatusContent` renderiza "Admin devolvió los sats".
- **Admin canceled** (`adminCanceled`): `status = seller-refunded`, `action = admin-canceled`.
- **User completed** (pago Lightning exitoso) o **cooperative cancel**: la lógica de auto-cierre en `OrderState` establece `status = closed`, `action = user-completed / cooperative-cancel`. No se requiere involucramiento del admin.

### Flujos de no leídos + notificaciones
- Porque `DisputeReadStatusService` trabaja con timestamps, cualquier mensaje nuevo (admin o usuario) incrementa el badge automáticamente hasta que el usuario abre el chat.
- El badge del chat P2P (`chatCountProvider`) es independiente; las disputas actualmente dependen del punto rojo dentro de los items de lista.

---

## 8) Referencias cruzadas

| Tema | Documento |
|------|-----------|
| Acciones de Trade Detail y botón de disputa | [TRADE_EXECUTION.md](./TRADE_EXECUTION.md) |
| Transiciones de status de orden y cierre de disputa | [ORDER_STATUS_HANDLING.md](./ORDER_STATUS_HANDLING.md) |
| Arquitectura de chat P2P (widgets compartidos, pipeline de media) | [P2P_CHAT_SYSTEM.md](./P2P_CHAT_SYSTEM.md) |
| Gestión de sesiones y llaves (almacenamiento de admin shared key) | [SESSION_AND_KEY_MANAGEMENT.md](./SESSION_AND_KEY_MANAGEMENT.md) |
| Tabla de rutas de navegación | [NAVIGATION_ROUTES.md](./NAVIGATION_ROUTES.md) |

# Sistema de Chat P2P — Arquitectura de Implementación

Este documento describe cómo funciona el chat peer-to-peer entre las partes de trading a nivel de implementación: cómo fluyen los eventos desde los relays hasta la UI, cómo se persisten los mensajes, qué se almacena cifrado vs. en texto plano, y problemas conocidos que han sido corregidos.

Para la **especificación del protocolo** (NIP-59, ECDH, formato de evento), ver el [protocolo de Chat P2P de Mostro](https://mostro.network/protocol/chat.html) ([fuente](https://github.com/MostroP2P/protocol)).

---

## Alcance

Esta sección documenta todo lo que alimenta **Mostro Mobile v1 sección 7: CHAT PEER-TO-PEER**:

- Rutas `/chat_list` (hub de chat) y `/chat_room/:orderId` (sala de chat por trade) más los widgets de UI construidos sobre ellas (`ChatRoomsScreen`, `ChatRoomScreen`, `ChatTabs`, `MessageInput`, `MessageBubble`, etc.).
- Estado derivado de providers Riverpod: `chatRoomsProvider`, `chatRoomsNotifierProvider`, `sortedChatRoomsProvider`, `sessionProvider`, `orderNotifierProvider`, `chatTabProvider`.
- Plomería de mensajería: `ChatRoomNotifier`, `ChatRoomsNotifier`, `SubscriptionManager`, `eventStorage`, y los helpers de Blossom para upload/download de media.
- Indicadores de estado de lectura (`ChatReadStatusService`) y badges de navegación (`chatCountProvider`).
- Manejo de errores (sesiones faltantes, layout seguro con teclado) y hooks de ciclo de vida (`appInitializerProvider`, `LifecycleManager`).

Todo en este archivo ya está implementado en Dart/Flutter y necesita ser replicado (o consumido) por el nuevo stack.

## Navegación y Puntos de Entrada

- **Nav inferior:** `BottomNavBar` asigna índice de pestaña 2 a `/chat_list`. Observa `chatCountProvider` para dibujar un punto rojo cuando hay mensajes no leídos (otros flujos incrementan ese provider).
- **Drawer:** `ChatRoomsScreen` está envuelta por `CustomDrawerOverlay`, así que los atajos del drawer global también pueden hacer push a `/chat_list`.
- **Mis Trades → Chat:** `TradeDetailScreen` expone un botón "Contactar" que llama a `context.push('/chat_room/$orderId')` para que los usuarios puedan saltar directamente al chat threaded del trade activo.
- **Notificaciones:** `NotificationListenerWidget` y las acciones FCM rutean payloads de intent (ej., tap en un push "nuevo mensaje") a través de `GoRouter`, así que enlaces como `/chat_room/{orderId}` llegan a la misma pantalla.

Desde el punto de vista del usuario, el stack de navegación siempre es: **Home → Mis Trades → Trade Detail → Chat** o Home → pestaña de Chat.

## Lista de Chat (`ChatRoomsScreen`, ruta `/chat_list`)

### Layout y pestañas

- Rootea dentro de un `Scaffold` con `MostroAppBar`, drawer overlay, y un `BottomNavBar` permanentemente fijado.
- La sección de header renderiza el título "Chat" más el componente `ChatTabs` (dos pestañas: `messages` y `disputes`). Deslizar izquierda/derecha en el área de contenido también alterna entre pestañas vía `chatTabProvider`.
- Debajo de las pestañas hay un copy de descripción corta (diferente por pestaña) y luego el área de contenido principal. Cuando tab = `ChatTabType.disputes`, el widget cambia a `DisputesList` (mismo componente usado por el módulo de disputas).
- Cuando tab = `messages`, `_buildBody()` renderiza ya sea `EmptyStateView` (si no hay chats) o un `ListView.builder` de `ChatListItem`s. Padding inferior extra mantiene el contenido despejado de la nav bar.

### Fuentes de datos y ordenamiento

- La pantalla observa `sortedChatRoomsProvider`, que:
  1. Escucha a `chatRoomsNotifierProvider` (un `StateNotifier<List<ChatRoom>>`).
  2. Para cada `ChatRoom` re-lee `chatRoomsProvider(orderId)` para asegurar que se usa el estado en memoria más fresco (mensajes, metadata).
  3. Ordena chats por el tiempo de inicio de sesión (`sessionProvider(orderId).startTime`), más reciente primero. Si falta una sesión, hace fallback a `DateTime.now()` para que los chats nuevos floten hacia arriba.
- `ChatRoomsNotifier` construye su lista desde `sessionNotifierProvider.sessions`. Solo se muestran sesiones que (a) tienen un `orderId`, (b) tienen un `peer` o comenzaron en la última hora, y (c) ya obtuvieron al menos un mensaje. Esto previene que shells vacíos llenen la lista. Cuando un chat gana mensajes, `ChatRoomNotifier` llama a `refreshChatList()` para que la lista se re-ordene.
- El startup de la app (`appInitializerProvider`) instancia eagerly `chatRoomsProvider(orderId)` para todas las sesiones no expiradas para que `_loadHistoricalMessages()` corra antes de que el usuario abra la pestaña de chat.

### Detalles del item de lista de chat

- `ChatListItem` compone:
  - **Avatar y handle:** `NymAvatar` + `nickNameProvider(peerPubkey)`.
  - **Línea de contexto:** "Estás vendiendo a/comprando de {handle}" basado en `session.role`.
  - **Preview del último mensaje:** La última entrada en `chatRoom.messages` (el constructor ordena ascendente, así que `.last` es el más nuevo). Los mensajes propios tienen prefijo con el label localizado "Tú:".
  - **Chip de timestamp:** Usa `Intl.DateFormat` para mostrar `HH:mm`, "Ayer", día de la semana, o `MMM d` dependiendo de la antigüedad.
  - **Punto de no leído:** `ChatReadStatusService.hasUnreadMessages(orderId, messages, currentUserPubkey)` compara el último timestamp de lectura (almacenado en `SharedPreferences`) contra mensajes del peer. Si cualquier mensaje del peer es más nuevo, se muestra un punto rojo hasta que el usuario entre a la sala. `onTap` optimistamente establece `_isMarkedAsRead = true`, await `markChatAsRead()`, y luego hace push a `/chat_room/{orderId}`.
- Los skeletons placeholder se renderizan mientras falta sesión o info del peer, para que la altura de la lista se mantenga estable durante el churn de providers.

## Sala de Chat (`ChatRoomScreen`, ruta `/chat_room/:orderId`)

### Estructura y dependencias

- Observa `chatRoomsProvider(orderId)` para mensajes/estado descifrados, `sessionProvider(orderId)` para rol + metadata del peer, y `orderNotifierProvider(orderId)` para status de orden en vivo (pasado a las pestañas de info).
- Si falta la sesión o el peer, la pantalla inmediatamente retorna `ChatErrorScreen.sessionNotFound()` / `.peerUnavailable()` en lugar de intentar enviar mensajes sin una shared key.
- El Scaffold incluye una app bar custom ("Atrás"), el `PeerHeader`, pestañas de info opcionales, la lista de mensajes, el compositor, y (cuando el teclado está oculto) el `BottomNavBar` global para que los usuarios puedan ir a otro lugar sin hacer pop del stack.
- `_selectedInfoType` alterna entre `null`, `'trade'`, y `'user'`. Enfocar el input de mensaje automáticamente limpia cualquier panel de info vía `_handleInfoTypeChanged(null)` para que el compositor nunca se superponga al sheet.

### Paneles de info de trade y usuario

- `InfoButtons` expone dos botones estilo CTA:
  - **Información del trade** (`TradeInformationTab`): muestra order ID, monto fiat, "Comprando/Vendiendo {sats}" formateado, chip de status localizado (colores de `AppTheme`), método de pago, y fecha de creación. Depende de `order.copyWith(status: orderState.status)` para que la UI refleje actualizaciones del FSM local.
  - **Información del usuario** (`UserInformationTab`): muestra el avatar del peer, handle, clave pública (copiable vía `ClickableText`), tu propio handle, y la shared key derivada (o "No disponible" si la sesión no ha negociado llaves aún).

### Timeline de mensajes

- `ChatMessagesList` renderiza `chatRoom.messages` ordenados cronológicamente (más viejo primero) usando un `ScrollController` dedicado. Auto-scrollea al fondo en la primera carga y cuando cambia el conteo de mensajes. El controller también está conectado a `_scrollController` en `ChatRoomScreen` para que la visibilidad del teclado dispare pequeñas animaciones de scroll que mantienen el compositor visible.
- Cada mensaje es renderizado por `MessageBubble`, que detecta tipo de contenido vía `MessageTypeUtils`:
  - Texto plano → bubble estándar con long-press copiar al clipboard.
  - `image_encrypted` → `EncryptedImageMessage`, incluyendo previews cacheados y manejo seguro de abrir-en-viewer.
  - `file_encrypted` → `EncryptedFileMessage`, incluyendo botones de descarga, chips de metadata, y archivos temporales seguros.
- Envíos optimistas: después de que el usuario envía un mensaje, el `NostrEvent` en texto plano se agrega inmediatamente para que aparezca en la lista antes de que llegue el eco del relay.

### Compositor y adjuntos

- `MessageInput` mantiene un `TextEditingController`, `FocusNode`, y un flag `_isUploadingFile`. El icono de adjuntar está deshabilitado y muestra un spinner mientras corren los uploads.
- `_sendMessage()` hace trim del whitespace, delega a `chatRoomsProvider(orderId).notifier.sendMessage(text)`, limpia el campo, y re-enfoca el input.
- `_selectAndUploadFile()` llama a `ChatFileUploadHelper.selectAndUploadFile()` con tres callbacks:
  - `getSharedKey` (de `ChatRoomNotifier`) retorna los bytes raw de la llave ChaCha20.
  - `sendMessage` postea el JSON de metadata retornado por los servicios de upload.
  - `isMounted` protege actualizaciones de snackbar/diálogo cuando el widget tree ya no existe.
- `ChatFileUploadHelper` aplica límites de tamaño/tipo de archivo vía `FileValidationService` + `MediaValidationService`, corre un diálogo de confirmación, cifra el archivo con ChaCha20-Poly1305, sube a Blossom (`BlossomUploadHelper`/`BlossomClient`), y finalmente envía el blob JSON `image_encrypted` o `file_encrypted` de vuelta a través del pipeline de chat.

### Teclado, drawer y errores

- `didChangeDependencies` escucha aperturas de teclado; cuando el teclado se abre scrollea la lista hacia abajo un poco para mantener los últimos mensajes sin obstrucción.
- La lista de mensajes está envuelta en `CustomDrawerOverlay`, así que deslizar desde el borde aún revela el drawer global incluso dentro de un chat.
- Mientras `ChatRoomNotifier` aún está cargando historial, la UI muestra un `CircularProgressIndicator` centrado. Si la inicialización falla, el notifier deja `chatRoomInitializedProvider` como `false` y la UI permanece en estado de carga hasta que el usuario sale.

---

## Componentes de Estado y Transporte


| Componente | Archivo | Responsabilidad |
|---|---|---|
| `SubscriptionManager` | `lib/features/subscriptions/subscription_manager.dart` | Suscripción única de Nostr para todos los chats, stream broadcast |
| `ChatRoomNotifier` | `lib/features/chat/notifiers/chat_room_notifier.dart` | Chat por orden: recibe eventos, almacena en disco, descifra, maneja estado |
| `ChatRoomsNotifier` | `lib/features/chat/notifiers/chat_rooms_notifier.dart` | Lista de chat: carga, refresca, recarga todos los chats |
| `chatRoomsProvider` | `lib/features/chat/chat_room_provider.dart` | Provider family de Riverpod, crea e inicializa `ChatRoomNotifier` |
| `EventStorage` | `lib/data/repositories/event_storage.dart` | Store de Sembast para eventos gift wrap |
| `Session` | `lib/data/models/session.dart` | Mantiene llaves de trade, info del peer, computa shared key vía ECDH |
| Extensiones de `NostrEvent` | `lib/data/models/nostr_event.dart` | `p2pWrap()` / `p2pUnwrap()` — cifrar/descifrar gift wraps |

---

## Flujo de Mensaje: Recepción

```text
Relay
  │  eventos gift wrap kind 1059 (cifrados)
  ▼
NostrService (WebSocket)
  │
  ▼
SubscriptionManager
  │  UNA suscripción con TODAS las pubkeys sharedKey en un solo NostrFilter
  │  Eventos despachados vía StreamController.broadcast()
  ▼
ChatRoomNotifier._onChatEvent()  (un listener por chat activo)
  │
  ├─ 1. Verificar que p-tag coincide con sharedKey.public de este chat → saltar si no es nuestro
  ├─ 2. Dedup: eventStore.hasItem(event.id) → saltar si ya almacenado
  ├─ 3. Almacenar gift wrap cifrado a Sembast (kind 1059, contenido cifrado NIP-44)
  ├─ 4. Descifrar: event.p2pUnwrap(sharedKey) → evento kind 1 en texto plano
  ├─ 5. Agregar a state.messages (solo en memoria)
  └─ 6. Notificar lista de chat para refrescar
```

### Detalle clave: suscripción única, múltiples listeners

`SubscriptionManager` crea **una** suscripción de relay conteniendo todas las pubkeys de shared key de chats activos:

```dart
// subscription_manager.dart — _createFilterForType()
NostrFilter(
  kinds: [1059],
  p: sessions
      .where((s) => s.sharedKey?.public != null)
      .map((s) => s.sharedKey!.public)
      .toList(),  // TODAS las shared keys en UN filtro
);
```

El relay envía eventos para todos los chats a través de esta suscripción única. Los eventos se despachan vía un `StreamController.broadcast()` a todas las instancias de `ChatRoomNotifier`. Cada notifier verifica el tag `p` del evento para determinar si el evento pertenece a su chat.

---

## Flujo de Mensaje: Envío

```text
Usuario escribe mensaje
  │
  ▼
ChatRoomNotifier.sendMessage(text)
  │
  ├─ 1. Crear evento inner kind 1, firmado con tradeKey
  ├─ 2. p2pWrap(tradeKey, sharedKey.public) → gift wrap kind 1059
  │     - Genera par de llaves efímeras (uso único)
  │     - Cifra JSON del evento inner con NIP-44 (privada efímera + pubkey compartida)
  │     - p-tag = sharedKey.public
  │     - Timestamp aleatorizado para prevenir análisis de tiempo
  ├─ 3. Publicar evento wrapped al relay
  ├─ 4. Persistir evento wrapped a Sembast (cifrado, kind 1059)
  ├─ 5. Agregar evento inner (texto plano) a state.messages para display inmediato en UI
  └─ 6. Notificar lista de chat para refrescar
```

El paso 4 asegura que los mensajes enviados sobrevivan reinicios de la app incluso si el eco del relay nunca llega (ej., conexión se cae después de enviar). Cuando el eco del relay llega, `_onChatEvent` lo salta vía la verificación de dedup `hasItem`.

---

## Almacenamiento: Qué Hay en Disco

Los eventos se almacenan en el store `events` de Sembast como gift wraps cifrados:

```dart
{
  'id': event.id,                    // hash del evento
  'created_at': <timestamp unix>,
  'kind': 1059,                      // gift wrap
  'content': '<cifrado NIP-44>',     // ciphertext — NO legible sin llave privada
  'pubkey': '<pubkey efímera>',      // llave de uso único, no identifica al remitente
  'sig': '<firma efímera>',
  'tags': [['p', '<sharedKey.public>']],
  'type': 'chat',                    // metadata de la app
  'order_id': '<orderId>',           // metadata de la app — vincula evento a un trade específico
}
```

**Propiedades de privacidad:**
- El campo `content` está cifrado con NIP-44. Leerlo requiere el componente privado de la shared key ECDH.
- La `pubkey` es una llave efímera generada por mensaje. No identifica al remitente.
- El tag `p` contiene el componente público de la shared key, no la identidad real de ninguna parte.
- El `order_id` es metadata interna de la app no presente en el evento Nostr mismo.

**Qué NO está en disco:**
- Contenido de mensaje en texto plano
- Identidad del remitente (la pubkey de trade está dentro del payload cifrado)
- Ninguna llave privada

---

## Almacenamiento: Qué Hay en Memoria

`state.messages` mantiene objetos `NostrEvent` descifrados (kind 1) en RAM:

```dart
// Después de p2pUnwrap:
NostrEvent(
  kind: 1,
  content: "¡Reestablezcamos la naturaleza peer-to-peer de Bitcoin!",  // texto plano
  pubkey: "<pubkey de trade del remitente>",
  // ...
)
```

Estos existen **solo en memoria**. Cuando la app se cierra, se pierden. Al reiniciar, `_loadHistoricalMessages()` lee los gift wraps cifrados de Sembast y los descifra de nuevo.

---

## Ciclo de Vida de Shared Key

La shared key nunca se almacena directamente. Se computa vía ECDH cada vez que una `Session` tiene un `peer`:

```dart
// session.dart
set peer(Peer? newPeer) {
  _peer = newPeer;
  _sharedKey = NostrUtils.computeSharedKey(
    tradeKey.private,
    newPeer.publicKey,
  );
}
```

Al reiniciar la app:
1. `SessionNotifier.init()` carga sesiones desde Sembast (peer está persistido)
2. El constructor de `Session` llama a `computeSharedKey` con la clave pública del peer persistido
3. La shared key está disponible en memoria — no se necesita almacenamiento separado

---

## Secuencia de Inicialización

### Startup de app (`app_init_provider.dart`)

```text
1. NostrService.init()         → conexiones a relay
2. KeyManager.init()           → llaves crypto desde secure storage
3. MostroNodes.init()          → metadata de nodos
4. SessionNotifier.init()      → carga sesiones desde Sembast (sharedKey computada aquí)
5. SubscriptionManager creado  → suscribe al relay con todas las llaves de sesión
6. Para cada sesión con peer:
   └─ Leer chatRoomsProvider(orderId) → crea ChatRoomNotifier
      └─ _initializeChatRoomSafely() [async]
         ├─ _loadHistoricalMessages() → lee eventos cifrados de disco, descifra
         └─ subscribe() → escucha el stream broadcast
```

### Inicialización de sala de chat (`chat_room_provider.dart`)

Cuando `chatRoomsProvider(orderId)` se lee por primera vez:
1. Crea un `ChatRoomNotifier` con mensajes vacíos
2. Llama a `_initializeChatRoomSafely()` (async, fire-and-forget)
3. Retorna el notifier inmediatamente (los mensajes pueden no estar cargados aún)

`_initializeChatRoomSafely()` entonces:
1. Llama a `notifier.initialize()` → carga historial de disco + suscribe al stream
2. Marca `chatRoomInitializedProvider(chatId)` como true

### Reconexión (`lifecycle_manager.dart`)

Cuando la app vuelve a primer plano después de perder conexión:
1. `NostrService` reconecta a los relays
2. Se llama a `reloadAllChats()`
3. Cada `ChatRoomNotifier.reload()`:
   - Cancela listener de stream actual
   - Recarga mensajes de disco (`_loadHistoricalMessages`)
   - Re-suscribe al stream broadcast

---

## Carga Histórica (`_loadHistoricalMessages`)

```text
Query Sembast: WHERE type = 'chat' AND order_id = orderId
  │
  ▼
Para cada evento almacenado:
  ├─ Reconstruir NostrEvent del map almacenado
  ├─ Verificar que p-tag coincide con session.sharedKey.public
  ├─ p2pUnwrap(sharedKey) → descifrar a evento inner kind 1
  └─ Agregar a lista historicalMessages
  │
  ▼
Merge con state.messages existente, deduplicar por ID, ordenar por created_at
```

La verificación del p-tag durante la carga (línea 353) actúa como filtro de seguridad: incluso si un evento de alguna manera se almacenó con un `order_id` incorrecto, no se mostrará en el chat equivocado porque la llave de descifrado no coincidiría.

---

## Mensajes Multimedia

Los mensajes de texto tienen contenido de string plano. Los mensajes multimedia usan contenido JSON:

### Envío
1. Archivo/imagen cifrado con ChaCha20-Poly1305 usando bytes de shared key
2. Subido a servidor Blossom (blob cifrado)
3. Metadata JSON enviada como contenido del mensaje: `{ "type": "image_encrypted", "blossomUrl": "...", ... }`
4. El JSON está dentro del gift wrap NIP-44 — doblemente cifrado

### Recepción
1. Gift wrap llega → descifrado a kind 1 → contenido JSON detectado
2. `_processMessageContent()` identifica `image_encrypted` / `file_encrypted`
3. Descarga blob cifrado de Blossom, descifra con shared key
4. Cachea media descifrado en memoria (`MediaCacheMixin`)

**Disco**: Solo el gift wrap se almacena (URL de Blossom dentro del payload cifrado).
**Memoria**: Media descifrado cacheado para display, limpiado en dispose.

## Estado de Lectura y Badges de Notificación

- **Estado por chat:** `ChatReadStatusService` almacena timestamps `chat_last_read_{orderId}` en `SharedPreferences`. Cuando el usuario abre una sala, `markChatAsRead()` registra `DateTime.now()`; `hasUnreadMessages()` compara ese timestamp contra el último mensaje del peer para que `ChatListItem` pueda mostrar un punto rojo.
- **Pipeline de badge global:** `chatCountProvider` (declarado en `bottom_nav_bar.dart`) es write-only para handlers de background/push y read-only para la UI. `BottomNavBar` simplemente observa el provider para decidir si dibujar el badge. Las superficies de mensajes entrantes (`ChatRoomNotifier._onChatEvent()` para ecos de relay más cualquier handler de push/background que reciba un mensaje mientras el usuario está fuera de esa sala) son los únicos lugares que incrementan el provider, y lo hacen después de llamar a `chatRoomsNotifierProvider.notifier.refreshChatList()` para mantener el orden de lista/puntos de no leídos sincronizados. `sendMessage()` también llama a `refreshChatList()` pero nunca decrementa el badge (envíos locales no deberían alterar conteos de no leídos).
- **Confirmación de lectura / resets:** `markChatAsRead()` es el único camino permitido para limpiar/quitar el badge. Después de persistir el timestamp vía `ChatReadStatusService`, invoca el helper de reset de badge (ej. `chatCountProvider.notifier.resetForChat(orderId)` / `refreshBadge()`), asegurando que cada decremento fluya a través de una única API y previniendo que handlers externos muten el conteo directamente.

## Ciclo de Vida y Recargas

- **Init de app:** `appInitializerProvider` carga llaves, sesiones, y el subscription manager, luego instancia `chatRoomsProvider(orderId)` para cada sesión reciente. Esto garantiza que `_loadHistoricalMessages()` corra una vez en startup, incluso si la pestaña de chat no ha sido abierta aún.
- **Resume a primer plano:** `LifecycleManager` escucha por `AppLifecycleState.resumed`. Cuando dispara re-suscribe a relays, reinicializa `MostroService`, pide al repositorio de órdenes que recargue, y await `chatRoomsNotifierProvider.notifier.reloadAllChats()` para que cada `ChatRoomNotifier` cancele su stream viejo, recargue historial de disco, y se reatache a `subscriptionManager.chat`.
- **Handoff a background:** En `AppLifecycleState.paused`, `LifecycleManager` captura los filtros Nostr activos y los pasa a `backgroundServiceProvider` para que las push notifications sigan streaming; también desuscribe el `SubscriptionManager` de primer plano para evitar eventos duplicados.

---

## Bug: Pérdida de Mensajes Después de Reconexión

### Síntoma

Con 2+ trades activos, los mensajes de la contraparte desaparecen después de cerrar y reabrir la app. Restaurar el usuario los trae de vuelta.

### Causas raíz encontradas y corregidas

#### 1. Condición de carrera del stream broadcast (causa principal)

**Problema**: Todas las instancias de `ChatRoomNotifier` escuchan el mismo stream broadcast. Cuando llega un evento, cada notifier lo recibe. Antes del fix, `_onChatEvent` almacenaba el evento en disco con su propio `orderId` **antes** de verificar el tag `p` para verificar propiedad. Con múltiples notifiers concurrentes:

- Notifier A almacena evento con `order_id: "orderA"` (incorrecto)
- Notifier B almacena mismo evento con `order_id: "orderB"` (correcto)
- Sembast hace upsert — el último escritor gana
- Si A escribe último, el evento tiene el `order_id` incorrecto en disco
- Al reiniciar, notifier B consulta `WHERE order_id = "orderB"` — no lo encuentra

**Fix**: Verificar que el tag `p` coincide con `session.sharedKey.public` **antes** de cualquier escritura a disco. Solo el notifier propietario almacena el evento.

#### 2. Doble suscripción por chat

**Problema**: `app_init_provider.dart` explícitamente llamaba a `subscribe()` en cada `ChatRoomNotifier`, pero crear el provider ya dispara `_initializeChatRoomSafely()` → `initialize()` → `subscribe()`. Esto resultaba en 2 listeners por chat en el stream broadcast, duplicando la contención de escritura a disco.

**Fix**: Removida la llamada explícita a `subscribe()` de `app_init_provider.dart`. La inicialización del provider maneja la suscripción.

#### 3. Lista de chat vacía después de inicialización async

**Problema**: `ChatRoomsNotifier.loadChats()` filtra chats por `messages.isNotEmpty`, pero la inicialización de `ChatRoomNotifier` es async. Cuando `loadChats()` corre, los mensajes no se han cargado aún → todos los chats filtrados. Ningún código llamaba a `refreshChatList()` después de que la inicialización completaba.

**Fix**: `_initializeChatRoomSafely()` llama a `refreshChatList()` después de inicialización exitosa.

#### 4. `reloadAllChats()` opera en estado vacío

**Problema**: `reloadAllChats()` itera sobre `state` (la lista de chat actual). Si `state` está vacío debido al issue #3, nada se recarga.

**Fix**: `reloadAllChats()` itera sobre sesiones (fuente de verdad) en lugar de `state`.

#### 5. Mensajes enviados no persistidos (pre-existente)

**Problema**: `sendMessage()` solo publicaba al relay y agregaba al estado en memoria. Si el eco del relay nunca llegaba (caída de conexión), el mensaje enviado se perdía al reiniciar.

**Fix**: `sendMessage()` persiste el evento wrapped a Sembast inmediatamente después de publicación exitosa.

#### 6. `reload()` no cargaba de disco (pre-existente)

**Problema**: `reload()` solo cancelaba y re-suscribía al stream. No llamaba a `_loadHistoricalMessages()`, así que la reconexión no podía recuperar mensajes de disco.

**Fix**: `reload()` llama a `_loadHistoricalMessages()` antes de re-suscribir.

---

## Referencia de Archivos

| Archivo | Rol |
|---|---|
| `lib/features/subscriptions/subscription_manager.dart` | Suscripción única, stream broadcast, construcción de filtros |
| `lib/features/chat/notifiers/chat_room_notifier.dart` | Manejo de eventos por chat, almacenamiento, descifrado, estado de mensajes |
| `lib/features/chat/notifiers/chat_rooms_notifier.dart` | Gestión de lista de chat, loadChats, refreshChatList, reloadAllChats |
| `lib/features/chat/chat_room_provider.dart` | Creación de provider, inicialización async |
| `lib/shared/providers/app_init_provider.dart` | Secuencia de startup de app, setup de suscripción de chat |
| `lib/data/repositories/event_storage.dart` | Wrapper de Sembast para persistencia de eventos |
| `lib/data/models/session.dart` | Modelo de sesión, cómputo de shared key ECDH |
| `lib/data/models/nostr_event.dart` | Cifrado/descifrado p2pWrap / p2pUnwrap |
| `lib/services/lifecycle_manager.dart` | Transiciones primer plano/background, recarga de chat |

## Referencias Cruzadas

| Tema | Documento |
|------|-----------|
| Pipeline de media de chat | [.specify/v1-reference/ENCRYPTED_IMAGE_MESSAGING_IMPLEMENTATION.md](./ENCRYPTED_IMAGE_MESSAGING_IMPLEMENTATION.md) |
| Sesiones y shared keys | [.specify/v1-reference/SESSION_AND_KEY_MANAGEMENT.md](./SESSION_AND_KEY_MANAGEMENT.md) |
| Acciones de trade detail (botón de chat) | [.specify/v1-reference/TRADE_EXECUTION.md](./TRADE_EXECUTION.md) |
| Lista de Mis Trades (fuente de sesiones de chat) | [.specify/v1-reference/MY_TRADES.md](./MY_TRADES.md) |

*Las conversaciones de disputa reusan los mismos widgets de chat; ver [DISPUTE_SYSTEM.md](./DISPUTE_SYSTEM.md) para la especificación dedicada.*

---

*Última Actualización: Marzo 2026*
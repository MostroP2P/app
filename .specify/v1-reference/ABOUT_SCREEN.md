# Pantalla Acerca de (Referencia v1)

> Información de la app, enlaces a documentación, y detalles del nodo Mostro.

**Ruta:** `/about`

## Layout de Pantalla

```text
┌─────────────────────────────────────────────────────┐
│  ←  Acerca de                                       │  AppBar
├─────────────────────────────────────────────────────┤
│                                                     │
│  ┌───────────────────────────────────────────────┐  │
│  │  📱  Información de la App                    │  │
│  │                                               │  │
│  │  Versión              0.2.5                   │  │
│  │                                               │  │
│  │  Repositorio GitHub   mostro-mobile  ↗️       │  │
│  │                                               │  │
│  │  Hash de Commit       abc1234                 │  │
│  │                                               │  │
│  │  Licencia             MIT                     │  │
│  └───────────────────────────────────────────────┘  │
│                                                     │
│  ┌───────────────────────────────────────────────┐  │
│  │  📖  Documentación                            │  │
│  │                                               │  │
│  │  Usuarios (Inglés)    Leer  ↗️                │  │
│  │                                               │  │
│  │  Usuarios (Español)   Leer  ↗️                │  │
│  │                                               │  │
│  │  Técnica              Leer  ↗️                │  │
│  └───────────────────────────────────────────────┘  │
│                                                     │
│  ┌───────────────────────────────────────────────┐  │
│  │  🖥️  Nodo Mostro                              │  │
│  │                                               │  │
│  │  ══ Info General ══                           │  │
│  │                                               │  │
│  │  Clave Pública Mostro npub1m0str0...  ℹ️ 📋   │  │
│  │  Monto Máximo Orden   10,000,000 Satoshis ℹ️  │  │
│  │  Monto Mínimo Orden   100 Satoshis       ℹ️  │  │
│  │  Vida de Orden        24 horas           ℹ️  │  │
│  │  Comisión Servicio    0.6%               ℹ️  │  │
│  │  Monedas Fiat         Todas              ℹ️  │  │
│  │                                               │  │
│  │  ══ Detalles Técnicos ══                      │  │
│  │                                               │  │
│  │  Versión Mostro       0.12.5             ℹ️  │  │
│  │  Commit Mostro        def5678             ℹ️  │  │
│  │  Expiración Orden     900 seg             ℹ️  │  │
│  │  Exp. Hold Invoice    86400 seg           ℹ️  │  │
│  │  CLTV Hold Invoice    144 bloques         ℹ️  │  │
│  │  Ventana Exp. Invoice 3600 segundos       ℹ️  │  │
│  │  Proof of Work        0                   ℹ️  │  │
│  │  Órdenes Máx/Resp     50                  ℹ️  │  │
│  │                                               │  │
│  │  ══ Lightning Network ══                      │  │
│  │                                               │  │
│  │  Versión LND          0.18.0-beta        ℹ️  │  │
│  │  Clave Pública LND    02abc...      ℹ️ 📋   │  │
│  │  Commit LND           ghi9012             ℹ️  │  │
│  │  Alias Nodo LND       MostroNode          ℹ️  │  │
│  │  Cadenas Soportadas   bitcoin             ℹ️  │  │
│  │  Redes Soportadas     mainnet             ℹ️  │  │
│  │  URI Nodo LND         02abc@host:9735 ℹ️ 📋  │  │
│  └───────────────────────────────────────────────┘  │
│                                                     │
└─────────────────────────────────────────────────────┘
```

## Detalle de Cards

### 1. Card de Información de la App

**Icono:** `LucideIcons.smartphone`, mostroGreen, 20px

| Campo | Fuente del Valor | Clickeable |
|-------|------------------|------------|
| Versión | Variable de entorno `APP_VERSION` | No |
| Repositorio GitHub | URL estática | Sí → abre GitHub |
| Hash de Commit | Variable de entorno `GIT_COMMIT` | No |
| Licencia | "MIT" | Sí → muestra diálogo de licencia |

**Diálogo de Licencia:**
- Texto completo de licencia MIT en contenedor scrolleable
- Fuente monoespaciada
- Botón cerrar

### 2. Card de Documentación

**Icono:** `LucideIcons.book`, mostroGreen, 20px

| Enlace | URL |
|--------|-----|
| Usuarios (Inglés) | https://mostro.network/docs-english/ |
| Usuarios (Español) | https://mostro.network/docs-spanish/ |
| Técnica | https://mostro.network/protocol/ |

**Filas clickeables** con icono de enlace externo (↗️).

### 3. Card de Nodo Mostro

**Icono:** `LucideIcons.server`, mostroGreen, 20px

**Estado de Carga:** Muestra spinner mientras obtiene info del nodo.

**Fuente de Datos:** `MostroInstance` del evento de anuncio del daemon.

#### Sección Info General

| Campo | Clave | Formato |
|-------|-------|---------|
| Clave Pública Mostro | `pubKey` | Truncada, copiable |
| Monto Máximo Orden | `maxOrderAmount` | Número formateado + "Satoshis" |
| Monto Mínimo Orden | `minOrderAmount` | Número formateado + "Satoshis" |
| Vida de Orden | `expirationHours` | Número + "horas" |
| Comisión Servicio | `fee` | Porcentaje (fee * 100 + "%") |
| Monedas Fiat | `fiatCurrenciesAccepted` | Separadas por coma o "Todas" |

#### Sección Detalles Técnicos

| Campo | Clave |
|-------|-------|
| Versión Mostro | `mostroVersion` |
| Commit Mostro | `commitHash` |
| Expiración Orden | `expirationSeconds` + "seg" |
| Expiración Hold Invoice | `holdInvoiceExpirationWindow` + "seg" |
| CLTV Delta Hold Invoice | `holdInvoiceCltvDelta` + "bloques" |
| Ventana Expiración Invoice | `invoiceExpirationWindow` + "segundos" |
| Proof of Work | `pow` |
| Órdenes Máx Por Respuesta | `maxOrdersPerResponse` |

#### Sección Lightning Network

| Campo | Clave |
|-------|-------|
| Versión LND | `lndVersion` |
| Clave Pública Nodo LND | `lndNodePublicKey` (copiable) |
| Commit LND | `lndCommitHash` |
| Alias Nodo LND | `lndNodeAlias` |
| Cadenas Soportadas | `supportedChains` |
| Redes Soportadas | `supportedNetworks` |
| URI Nodo LND | `lndNodeUri` (copiable) |

## Patrones de Fila de Info

### Fila de Info Estándar

```text
Label              Valor
```

- Label: `textSecondary`, 14sp
- Valor: `textPrimary`, 14sp, peso medium

### Fila de Info con Diálogo

```text
Label  ℹ️
Valor
```

- Tap ℹ️ → muestra diálogo de explicación
- Icono de info: 16px, `textSecondary`

### Fila de Info con Diálogo y Copiar

```text
Label  ℹ️  📋
Valor (truncado)
```

- Tap ℹ️ → diálogo de explicación
- Tap 📋 → copia valor al clipboard
- Muestra snackbar "Copiado al portapapeles"

## Headers de Sección

```dart
Text(
  "Info General",
  style: TextStyle(
    color: AppTheme.activeColor,  // mostroGreen
    fontSize: 16,
    fontWeight: FontWeight.w600,
  ),
)
```

## Diálogos de Info

Cada botón ℹ️ muestra un diálogo con explicación:

| Campo | Clave de Explicación |
|-------|----------------------|
| Clave Pública Mostro | `mostroPublicKeyExplanation` |
| Monto Máximo Orden | `maxOrderAmountExplanation` |
| Monto Mínimo Orden | `minOrderAmountExplanation` |
| Vida de Orden | `orderExpirationExplanation` |
| Comisión Servicio | `serviceFeeExplanation` |
| ... | (todos los campos tienen explicaciones) |

Las explicaciones son strings i18n que describen qué significa cada campo y por qué importa.

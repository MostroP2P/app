// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Spanish Castilian (`es`).
class AppLocalizationsEs extends AppLocalizations {
  AppLocalizationsEs([String locale = 'es']) : super(locale);

  @override
  String get appName => 'Mostro';

  @override
  String get loading => 'Cargando…';

  @override
  String get error => 'Error';

  @override
  String get cancel => 'Cancelar';

  @override
  String get confirm => 'Confirmar';

  @override
  String get done => 'Listo';

  @override
  String get skip => 'Omitir';

  @override
  String get chatTimestampYesterday => 'Ayer';

  @override
  String get disputesEmptyState => 'Tus disputas aparecerán aquí';

  @override
  String get disputeAttachFile => 'Adjuntar archivo';

  @override
  String get disputeWriteMessageHint => 'Escribe un mensaje…';

  @override
  String get disputeSend => 'Enviar';

  @override
  String get orderDispute => 'Disputa de orden';

  @override
  String get disputeAdminAssigned =>
      'Se ha asignado un administrador a tu disputa. Se pondrá en contacto contigo aquí en breve.';

  @override
  String get disputeChatClosed =>
      'Esta disputa ha sido resuelta. El chat está cerrado.';

  @override
  String get messageCopied => 'Copiado';

  @override
  String get disputeLoadError =>
      'No se pudieron cargar las disputas. Por favor, inténtalo de nuevo.';

  @override
  String get disputeMessagingComingSoon => 'Mensajería de disputa próximamente';

  @override
  String get disputeAttachmentsComingSoon => 'Archivos adjuntos próximamente';

  @override
  String get disputeNotFound => 'Disputa no encontrada.';

  @override
  String get disputeNotFoundForOrder =>
      'No se encontró ninguna disputa para esta orden.';

  @override
  String get disputeResolved => 'Resuelto';

  @override
  String get disputeSuccessfullyCompleted => 'Completado con éxito';

  @override
  String get disputeCoopCancelMessage =>
      'La orden fue cancelada cooperativamente. No se transfirieron fondos.';

  @override
  String disputeWithBuyer(String handle) {
    return 'Disputa con Comprador: $handle';
  }

  @override
  String disputeWithSeller(String handle) {
    return 'Disputa con Vendedor: $handle';
  }

  @override
  String orderLabel(String orderId) {
    return 'Orden $orderId';
  }

  @override
  String get disputeInitiated => 'Iniciado';

  @override
  String get disputeInProgress => 'En progreso';

  @override
  String get disputeStatusClosed => 'Cerrado';

  @override
  String get disputeLostFundsToBuyer =>
      'El administrador resolvió la disputa a favor del comprador. Los sats fueron liberados al comprador.';

  @override
  String get disputeLostFundsToSeller =>
      'El administrador canceló la orden y devolvió los sats al vendedor. No recibiste los sats.';

  @override
  String get walkthroughSlideOneTitle =>
      'Intercambia Bitcoin libremente — sin KYC';

  @override
  String get walkthroughSlideOneBody =>
      'Mostro es un exchange peer-to-peer que te permite intercambiar Bitcoin por cualquier moneda y método de pago — sin KYC y sin necesidad de dar tus datos a nadie. Está construido sobre Nostr, lo que lo hace resistente a la censura. Nadie puede impedirte operar.';

  @override
  String get walkthroughSlideTwoTitle => 'Privacidad por defecto';

  @override
  String get walkthroughSlideTwoBody =>
      'Mostro genera una nueva identidad en cada intercambio, de modo que tus operaciones no pueden vincularse. También puedes decidir cuánta privacidad quieres:\n• Modo reputación – Permite que otros vean tus operaciones exitosas y tu nivel de confianza.\n• Modo privacidad total – No se construye reputación, pero tu actividad es completamente anónima.\nCambia de modo en cualquier momento desde la pantalla de Cuenta, donde también debes guardar tus palabras secretas — son la única forma de recuperar tu cuenta.';

  @override
  String get walkthroughSlideThreeTitle => 'Seguridad en cada paso';

  @override
  String get walkthroughSlideThreeBody =>
      'Mostro usa Hold Invoices (facturas retenidas): los sats permanecen en la billetera del vendedor hasta el final del intercambio. Esto protege a ambas partes. La aplicación también está diseñada para ser intuitiva y fácil para todo tipo de usuarios.';

  @override
  String get walkthroughSlideFourTitle => 'Chat totalmente cifrado';

  @override
  String get walkthroughSlideFourBody =>
      'Cada operación tiene su propio chat privado, cifrado de extremo a extremo. Solo los dos usuarios involucrados pueden leerlo. En caso de disputa, puedes compartir la clave con un administrador para ayudar a resolver el problema.';

  @override
  String get walkthroughSlideFiveTitle => 'Toma una oferta';

  @override
  String get walkthroughSlideFiveBody =>
      'Explora el libro de órdenes, elige una oferta que te convenga y sigue el flujo de la operación paso a paso. Podrás revisar el perfil del otro usuario, chatear de forma segura y completar la operación con facilidad.';

  @override
  String get walkthroughSlideSixTitle => '¿No encuentras lo que necesitas?';

  @override
  String get walkthroughSlideSixBody =>
      'También puedes crear tu propia oferta y esperar a que alguien la tome. Establece el monto y el método de pago preferido — Mostro se encarga del resto.';

  @override
  String get tabBuyBtc => 'COMPRAR BTC';

  @override
  String get tabSellBtc => 'VENDER BTC';

  @override
  String get filterButtonLabel => 'FILTRAR';

  @override
  String offersCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count ofertas',
      one: '1 oferta',
    );
    return '$_temp0';
  }

  @override
  String get noOrdersAvailable => 'No hay órdenes disponibles';

  @override
  String get justNow => 'Ahora mismo';

  @override
  String minutesAgo(int m) {
    return 'Hace ${m}m';
  }

  @override
  String hoursAgo(int h) {
    return 'Hace ${h}h';
  }

  @override
  String daysAgo(int d) {
    return 'Hace ${d}d';
  }

  @override
  String get creatingNewOrderTitle => 'CREANDO NUEVA ORDEN';

  @override
  String get youWantToBuyBitcoin => 'Quieres comprar Bitcoin';

  @override
  String get youWantToSellBitcoin => 'Quieres vender Bitcoin';

  @override
  String get rangeOrderLabel => 'Orden por rango';

  @override
  String get payLightningInvoiceTitle => 'Pagar Factura Lightning';

  @override
  String get invoiceCopied => 'Factura copiada';

  @override
  String get addInvoiceTitle => 'Agregar Factura';

  @override
  String get submitButtonLabel => 'Enviar';

  @override
  String get orderAlreadyTaken => 'La orden ya fue tomada';

  @override
  String get orderIdCopied => 'ID de orden copiado';

  @override
  String get orderDetailsTitle => 'DETALLES DE LA ORDEN';

  @override
  String get timeRemainingLabel => 'Tiempo restante:';

  @override
  String get fiatSentButtonLabel => 'FIAT ENVIADO';

  @override
  String get disputeButtonLabel => 'DISPUTAR';

  @override
  String get contactButtonLabel => 'CONTACTAR';

  @override
  String get rateButtonLabel => 'VALORAR';

  @override
  String get viewDisputeButtonLabel => 'VER DISPUTA';

  @override
  String get comingSoonMessage => 'Próximamente';

  @override
  String get tradeStatusActive => 'Activo';

  @override
  String get tradeStatusFiatSent => 'Fiat enviado';

  @override
  String get tradeStatusCompleted => 'Completado';

  @override
  String get tradeStatusCancelled => 'Cancelado';

  @override
  String get tradeStatusDisputed => 'En disputa';

  @override
  String get releaseButtonLabel => 'LIBERAR';

  @override
  String get accountScreenTitle => 'Cuenta';

  @override
  String get secretWordsTitle => 'Palabras secretas';

  @override
  String get toRestoreYourAccount => 'Para restaurar tu cuenta';

  @override
  String get privacyCardTitle => 'Privacidad';

  @override
  String get controlPrivacySettings =>
      'Controla tu configuración de privacidad';

  @override
  String get reputationMode => 'Modo Reputación';

  @override
  String get reputationModeSubtitle => 'Privacidad estándar con reputación';

  @override
  String get fullPrivacyMode => 'Modo Privacidad Total';

  @override
  String get fullPrivacyModeSubtitle => 'Anonimato máximo';

  @override
  String get generateNewUserButton => 'Generar nuevo usuario';

  @override
  String get importMostroUserButton => 'Importar usuario de Mostro';

  @override
  String get generateNewUserDialogTitle => '¿Generar nuevo usuario?';

  @override
  String get generateNewUserDialogContent =>
      'Esto creará una identidad completamente nueva. Tus palabras secretas actuales dejarán de funcionar — asegúrate de tenerlas respaldadas antes de continuar.';

  @override
  String get continueButtonLabel => 'Continuar';

  @override
  String get importMnemonicDialogTitle => 'Importar Mnemónico';

  @override
  String get importMnemonicHintText => 'Ingresa tu frase de 12 o 24 palabras…';

  @override
  String get importButtonLabel => 'Importar';

  @override
  String get refreshUserDialogTitle => '¿Actualizar usuario?';

  @override
  String get refreshUserDialogContent =>
      'Esto volverá a obtener tus operaciones y órdenes desde la instancia de Mostro. Úsalo si crees que tus datos están desincronizados o faltan órdenes.';

  @override
  String get hideButtonLabel => 'Ocultar';

  @override
  String get showButtonLabel => 'Mostrar';

  @override
  String get settingsScreenTitle => 'Configuración';

  @override
  String get languageSettingTitle => 'Idioma';

  @override
  String get appearanceSettingTitle => 'Apariencia';

  @override
  String get appearanceDialogTitle => 'Apariencia';

  @override
  String get defaultFiatCurrencyTitle => 'Moneda fiat predeterminada';

  @override
  String get allCurrencies => 'Todas las monedas';

  @override
  String get lightningAddressSettingTitle => 'Dirección Lightning';

  @override
  String get tapToSetSubtitle => 'Toca para configurar';

  @override
  String get nwcWalletSettingTitle => 'Billetera NWC';

  @override
  String get nwcConnectPrompt => 'Conecta tu billetera Lightning mediante NWC';

  @override
  String get relaysSettingTitle => 'Relays';

  @override
  String get manageRelayConnections => 'Administrar conexiones de relay';

  @override
  String get pushNotificationsSettingTitle => 'Notificaciones push';

  @override
  String get manageNotificationPreferences =>
      'Administrar preferencias de notificaciones';

  @override
  String get logReportSettingTitle => 'Informe de registros';

  @override
  String get viewDiagnosticLogs => 'Ver registros de diagnóstico';

  @override
  String get mostroNodeSettingTitle => 'Nodo Mostro';

  @override
  String get themeDark => 'Oscuro';

  @override
  String get themeLight => 'Claro';

  @override
  String get themeSystemDefault => 'Predeterminado del sistema';

  @override
  String get lightningAddressDialogTitle => 'Dirección Lightning';

  @override
  String get lightningAddressHintText => 'usuario@dominio.com';

  @override
  String get invalidLightningAddressFormat =>
      'Debe tener el formato usuario@dominio';

  @override
  String get clearButtonLabel => 'Limpiar';

  @override
  String get saveButtonLabel => 'Guardar';

  @override
  String get connectWalletTitle => 'Conectar billetera';

  @override
  String get scanQrCodeTitle => 'Escanear código QR';

  @override
  String get pasteNwcUri => 'Pegar URI NWC';

  @override
  String get selectLanguageTitle => 'Seleccionar idioma';

  @override
  String get selectCurrencyDialogTitle => 'Seleccionar moneda';

  @override
  String get addRelayDialogTitle => 'Agregar relay';

  @override
  String get addButtonLabel => 'Agregar';

  @override
  String get relayHintText => 'wss://relay.example.com';

  @override
  String get relayErrorMustStartWithWss => 'Debe comenzar con wss://';

  @override
  String get relayErrorUrlTooShort => 'La URL es demasiado corta';

  @override
  String get relayErrorDuplicate => 'El relay ya está en la lista';

  @override
  String nwcConnectedBalance(String balance) {
    return 'NWC — Conectado. Saldo: $balance';
  }

  @override
  String get pasteQrCodeHeading => 'Pegar contenido del código QR';

  @override
  String get pasteButtonLabel => 'Pegar';

  @override
  String get clipboardEmptyError => 'El portapapeles está vacío';

  @override
  String get enterValueError => 'Por favor ingresa un valor';

  @override
  String get pasteOrScanQrCode => 'Pegar o escanear un código QR';

  @override
  String get mostroNodeTitle => 'Nodo Mostro';

  @override
  String get currentNodeLabel => 'Nodo actual';

  @override
  String get trustedBadgeLabel => 'De confianza';

  @override
  String get useDefaultButtonLabel => 'Usar predeterminado';

  @override
  String get confirmButtonLabel => 'Confirmar';

  @override
  String get invalidHexPubkey =>
      'Debe ser una cadena hexadecimal de 64 caracteres';

  @override
  String get notificationsScreenTitle => 'Notificaciones';

  @override
  String get markAllAsReadMenuItem => 'Marcar todo como leído';

  @override
  String get clearAllMenuItem => 'Borrar todo';

  @override
  String get youMustBackUpYourAccount =>
      'Debes hacer una copia de seguridad de tu cuenta';

  @override
  String get tapToViewAndSaveSecretWords =>
      'Toca para ver y guardar tus palabras secretas.';

  @override
  String get noNotifications => 'Sin notificaciones';

  @override
  String get markAsRead => 'Marcar como leído';

  @override
  String get deleteNotificationLabel => 'Eliminar';

  @override
  String get rateScreenHeader => 'VALORAR';

  @override
  String get successfulOrder => 'Orden exitosa';

  @override
  String get submitRatingButton => 'ENVIAR';

  @override
  String get closeRatingButton => 'CERRAR';

  @override
  String get aboutScreenTitle => 'Acerca de';

  @override
  String get mostroTagline => 'Intercambio de Bitcoin peer-to-peer sobre Nostr';

  @override
  String get viewDocumentationButton => 'Ver documentación';

  @override
  String get linkCopiedToClipboard => 'Enlace copiado al portapapeles';

  @override
  String get defaultNodeSection => 'Nodo predeterminado';

  @override
  String get pubkeyLabel => 'Clave pública';

  @override
  String get relaysLabel => 'Relays';

  @override
  String get pubkeyCopiedToClipboard => 'Clave pública copiada al portapapeles';

  @override
  String get footerTagline => 'Código abierto. Sin custodia. Privado.';

  @override
  String get drawerTitle => 'MOSTRO';

  @override
  String get betaBadgeLabel => 'Beta';

  @override
  String get drawerAccountMenuItem => 'Cuenta';

  @override
  String get drawerSettingsMenuItem => 'Configuración';

  @override
  String get drawerAboutMenuItem => 'Acerca de';

  @override
  String get navOrderBook => 'Libro de órdenes';

  @override
  String get navMyTrades => 'Mis operaciones';

  @override
  String get navChat => 'Chat';

  @override
  String get loadingOrders => 'Cargando órdenes…';

  @override
  String get errorLoadingOrders =>
      'No se pudieron cargar las órdenes. Comprueba tu conexión.';

  @override
  String get retry => 'Reintentar';

  @override
  String disableRelayLabel(String url) {
    return 'Desactivar relay $url';
  }

  @override
  String enableRelayLabel(String url) {
    return 'Activar relay $url';
  }

  @override
  String get removeRelayTooltip => 'Eliminar relay';

  @override
  String get relayAddFailed => 'Error al añadir el relay';

  @override
  String get relayRemoveFailed => 'Error al eliminar el relay';

  @override
  String get backupConfirmCheckbox =>
      'He anotado mis palabras y las he guardado de forma segura';

  @override
  String get cancelTradeDialogTitle => '¿Cancelar intercambio?';

  @override
  String get cancelTradeDialogContent =>
      'Se solicita una cancelación cooperativa. La otra parte también debe aceptar para que el intercambio quede cancelado.';

  @override
  String get noButtonLabel => 'No';

  @override
  String get yesCancelButtonLabel => 'Sí, cancelar';

  @override
  String get cancelRequestSent => 'Solicitud de cancelación enviada';

  @override
  String get cancelRequestFailed =>
      'No se pudo cancelar. Por favor, inténtelo de nuevo.';

  @override
  String get fiatSentFailed =>
      'Error al marcar el fiat como enviado. Por favor, inténtelo de nuevo.';

  @override
  String get releaseFailed =>
      'Error al liberar. Por favor, inténtelo de nuevo.';

  @override
  String get orderPillYouAreSelling => 'USTED ESTÁ VENDIENDO';

  @override
  String get orderPillYouAreBuying => 'USTED ESTÁ COMPRANDO';

  @override
  String get orderPillSelling => 'VENDIENDO';

  @override
  String get orderPillBuying => 'COMPRANDO';

  @override
  String get myOrderSellTitle => 'SU ORDEN DE VENTA';

  @override
  String get myOrderBuyTitle => 'SU ORDEN DE COMPRA';

  @override
  String get cancelOrderButton => 'Cancelar orden';

  @override
  String get cancelOrderDialogTitle => 'Cancelar orden';

  @override
  String get cancelOrderDialogContent =>
      '¿Está seguro de que desea cancelar esta orden? Esta acción no se puede deshacer.';

  @override
  String get cancelOrderFailed =>
      'No se pudo cancelar la orden. Por favor, inténtelo de nuevo.';

  @override
  String get closeButtonLabel => 'Cerrar';

  @override
  String get copyButtonLabel => 'Copiar';

  @override
  String get orderStatusWaitingForTaker => 'Esperando un tomador';

  @override
  String get orderStatusWaitingBuyerInvoice =>
      'Esperando factura del comprador';

  @override
  String get orderStatusWaitingPayment => 'Esperando pago';

  @override
  String get orderStatusInProgress => 'En progreso';

  @override
  String get orderStatusExpired => 'Expirada';

  @override
  String get copyOrderIdTooltip => 'Copiar ID de orden';

  @override
  String get orderNotFoundTitle => 'Orden no encontrada';

  @override
  String get orderNotFoundMessage => 'Esta orden ya no está disponible.';

  @override
  String get orderCancelledSuccess => 'Orden cancelada exitosamente.';

  @override
  String get aboutAppInfoTitle => 'Información de la aplicación';

  @override
  String get aboutDocumentationTitle => 'Documentación';

  @override
  String get aboutMostroNodeTitle => 'Nodo Mostro';

  @override
  String get aboutVersionLabel => 'Versión';

  @override
  String get aboutGithubRepoLabel => 'Repositorio GitHub';

  @override
  String get aboutCommitHashLabel => 'Hash del commit';

  @override
  String get aboutLicenseLabel => 'Licencia';

  @override
  String get aboutLicenseName => 'MIT';

  @override
  String get aboutGithubRepoName => 'mostro-mobile';

  @override
  String get aboutDocsUsersEnglish => 'Usuarios (Inglés)';

  @override
  String get aboutDocsUsersSpanish => 'Usuarios (Español)';

  @override
  String get aboutDocsTechnical => 'Técnica';

  @override
  String get aboutDocsRead => 'Leer';

  @override
  String get aboutCopiedToClipboard => 'Copiado al portapapeles';

  @override
  String get aboutLicenseDialogTitle => 'Licencia MIT';

  @override
  String get aboutNodeLoadingText => 'Cargando información del nodo…';

  @override
  String get aboutNodeUnavailable => 'Información del nodo no disponible';

  @override
  String get aboutNodeRetry => 'Reintentar';

  @override
  String get aboutGeneralInfoSection => 'Información general';

  @override
  String get aboutTechnicalDetailsSection => 'Detalles técnicos';

  @override
  String get aboutLightningNetworkSection => 'Red Lightning';

  @override
  String get aboutMostroPublicKeyLabel => 'Clave pública de Mostro';

  @override
  String get aboutMaxOrderAmountLabel => 'Monto máximo de orden';

  @override
  String get aboutMinOrderAmountLabel => 'Monto mínimo de orden';

  @override
  String get aboutOrderLifespanLabel => 'Vida útil de la orden';

  @override
  String get aboutServiceFeeLabel => 'Comisión de servicio';

  @override
  String get aboutFiatCurrenciesLabel => 'Monedas fiat';

  @override
  String get aboutMostroVersionLabel => 'Versión de Mostro';

  @override
  String get aboutMostroCommitLabel => 'Commit de Mostro';

  @override
  String get aboutOrderExpirationLabel => 'Vencimiento de la orden';

  @override
  String get aboutHoldInvoiceExpLabel => 'Vencimiento de hold invoice';

  @override
  String get aboutHoldInvoiceCltvLabel => 'CLTV de hold invoice';

  @override
  String get aboutInvoiceExpWindowLabel => 'Ventana de vencimiento de factura';

  @override
  String get aboutProofOfWorkLabel => 'Prueba de trabajo';

  @override
  String get aboutMaxOrdersPerResponseLabel => 'Máx. órdenes por respuesta';

  @override
  String get aboutLndVersionLabel => 'Versión de LND';

  @override
  String get aboutLndNodePublicKeyLabel => 'Clave pública del nodo LND';

  @override
  String get aboutLndCommitLabel => 'Commit de LND';

  @override
  String get aboutLndNodeAliasLabel => 'Alias del nodo LND';

  @override
  String get aboutSupportedChainsLabel => 'Cadenas soportadas';

  @override
  String get aboutSupportedNetworksLabel => 'Redes soportadas';

  @override
  String get aboutLndNodeUriLabel => 'URI del nodo LND';

  @override
  String get aboutSatoshisSuffix => 'Satoshis';

  @override
  String get aboutHoursSuffix => 'horas';

  @override
  String get aboutSecondsSuffix => 'segundos';

  @override
  String get aboutBlocksSuffix => 'bloques';

  @override
  String get aboutFiatCurrenciesAll => 'Todas';

  @override
  String get aboutMostroPublicKeyExplanation =>
      'La clave pública Nostr del daemon Mostro. Todas las órdenes y mensajes cifrados de esta instancia son publicados o enrutados por esta clave.';

  @override
  String get aboutMaxOrderAmountExplanation =>
      'El monto fiat máximo permitido para una sola orden en esta instancia de Mostro.';

  @override
  String get aboutMinOrderAmountExplanation =>
      'El monto fiat mínimo requerido para una sola orden en esta instancia de Mostro.';

  @override
  String get aboutOrderLifespanExplanation =>
      'Cuánto tiempo permanece abierta una orden pendiente antes de que expire automáticamente si no se encuentra un tomador.';

  @override
  String get aboutServiceFeeExplanation =>
      'El porcentaje del monto de la operación que cobra el daemon Mostro como comisión de servicio.';

  @override
  String get aboutFiatCurrenciesExplanation =>
      'Las monedas fiat aceptadas en esta instancia de Mostro. \'Todas\' significa que no hay restricciones.';

  @override
  String get aboutMostroVersionExplanation =>
      'La versión del software del daemon Mostro que ejecuta esta instancia.';

  @override
  String get aboutMostroCommitExplanation =>
      'El hash del commit de Git de la compilación del daemon Mostro, utilizado para identificar la revisión exacta del software.';

  @override
  String get aboutOrderExpirationExplanation =>
      'El tiempo de espera en segundos tras el cual una operación que espera acción (p.ej. factura o pago) se cancela automáticamente.';

  @override
  String get aboutHoldInvoiceExpExplanation =>
      'La ventana de tiempo en segundos durante la cual la hold invoice de Lightning debe liquidarse.';

  @override
  String get aboutHoldInvoiceCltvExplanation =>
      'El delta CLTV (número de bloques) utilizado para las hold invoices, que controla cuánto tiempo puede permanecer bloqueado el HTLC.';

  @override
  String get aboutInvoiceExpWindowExplanation =>
      'La ventana de tiempo en segundos dentro de la cual el comprador debe enviar una factura Lightning después de que se inicia la operación.';

  @override
  String get aboutProofOfWorkExplanation =>
      'La dificultad mínima de prueba de trabajo requerida para los eventos Nostr en esta instancia. 0 significa que no se requiere PoW.';

  @override
  String get aboutMaxOrdersPerResponseExplanation =>
      'El número máximo de órdenes devueltas en una sola respuesta del relay. Limita el uso de ancho de banda.';

  @override
  String get aboutLndVersionExplanation =>
      'La versión del nodo LND (Lightning Network Daemon) conectado a esta instancia de Mostro.';

  @override
  String get aboutLndNodePublicKeyExplanation =>
      'La clave pública del nodo LND. Se utiliza para identificar y verificar el nodo de la Red Lightning.';

  @override
  String get aboutLndCommitExplanation =>
      'El hash del commit de Git de la compilación de LND, que identifica la revisión exacta del software del nodo Lightning.';

  @override
  String get aboutLndNodeAliasExplanation =>
      'El alias legible por humanos del nodo LND configurado por el operador del nodo.';

  @override
  String get aboutSupportedChainsExplanation =>
      'La(s) blockchain(s) soportadas por el nodo LND (p.ej. \'bitcoin\').';

  @override
  String get aboutSupportedNetworksExplanation =>
      'La(s) red(es) en la(s) que opera el nodo LND (p.ej. \'mainnet\', \'testnet\').';

  @override
  String get aboutLndNodeUriExplanation =>
      'El URI de conexión del nodo LND en el formato pubkey@host:puerto. Se utiliza para abrir canales de pago directos.';

  @override
  String get openDisputeFailed =>
      'No se pudo abrir la disputa. Por favor, inténtelo de nuevo.';

  @override
  String get tradeWaitingInvoiceBuyerInstruction =>
      'Envía tu factura Lightning para que el vendedor pueda bloquear los fondos.';

  @override
  String get tradeWaitingInvoiceSellerInstruction =>
      'Esperando a que el comprador envíe su factura Lightning.';

  @override
  String get tradeWaitingPaymentBuyerInstruction =>
      'El vendedor está pagando la factura hold. Por favor, espera.';

  @override
  String get tradeWaitingPaymentSellerInstruction =>
      'Paga la factura hold para bloquear los fondos e iniciar el intercambio.';

  @override
  String get tradeLoadError => 'Ocurrió un error al cargar el intercambio.';

  @override
  String get tradeWaitingForHoldInvoice => 'Esperando la factura hold...';

  @override
  String get payInvoiceScreenTitle => 'Pagar Factura Lightning';

  @override
  String get payInvoiceInstruction =>
      'Paga esta factura hold para iniciar el intercambio.';

  @override
  String get shareButtonLabel => 'Compartir';

  @override
  String get waitingForPaymentConfirmation =>
      'Esperando confirmación de pago...';

  @override
  String get payWithLightningWallet => 'Pagar con wallet Lightning';

  @override
  String get noLightningWalletFound =>
      'No se encontró una wallet Lightning en este dispositivo';

  @override
  String get cancelButtonLabel => 'Cancelar';
}

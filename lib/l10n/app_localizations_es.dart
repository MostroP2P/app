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
  String get actionFailedAnnouncement => 'Acción fallida';

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
  String get bondRequired =>
      'Este nodo requiere un bono anti-abuso, que aún no está soportado';

  @override
  String addInvoiceAmount(String sats) {
    return 'Cantidad a recibir: $sats sats';
  }

  @override
  String payInvoiceAmount(String sats) {
    return 'Cantidad a pagar: $sats sats';
  }

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
  String get viewDisputeButtonLabel => 'Ver disputa';

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
  String get backupRitualSecondFailureMessage =>
      'Eso fue incorrecto de nuevo. Por favor revisa y respalda tus palabras secretas, luego verifica desde el principio.';

  @override
  String get cancelTradeDialogTitle => '¿Cancelar intercambio?';

  @override
  String get cancelTradeDialogContent =>
      'Se solicita una cancelación cooperativa. La otra parte también debe aceptar para que el intercambio quede cancelado.';

  @override
  String get noButtonLabel => 'No';

  @override
  String get yesButtonLabel => 'Sí';

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
  String get cancelTradeButton => 'Cancelar intercambio';

  @override
  String get payHoldInvoiceButton => 'Pagar factura hold';

  @override
  String get openDisputeButton => 'Abrir disputa';

  @override
  String get releaseSatsButton => 'Liberar sats';

  @override
  String get markFiatSentButton => 'Marcar fiat enviado';

  @override
  String get confirmReleaseSatsButton => 'Confirmar y liberar sats';

  @override
  String get shareOrderButton => 'Compartir orden';

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
  String get aboutAntiAbuseBondSection => 'Fianza antiabuso';

  @override
  String get aboutBondEnabledValue => 'Habilitada';

  @override
  String get aboutBondDisabledValue => 'Deshabilitada';

  @override
  String get aboutBondUnsupportedValue => 'No compatible';

  @override
  String get aboutBondStatusLabel => 'Estado de la fianza';

  @override
  String get aboutBondStatusExplanation =>
      'Indica si esta instancia de Mostro exige una fianza antiabuso: una pequeña hold invoice de Lightning que se bloquea mientras dura la operación y se libera cuando esta finaliza con normalidad. \'No compatible\' significa que el daemon es anterior a esta funcionalidad.';

  @override
  String get aboutBondAppliesToLabel => 'Se aplica a';

  @override
  String get aboutBondAppliesToExplanation =>
      'Qué parte de la operación debe bloquear una fianza: quien toma la orden, quien la crea, o ambos.';

  @override
  String get aboutBondAppliesToTakers => 'Quien toma la orden';

  @override
  String get aboutBondAppliesToMakers => 'Quien crea la orden';

  @override
  String get aboutBondAppliesToBoth => 'Ambas partes';

  @override
  String get aboutBondAmountLabel => 'Importe de la fianza';

  @override
  String get aboutBondAmountExplanation =>
      'La fianza como porcentaje del importe de la orden. Se cobra el mayor entre este valor y la fianza mínima.';

  @override
  String get aboutBondBaseAmountLabel => 'Fianza mínima';

  @override
  String get aboutBondBaseAmountExplanation =>
      'El mínimo de una fianza, en satoshis. Se aplica cuando el porcentaje sobre el importe de la orden queda por debajo.';

  @override
  String get aboutBondNodeShareLabel => 'Parte del nodo al confiscar';

  @override
  String get aboutBondNodeShareExplanation =>
      'La parte de una fianza confiscada que retiene el nodo. El resto se envía a la contraparte afectada.';

  @override
  String get aboutBondSlashOnTimeoutLabel => 'Confiscar por tiempo de espera';

  @override
  String get aboutBondSlashOnTimeoutExplanation =>
      'Indica si la fianza se confisca cuando una parte deja vencer un estado de espera en lugar de actuar.';

  @override
  String get aboutBondClaimWindowLabel => 'Plazo para reclamar el pago';

  @override
  String get aboutBondClaimWindowExplanation =>
      'El tiempo que tiene la contraparte afectada para enviar una factura Lightning y reclamar su parte de una fianza confiscada.';

  @override
  String aboutBondClaimWindowValue(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count días',
      one: '$count día',
    );
    return '$_temp0';
  }

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
  String get payInvoiceInstruction =>
      'Paga esta factura hold para iniciar el intercambio.';

  @override
  String get shareButtonLabel => 'Compartir';

  @override
  String get shareFailed => 'No se pudo compartir la factura';

  @override
  String get waitingForPaymentConfirmation =>
      'Esperando confirmación de pago...';

  @override
  String get payWithLightningWallet => 'Pagar con wallet Lightning';

  @override
  String get noLightningWalletFound =>
      'No se encontró una wallet Lightning en este dispositivo';

  @override
  String get orderNoLongerActive => 'Esta orden ya no está activa';

  @override
  String get sessionTimeoutMessage =>
      'No hubo respuesta, verifica tu conexión e inténtalo más tarde';

  @override
  String get noIdentityFoundMessage =>
      'No se encontró ninguna identidad — intenta reiniciar la app.';

  @override
  String get failedToLoadSecretWordsMessage =>
      'No se pudieron cargar las palabras secretas. Inténtalo de nuevo.';

  @override
  String get failedToConfirmBackupMessage =>
      'No se pudo confirmar el respaldo. Inténtalo de nuevo.';

  @override
  String get secretWordsInfoContent =>
      'Tus 12 palabras secretas son la única forma de recuperar tu cuenta. Respáldalas en un lugar seguro — nunca las compartas con nadie.';

  @override
  String get privacyModesInfoTitle => 'Modos de privacidad';

  @override
  String get privacyModesInfoContent =>
      'El modo reputación permite que otros vean tus operaciones exitosas.\n\nEl modo privacidad total mantiene tu actividad completamente anónima — no se construye reputación.';

  @override
  String get failedToGenerateIdentityMessage =>
      'No se pudo generar la identidad. Inténtalo de nuevo.';

  @override
  String get invalidMnemonicMessage =>
      'Mnemónico inválido. Revisa tus palabras e inténtalo de nuevo.';

  @override
  String get enterValidMnemonicError =>
      'Ingresa una frase válida de 12 o 24 palabras.';

  @override
  String get orderBookRefreshedMessage => 'Libro de órdenes actualizado';

  @override
  String get refreshFailedMessage => 'Error al actualizar';

  @override
  String get refreshButtonLabel => 'Actualizar';

  @override
  String get okButtonLabel => 'Aceptar';

  @override
  String get moreInformationTooltip => 'Más información';

  @override
  String get backedUpBadgeLabel => 'Respaldado';

  @override
  String get backupBannerTitle => 'Asegura tu reputación';

  @override
  String get backupBannerSubtitle =>
      'Respalda tus 12 palabras — toma 60 segundos.';

  @override
  String get failedToSaveBackupStatusMessage =>
      'No se pudo guardar el estado del respaldo. Inténtalo de nuevo.';

  @override
  String get backupRitualStep1Title => 'Paso 1 de 3 · Anota tus palabras';

  @override
  String get backupRitualStep2Title => 'Paso 2 de 3 · Verificar';

  @override
  String get backupRitualStep3Title => 'Paso 3 de 3 · Listo';

  @override
  String get backupRitualWarningTitle => 'Anótalas en papel. ';

  @override
  String get backupRitualWarningBody =>
      'No las guardes en fotos, capturas de pantalla ni en la nube — cualquiera con estas 12 palabras puede robar tu reputación.';

  @override
  String get wordsHiddenOnLeaveNote =>
      'Estas palabras se ocultarán cuando salgas de esta pantalla';

  @override
  String get wroteThemDownVerifyButton => 'Las anoté — verificar';

  @override
  String get tapCorrectWordsTitle => 'Toca las palabras correctas';

  @override
  String get verifyInstructionsBody =>
      'Te pedimos 3 al azar. Si las aciertas, sabemos que están bien anotadas.';

  @override
  String optionsForWordLabel(int number) {
    return 'OPCIONES PARA LA PALABRA #$number';
  }

  @override
  String get wrongPickMessage => 'Casi — revisa tu papel e inténtalo de nuevo.';

  @override
  String get allWordsCorrectMessage => '¡Las 3 palabras correctas!';

  @override
  String get showWordsAgainButton => 'Mostrar palabras de nuevo';

  @override
  String get accountBackedUpTitle => 'Tu cuenta está respaldada';

  @override
  String get accountBackedUpBody =>
      'Tu reputación está a salvo. Si alguna vez pierdes tu teléfono, restaura tu cuenta con tus 12 palabras.';

  @override
  String wordNumberLabel(int number) {
    return 'Palabra #$number';
  }

  @override
  String get backupTriggerBody =>
      'Tu reputación vive en una clave que solo tú posees. Si pierdes tu teléfono, pierdes esa reputación — ';

  @override
  String get backupTriggerBodyHighlight => 'respáldala en 60 segundos.';

  @override
  String get backupStepWriteDown => 'Anota tus 12 palabras en papel';

  @override
  String get backupStepVerifyRandom => 'Te pedimos 3 al azar para confirmar';

  @override
  String get backupStepSecured => 'Listo — tu cuenta está protegida';

  @override
  String get backupNowButton => 'Respaldar ahora';

  @override
  String get remindMeTomorrowButton => 'Recuérdamelo mañana';

  @override
  String get nwcConnectionFailedMessage =>
      'La conexión falló. Revisa tu URI de NWC e inténtalo de nuevo.';

  @override
  String get connectWalletDescription =>
      'Conecta tu wallet Lightning usando una\nURI de Nostr Wallet Connect (NWC).';

  @override
  String get nwcUriLabel => 'NWC URI';

  @override
  String get clipboardInvalidNwcUriMessage =>
      'El portapapeles no contiene una URI de NWC válida.';

  @override
  String get scanQrButtonLabel => 'Escanear QR';

  @override
  String get connectButtonLabel => 'Conectar';

  @override
  String get walletConfigurationTitle => 'Configuración de wallet';

  @override
  String get walletDisconnectedMessage => 'Wallet desconectada';

  @override
  String get connectedBadgeLabel => 'Conectada';

  @override
  String get balanceLabel => 'Saldo';

  @override
  String get relayLabel => 'Relay';

  @override
  String get noWalletConnectedTitle => 'No hay wallet conectada';

  @override
  String get connectWalletPrompt =>
      'Conecta una wallet para habilitar pagos Lightning automáticos.';

  @override
  String get disconnectButtonLabel => 'Desconectar';

  @override
  String relaysMoreSuffix(int count) {
    return '(+$count más)';
  }

  @override
  String get chooseNotificationEventsSubtitle =>
      'Elige qué eventos activan las notificaciones push.';

  @override
  String get notifTradeUpdatesTitle => 'Actualizaciones de operaciones';

  @override
  String get notifTradeUpdatesSubtitle =>
      'Cambios de estado en tus operaciones activas';

  @override
  String get notifNewMessagesTitle => 'Nuevos mensajes';

  @override
  String get notifNewMessagesSubtitle => 'Mensajes de tu contraparte';

  @override
  String get notifPaymentAlertsTitle => 'Alertas de pago';

  @override
  String get notifPaymentAlertsSubtitle =>
      'Confirmaciones y fallos de pagos Lightning';

  @override
  String get notifDisputeUpdatesTitle => 'Actualizaciones de disputas';

  @override
  String get notifDisputeUpdatesSubtitle =>
      'Acciones de administradores y resoluciones de disputas';

  @override
  String get searchCurrenciesHint => 'Buscar monedas…';

  @override
  String get noCurrenciesFoundMessage => 'No se encontraron monedas';

  @override
  String get failedToResetNodeMessage => 'No se pudo restablecer el nodo';

  @override
  String get invalidPubkeyOrBridgeErrorMessage =>
      'Clave pública inválida o error del puente';

  @override
  String get currentNodePublicKeyLabel => 'Clave pública del nodo actual';

  @override
  String get useCustomNodePubkeyLabel =>
      'Usar una clave pública de nodo personalizada';

  @override
  String get enterHexPubkeyHint => 'Ingresa clave pública hex de 64 caracteres';

  @override
  String get shareLogsTooltip => 'Compartir registros';

  @override
  String get noLogsToShareTooltip => 'No hay registros para compartir';

  @override
  String get disableLoggingTooltip => 'Desactivar registro';

  @override
  String get enableLoggingTooltip => 'Activar registro';

  @override
  String get loggingEnabledStatus => 'Registro activado';

  @override
  String get loggingDisabledStatus => 'Registro desactivado';

  @override
  String get noLogEntriesMessage => 'No hay entradas de registro';

  @override
  String get failedToShareLogsMessage =>
      'No se pudieron compartir los registros';

  @override
  String get tradeFilterAll => 'Todos';

  @override
  String get tradeFilterPending => 'Pendiente';

  @override
  String get tradeFilterWaitingInvoice => 'Esperando factura';

  @override
  String get tradeFilterWaitingPayment => 'Esperando pago';

  @override
  String get tradeFilterActive => 'Activo';

  @override
  String get tradeFilterFiatSent => 'Fiat enviado';

  @override
  String get tradeFilterSuccess => 'Exitoso';

  @override
  String get tradeFilterCanceled => 'Cancelado';

  @override
  String get tradeFilterDispute => 'Disputa';

  @override
  String get menuTooltip => 'Menú';

  @override
  String get tradeStatusFilterPrefix => 'Estado';

  @override
  String get noTradesTitle => 'Sin operaciones';

  @override
  String get noTradesSubtitle =>
      'Tus operaciones activas y completadas aparecerán aquí.';

  @override
  String get couldNotLoadTradesMessage =>
      'No se pudieron cargar las operaciones';

  @override
  String get releaseBitcoinTitle => 'Liberar Bitcoin';

  @override
  String get releaseBitcoinConfirmation =>
      '¿Seguro que quieres liberar los Satoshis al comprador?';

  @override
  String get sellingBitcoin => 'Vendiendo Bitcoin';

  @override
  String get buyingBitcoin => 'Comprando Bitcoin';

  @override
  String get createdByYou => 'Creada por ti';

  @override
  String get takenByYou => 'Tomada por ti';

  @override
  String get timeAgoNow => 'ahora';

  @override
  String timeAgoMinutes(int count) {
    return '${count}m';
  }

  @override
  String timeAgoHours(int count) {
    return '${count}h';
  }

  @override
  String timeAgoDays(int count) {
    return '${count}d';
  }

  @override
  String get tradeStatusLoading => 'Cargando';

  @override
  String get tradeStatusRate => 'Calificar';

  @override
  String get tradeStatusRated => 'Calificado';

  @override
  String get tradeInstructionActiveBuyer =>
      'Una vez que hayas enviado el dinero, márcalo abajo. Abre una disputa solo si el vendedor deja de responder.';

  @override
  String get tradeInstructionFiatSentBuyer =>
      'Pago fiat marcado como enviado. Esperando que el vendedor confirme la recepción y libere tus sats.';

  @override
  String get tradeInstructionActiveSeller =>
      'Contacta al comprador con las instrucciones de pago a través del chat de arriba.';

  @override
  String get tradeInstructionFiatSentSeller =>
      'El comprador confirmó que envió el pago fiat. Una vez que verifiques la recepción, libera los sats.';

  @override
  String get tradeInstructionDisputed =>
      'Se asignó un resolutor de disputas. Se pondrá en contacto contigo a través de la app.';

  @override
  String get tradeInstructionPendingRating =>
      'La operación se completó con éxito. Califica a tu contraparte para ayudar a construir confianza en la comunidad.';

  @override
  String get tradeInstructionRated => '¡Gracias por tu calificación!';

  @override
  String get tradeInstructionPending =>
      'Tu orden está publicada y esperando a que una contraparte la tome. Puedes cancelarla en cualquier momento.';

  @override
  String get tradeInstructionCancelled =>
      'Esta operación fue cancelada. No se intercambiaron fondos.';

  @override
  String get tradeInstructionInProgress => 'Operación en curso.';

  @override
  String get theAgreedAmount => 'el monto acordado';

  @override
  String get tradeHeadlinePending => 'Esperando a que alguien tome tu orden';

  @override
  String get tradeHeadlineWaitingInvoiceBuyer =>
      'Comparte una factura Lightning para recibir tus sats';

  @override
  String get tradeHeadlineWaitingInvoiceSeller =>
      'Esperando a que el comprador comparta una factura';

  @override
  String get tradeHeadlineWaitingPaymentBuyer =>
      'Esperando a que el vendedor bloquee los sats';

  @override
  String get tradeHeadlineWaitingPaymentSeller =>
      'Paga la hold invoice para bloquear los sats';

  @override
  String tradeHeadlineActiveBuyer(String amount) {
    return 'Envía $amount al vendedor';
  }

  @override
  String tradeHeadlineActiveSeller(String amount) {
    return 'Esperando a que el comprador envíe $amount';
  }

  @override
  String get tradeHeadlineFiatSentBuyer =>
      'Esperando a que el vendedor libere tus sats';

  @override
  String tradeHeadlineFiatSentSeller(String amount) {
    return 'Confirma que recibiste $amount';
  }

  @override
  String get tradeHeadlineDisputed => 'Disputa en curso';

  @override
  String get tradeHeadlineComplete => '¡Operación completada!';

  @override
  String get tradeHeadlineCompleteRated => 'Operación completada';

  @override
  String get tradeHeadlineCancelled => 'Orden cancelada';

  @override
  String get tradeHeadlineLoading => 'Cargando operación…';

  @override
  String get tradeTimerPendingLabel =>
      'Tiempo para que esta orden permanezca en el libro';

  @override
  String get tradeTimerPendingConsequence =>
      'Si expira, la orden se elimina del libro. No afectará tu reputación.';

  @override
  String get tradeTimerWaitingInvoiceLabelBuyer =>
      'Tiempo para compartir tu factura';

  @override
  String get tradeTimerWaitingInvoiceLabelSeller =>
      'Tiempo para que el comprador comparta una factura';

  @override
  String get tradeTimerWaitingInvoiceConsequence =>
      'Si expira, la operación se cancela y la orden vuelve al libro.';

  @override
  String get tradeTimerWaitingPaymentLabelBuyer =>
      'Tiempo para que el vendedor bloquee los sats';

  @override
  String get tradeTimerWaitingPaymentLabelSeller =>
      'Tiempo para pagar la hold invoice';

  @override
  String get tradeTimerActiveLabelBuyer => 'Tiempo para enviar el pago fiat';

  @override
  String get tradeTimerActiveLabelSeller =>
      'Tiempo para que el comprador envíe el fiat';

  @override
  String get tradeTimerActiveConsequence =>
      'Si expira, la operación puede cancelarse. Coordina en el chat si se necesita más tiempo.';

  @override
  String get tradeTimerFiatSentLabelBuyer =>
      'Tiempo para que el vendedor confirme la recepción';

  @override
  String get tradeTimerFiatSentLabelSeller =>
      'Tiempo para confirmar la recepción y liberar';

  @override
  String get tradeTimerFiatSentConsequence =>
      'Si algo parece mal, abre una disputa con el botón de abajo.';

  @override
  String get tradeStepOrderTaken => 'Orden tomada';

  @override
  String get tradeStepInvoiceBuyer =>
      'Compartes una factura · el vendedor bloquea los sats';

  @override
  String get tradeStepInvoiceSeller =>
      'El comprador comparte una factura · tú bloqueas los sats';

  @override
  String get tradeStepFiatBuyer => 'Envías el pago fiat';

  @override
  String get tradeStepFiatSeller => 'El comprador envía el pago fiat';

  @override
  String get tradeStepReleaseBuyer => 'El vendedor confirma y libera tus sats';

  @override
  String get tradeStepReleaseSeller =>
      'Confirmas la recepción y liberas los sats';

  @override
  String get tradeStepRate => 'Califica a tu contraparte';

  @override
  String get activeTradeTitle => 'OPERACIÓN ACTIVA';

  @override
  String tradeIdShortLabel(String id) {
    return 'ID $id';
  }

  @override
  String tradeCreatedAtLabel(String date) {
    return 'creada $date';
  }

  @override
  String get releaseSatsMenuItem => 'Liberar sats';

  @override
  String get cancelOrderMenuItem => 'Cancelar orden';

  @override
  String get openDisputeMenuItem => 'Abrir disputa';

  @override
  String get stepDoneLabel => 'LISTO';

  @override
  String stepIndicator(int current, int total) {
    return 'PASO $current DE $total';
  }

  @override
  String get addLightningInvoiceButton => 'Agregar factura Lightning';

  @override
  String get viewDisputeButton => 'Ver disputa';

  @override
  String get waitingForBuyer => 'Esperando al comprador…';

  @override
  String get waitingForSeller => 'Esperando al vendedor…';

  @override
  String get waitingForFiatPayment => 'Esperando el pago fiat…';

  @override
  String get waitingForCounterpart => 'Esperando una contraparte…';

  @override
  String get yourTradeTimelineTitle => 'TU OPERACIÓN';

  @override
  String get yourCounterpartFallback => 'tu contraparte';

  @override
  String secureChatUnread(int count) {
    return 'Chat seguro · $count nuevos';
  }

  @override
  String get secureChatEncrypted =>
      'Chat seguro · cifrado de extremo a extremo';

  @override
  String get messageSendFailed =>
      'No se pudo enviar el mensaje. Inténtalo de nuevo.';

  @override
  String get invalidTradeId => 'ID de operación inválido';

  @override
  String get selectForDetailsHint => 'Selecciona ℹ o 👤\npara ver detalles';

  @override
  String noMessagesYet(String handle) {
    return 'Aún no hay mensajes.\n¡Saluda a $handle!';
  }

  @override
  String get exchangeInfoTooltip => 'Info del intercambio';

  @override
  String get userInfoTooltip => 'Info del usuario';

  @override
  String chattingWith(String handle) {
    return 'Estás chateando con $handle';
  }

  @override
  String get unknownPeerHandle => 'Desconocido';

  @override
  String get messagesTab => 'Mensajes';

  @override
  String get disputesTab => 'Disputas';

  @override
  String get activeTradeConversations =>
      'Tus conversaciones de operaciones activas';

  @override
  String get noMessagesAvailable => 'No hay mensajes disponibles';

  @override
  String get disputesAndAdminChat => 'Disputas y chat con administradores';

  @override
  String get tradeInformationTitle => 'Información de la operación';

  @override
  String get orderIdLabel => 'ID de orden';

  @override
  String get fiatAmountLabel => 'Monto fiat';

  @override
  String get satsAmountLabel => 'Monto en sats';

  @override
  String get statusLabel => 'Estado';

  @override
  String get paymentMethodLabel => 'Método de pago';

  @override
  String get createdLabel => 'Creada';

  @override
  String get tradeDetailsPlaceholder =>
      'Detalles disponibles cuando el proveedor de operaciones esté listo (Fase 10+)';

  @override
  String get userInformationTitle => 'Información del usuario';

  @override
  String get peerPublicKeyLabel => 'Clave pública del par';

  @override
  String get yourSharedKeyLabel => 'Tu clave compartida';

  @override
  String get sharedKeyPlaceholder =>
      'Disponible tras la integración del puente (Fase 10+)';

  @override
  String get sharedKeySafetyNote =>
      'Guarda tu clave compartida de forma segura — es necesaria para resolver disputas';

  @override
  String get attachmentLabel => '[Adjunto]';

  @override
  String sellingSatsTo(String handle) {
    return 'Le estás vendiendo sats a $handle';
  }

  @override
  String buyingSatsFrom(String handle) {
    return 'Le estás comprando sats a $handle';
  }

  @override
  String youMessagePrefix(String message) {
    return 'Tú: $message';
  }

  @override
  String get downloadTooltip => 'Descargar';

  @override
  String get fileDownloadPlaceholder =>
      'Descarga de archivos disponible en la Fase 10+';

  @override
  String get fileTypeVideo => 'Vídeo';

  @override
  String get fileTypeImage => 'Imagen';

  @override
  String get fileTypeArchive => 'Archivo comprimido';

  @override
  String get fileTypeFile => 'Archivo';

  @override
  String get tapToDownload => 'Toca para descargar';

  @override
  String get imageDownloadPlaceholder =>
      'Descarga de imágenes disponible en la Fase 10+';

  @override
  String buyingSatsAmount(String sats) {
    return 'Comprando $sats sats';
  }

  @override
  String sellingSatsAmount(String sats) {
    return 'Vendiendo $sats sats';
  }

  @override
  String get viewOrderLink => 'Ver orden';

  @override
  String timeLeftLabel(String time) {
    return 'Quedan $time';
  }

  @override
  String get waitingForTradeAmount =>
      'Esperando el monto de la operación — inténtalo de nuevo en un momento.';

  @override
  String get fetchingTradeAmount => 'Obteniendo el monto de la operación…';

  @override
  String get enterInvoiceManually => 'Ingresar factura manualmente';

  @override
  String get enterLightningInvoiceInstruction =>
      'Ingresa una factura Lightning para recibir tus sats';

  @override
  String get lightningInvoiceLabel => 'Factura Lightning';

  @override
  String get submitButton => 'Enviar';

  @override
  String get sellOrderDetailsTitle => 'DETALLES DE ORDEN DE VENTA';

  @override
  String get buyOrderDetailsTitle => 'DETALLES DE ORDEN DE COMPRA';

  @override
  String get buyTheseSatsButton => 'COMPRAR ESTOS SATS';

  @override
  String get sellSatsButton => 'VENDER SATS';

  @override
  String get someoneSellingSats => 'Alguien está vendiendo sats';

  @override
  String get someoneBuyingSats => 'Alguien está comprando sats';

  @override
  String get takeOrderForPrefix => 'por ';

  @override
  String get takeOrderAtMarketPrice => ' a precio de mercado';

  @override
  String premiumLabel(String premium) {
    return 'Prima: $premium%';
  }

  @override
  String get creatorReputation => 'Reputación del creador';

  @override
  String get ratingStatLabel => 'calificación';

  @override
  String get tradesStatLabel => 'operaciones';

  @override
  String get daysActiveStatLabel => 'días activo';

  @override
  String get timeToTakeOrder => 'TIEMPO PARA TOMAR ESTA ORDEN';

  @override
  String get orderExpiryRemovedNote =>
      'Si expira, la orden se elimina del libro. ';

  @override
  String get orderExpiryNoReputationNote => 'No afectará tu reputación.';

  @override
  String get minHint => 'Mín';

  @override
  String get maxHint => 'Máx';

  @override
  String get fiatAmountHint => 'Monto fiat';

  @override
  String get enterAmountForPreview =>
      'Ingresa un monto para ver una vista previa en vivo.';

  @override
  String get previewLabel => 'VISTA PREVIA';

  @override
  String previewBuyMarket(String amount, String price) {
    return 'Compras BTC por *$amount* a *$price* · activa por *24 h*';
  }

  @override
  String previewSellMarket(String amount, String price) {
    return 'Vendes BTC por *$amount* a *$price* · activa por *24 h*';
  }

  @override
  String previewReceiveFixed(String sats, String amount) {
    return 'Recibes *$sats sats* por *$amount* · activa por *24 h*';
  }

  @override
  String previewSellFixed(String sats, String amount) {
    return 'Vendes *$sats sats* por *$amount* · activa por *24 h*';
  }

  @override
  String get marketPriceLabel => 'precio de mercado';

  @override
  String marketPricePremium(String premium) {
    return 'mercado $premium%';
  }

  @override
  String get priceTypeLabel => 'Tipo de precio';

  @override
  String get priceTypeMarket => 'Mercado';

  @override
  String get priceTypeFixed => 'Fijo';

  @override
  String get priceTypeInfoTooltip => 'Info del tipo de precio';

  @override
  String get premiumSectionLabel => 'Prima';

  @override
  String get amountInSatsHint => 'Monto en sats';

  @override
  String get priceTypesDialogTitle => 'Tipos de precio';

  @override
  String get priceTypesDialogContent =>
      'Precio de mercado: el precio de tu orden sigue la tasa del mercado con un porcentaje de prima/descuento aplicado.\n\nPrecio fijo: estableces un precio exacto en satoshis.';

  @override
  String get startFromPreset => 'EMPEZAR DESDE UN PRESET';

  @override
  String get presetExpressTitle => 'Exprés';

  @override
  String get recommendedTag => 'RECOMENDADO';

  @override
  String get presetConservativeTitle => 'Conservador';

  @override
  String get presetConservativeSubtitle =>
      'Precio de mercado · 0% de prima · eliges monto y métodos';

  @override
  String get presetCustomTitle => 'Personalizado';

  @override
  String get presetCustomSubtitle =>
      'Todos los campos — monto, rango, métodos, prima, precio fijo o de mercado';

  @override
  String expressPresetSubtitle(String details) {
    return 'Igual que tu última orden exitosa — $details';
  }

  @override
  String expressPremiumSuffix(String premium) {
    return '$premium% de prima';
  }

  @override
  String get paymentMethodsLabel => 'Métodos de pago';

  @override
  String get addPaymentMethod => 'Agregar método de pago';

  @override
  String get customPaymentMethodHint => 'Método de pago personalizado...';

  @override
  String get customMethodAppendedNote =>
      'El método personalizado se añadirá a la selección';

  @override
  String get selectPaymentMethodsTitle => 'Selecciona métodos de pago';

  @override
  String amountRangeError(String min, String max) {
    return 'El monto debe estar entre $min y $max';
  }

  @override
  String get enterAmountTitle => 'Ingresa el monto';

  @override
  String minMaxRangeLabel(String min, String max, String currency) {
    return 'Mín: $min – Máx: $max $currency';
  }

  @override
  String get ratingFailed => 'La calificación falló. Inténtalo de nuevo.';

  @override
  String get submitUppercaseButton => 'ENVIAR';

  @override
  String selectStarTooltip(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Seleccionar $count estrellas',
      one: 'Seleccionar 1 estrella',
    );
    return '$_temp0';
  }

  @override
  String get disputeDetailsTitle => 'Detalles de la disputa';

  @override
  String get disputeIdLabel => 'ID de disputa';

  @override
  String disputeReasonLabel(String reason) {
    return 'Motivo: $reason';
  }

  @override
  String get adminLabel => 'Administrador';

  @override
  String get disputeScreenTitle => 'Disputa';

  @override
  String get filtersDialogTitle => 'Filtros';

  @override
  String get resetButton => 'Restablecer';

  @override
  String get currencyLabel => 'Moneda';

  @override
  String get ratingLabel => 'Calificación';

  @override
  String get applyButton => 'Aplicar';

  @override
  String get successLabel => 'Éxito';

  @override
  String get copyButton => 'Copiar';

  @override
  String get shareButton => 'Compartir';

  @override
  String sendSatsToAddress(String sats) {
    return 'Envía $sats sats a:';
  }

  @override
  String get changeButton => 'Cambiar';

  @override
  String get buyLabel => 'Comprar';

  @override
  String get sellLabel => 'Vender';

  @override
  String get unableToOpenNotification =>
      'No se pueden abrir los detalles de la notificación.';

  @override
  String get reasonBestPremium => '⚡ Mejor prima';

  @override
  String get reasonMostReputable => '⭐ Más reputado';

  @override
  String get reasonJustPublished => '🆕 Recién publicada';

  @override
  String get marketPriceCaption => 'Precio de mercado';

  @override
  String orderReputationStats(int trades, int days) {
    return ' · $trades operaciones · $days días';
  }

  @override
  String get hideEarlierEvents => 'Ocultar eventos anteriores';

  @override
  String viewEarlierEvents(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Ver $count eventos anteriores',
      one: 'Ver 1 evento anterior',
    );
    return '$_temp0';
  }

  @override
  String get goToTrade => 'Ir a la operación';

  @override
  String get disputeWord => 'Disputa';

  @override
  String get tradeWord => 'Operación';

  @override
  String get notifFilterAll => 'Todas';

  @override
  String get notifFilterDisputes => 'Disputas';

  @override
  String notifFilterDisputesCount(int count) {
    return 'Disputas · $count';
  }

  @override
  String get notifFilterSystem => 'Sistema';

  @override
  String notifFilterSystemCount(int count) {
    return 'Sistema · $count';
  }

  @override
  String get payingStatus => 'Pagando...';

  @override
  String get payWithWalletButton => 'Pagar con wallet';

  @override
  String get generatingInvoiceNwc => 'Generando factura vía NWC...';

  @override
  String get unableToGenerateInvoice =>
      'No se pudo generar la factura automáticamente';

  @override
  String get avatarIconLabel => 'Icono de avatar';

  @override
  String marketPricePremiumLabel(String premium) {
    return 'Precio de mercado ($premium%)';
  }

  @override
  String get disputeDescResolvedBuyerFavour =>
      'Disputa resuelta a favor del comprador';

  @override
  String get disputeDescResolvedYourFavour => 'Disputa resuelta a tu favor';

  @override
  String get disputeDescResolvedSellerFavour =>
      'Disputa resuelta a favor del vendedor';

  @override
  String get disputeDescCooperativeCancel => 'Orden cancelada cooperativamente';

  @override
  String get disputeDescResolved => 'Disputa resuelta';

  @override
  String get disputeDescYouOpened => 'Abriste esta disputa';

  @override
  String get disputeDescCounterpartOpened =>
      'La contraparte abrió esta disputa';

  @override
  String get notificationsBellNoUnread =>
      'Notificaciones, sin notificaciones sin leer';

  @override
  String get notificationsBellBackupActive =>
      'Notificaciones, recordatorio de respaldo activo';

  @override
  String notificationsBellUnread(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Notificaciones, $count sin leer',
      one: 'Notificaciones, 1 sin leer',
    );
    return '$_temp0';
  }

  @override
  String drawerBadgeNewCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count nuevos',
      one: '1 nuevo',
    );
    return '$_temp0';
  }

  @override
  String get lightningInvoiceQrLabel => 'Código QR de la factura Lightning';

  @override
  String get bondSlashedTitle => 'Fianza confiscada';

  @override
  String bondSlashedMessageTimeout(String amount, String orderId) {
    return 'Tu fianza antiabuso de $amount sats para la orden $orderId fue confiscada tras agotarse el tiempo de espera. El estado de tu orden no cambió.';
  }

  @override
  String bondSlashedMessageDispute(String amount, String orderId) {
    return 'Tu fianza antiabuso de $amount sats para la orden $orderId fue confiscada tras la resolución de una disputa. El estado de tu orden no cambió.';
  }

  @override
  String get bondSlashedCauseTimeout => 'Tiempo de espera agotado';

  @override
  String get bondSlashedCauseDispute => 'Resolución de disputa';

  @override
  String get bondSlashedDetailOrder => 'Orden';

  @override
  String get bondSlashedDetailAmount => 'Monto de la fianza';

  @override
  String get bondSlashedDetailCause => 'Motivo';

  @override
  String get bondSlashedDetailFiat => 'Fiat';

  @override
  String get bondSlashedDetailPaymentMethod => 'Método de pago';
}

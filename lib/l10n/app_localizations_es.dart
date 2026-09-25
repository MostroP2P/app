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
  String get tabBuyBtc => 'Comprar BTC';

  @override
  String get tabSellBtc => 'Vender BTC';

  @override
  String get filterButtonLabel => 'Filtrar';

  @override
  String filtersActiveCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count filtros activos',
      one: '1 filtro activo',
    );
    return '$_temp0';
  }

  @override
  String get noOrdersAvailable => 'No hay órdenes disponibles';

  @override
  String get justNow => 'ahora mismo';

  @override
  String minutesAgo(int m) {
    return 'hace ${m}m';
  }

  @override
  String hoursAgo(int h) {
    return 'hace ${h}h';
  }

  @override
  String daysAgo(int d) {
    return 'hace ${d}d';
  }

  @override
  String get invoiceRejected =>
      'El nodo rechazó esta factura. Revisa su monto y su expiración y agrega una nueva.';

  @override
  String get invoiceCopied => 'Factura copiada';

  @override
  String get submitButtonLabel => 'Enviar';

  @override
  String get orderAlreadyTaken => 'La orden ya fue tomada';

  @override
  String get nodeProtocolUnsupported =>
      'Este nodo Mostro usa una versión del protocolo que esta app no soporta. Elige otro nodo en Ajustes o busca una actualización de la app';

  @override
  String get nodeCapabilitiesUnknown =>
      'Aún se está comprobando qué soporta el nodo Mostro seleccionado. Inténtalo de nuevo en un momento';

  @override
  String get mostroMaintenanceMode =>
      'El nodo Mostro al que estás conectado está en mantenimiento. Inténtalo más tarde o conéctate a otro nodo Mostro desde Ajustes';

  @override
  String get storageUnavailable =>
      'La app no puede crear ni tomar órdenes mientras su base de datos local no esté disponible. Reinicia la app e inténtalo de nuevo';

  @override
  String get orderIdCopied => 'ID de orden copiado';

  @override
  String get comingSoonMessage => 'Próximamente';

  @override
  String get tradeStatusActive => 'Activo';

  @override
  String get tradeStatusCompleted => 'Completado';

  @override
  String get tradeStatusCancelled => 'Cancelado';

  @override
  String get tradeStatusDisputed => 'En disputa';

  @override
  String get accountScreenTitle => 'Cuenta';

  @override
  String get secretWordsTitle => 'Palabras secretas';

  @override
  String get privacyCardTitle => 'Privacidad';

  @override
  String get reputationMode => 'Modo Reputación';

  @override
  String get reputationModeSubtitle =>
      'Tus operaciones suman a tu reputación pública';

  @override
  String get fullPrivacyMode => 'Modo Privacidad Total';

  @override
  String get fullPrivacyModeSubtitle =>
      'Cada operación usa una identidad nueva, sin reputación';

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
  String get importMnemonicDialogTitle => 'Importar palabras secretas';

  @override
  String get importMnemonicHintText => 'Ingresa tus 12 palabras secretas';

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
  String get showWordsButton => 'Mostrar palabras';

  @override
  String get settingsScreenTitle => 'Configuración';

  @override
  String get languageSettingTitle => 'Idioma';

  @override
  String get appearanceSettingTitle => 'Apariencia';

  @override
  String get appearanceDialogTitle => 'Apariencia';

  @override
  String get allCurrencies => 'Todas las monedas';

  @override
  String get lightningAddressSettingTitle => 'Dirección Lightning';

  @override
  String get nwcWalletSettingTitle => 'Billetera NWC';

  @override
  String get relaysSettingTitle => 'Relays';

  @override
  String get pushNotificationsSettingTitle => 'Notificaciones push';

  @override
  String get logReportSettingTitle => 'Informe de registros';

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
  String get scanQrCodeTitle => 'Escanear código QR';

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
  String get pasteQrCodeHeading => 'Pegar contenido del código QR';

  @override
  String get pasteButtonLabel => 'Pegar';

  @override
  String get clipboardEmptyError => 'El portapapeles está vacío';

  @override
  String get enterValueError => 'Por favor ingresa un valor';

  @override
  String get trustedBadgeLabel => 'De confianza';

  @override
  String get confirmButtonLabel => 'Confirmar';

  @override
  String get selectMostroNode => 'Elegir nodo';

  @override
  String get addCustomNode => 'Agregar nodo propio';

  @override
  String get nodePubkeyFieldLabel => 'Clave pública';

  @override
  String get nodePubkeyFieldHint => 'Hex de 64 caracteres o npub…';

  @override
  String get nodeNameOptionalLabel => 'Nombre (opcional)';

  @override
  String get invalidPubkeyFormat =>
      'Ingresa una clave pública válida (hex de 64 caracteres o npub)';

  @override
  String get privateKeyNotAllowed =>
      'Eso es una clave privada — nunca la compartas. Ingresa la clave pública del nodo';

  @override
  String get nodeAlreadyExists => 'Este nodo ya está en la lista';

  @override
  String get nodeAddedSuccess => 'Nodo agregado';

  @override
  String nodeSwitchedSuccess(String nodeName) {
    return 'Ahora usas $nodeName';
  }

  @override
  String get errorSwitchingNode => 'No se pudo cambiar de nodo';

  @override
  String get cannotRemoveActiveNode =>
      'El nodo activo no se puede eliminar — cambia primero a otro nodo';

  @override
  String get deleteCustomNodeTitle => 'Eliminar nodo';

  @override
  String get deleteCustomNodeMessage =>
      '¿Eliminar este nodo personalizado de tu lista?';

  @override
  String get deleteCustomNodeConfirm => 'Eliminar';

  @override
  String get nodeRemovedSuccess => 'Nodo eliminado';

  @override
  String get nodeStorageUnavailable =>
      'La base de datos local no está lista. Reinicia la app e inténtalo de nuevo';

  @override
  String nodeSelectorSubtitle(String code) {
    return 'Órdenes y monedas de $code, tu moneda';
  }

  @override
  String get nodeSelectorSubtitleNoCurrency => 'Órdenes abiertas en cada nodo';

  @override
  String nodeMissingCurrencyChip(String code) {
    return 'SIN $code';
  }

  @override
  String get nodeOrdersNowLabel => 'órdenes ahora';

  @override
  String get nodeNoOrdersLabel => 'sin órdenes';

  @override
  String nodeOrdersInCurrency(int count, String code) {
    return '· $count en $code';
  }

  @override
  String get nodeFeeLabel => 'comisión';

  @override
  String get nodeFeeTooltip =>
      'Mostro reparte la comisión entre las dos partes.';

  @override
  String get nodePerTradeLabel => 'por operación';

  @override
  String get nodeCustodyLightning => 'Custodia Lightning';

  @override
  String nodeCustodyCashu(String mint) {
    return 'Custodia Cashu · $mint';
  }

  @override
  String get nodeCustodyUnknown => 'Custodia —';

  @override
  String nodeBondPct(String pct) {
    return 'Bond $pct%';
  }

  @override
  String get nodeBondNone => 'Sin bond';

  @override
  String nodeStatusOnline(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count órdenes',
      one: '1 orden',
    );
    return 'En línea · $_temp0';
  }

  @override
  String get nodeStatusNoUsefulOrders => 'Sin órdenes en tus monedas';

  @override
  String nodeStatusUnreachable(String ago) {
    return 'No responde · última señal $ago';
  }

  @override
  String get nodeStatusUnreachableNoSignal => 'No responde';

  @override
  String get nodeDisclaimerShort =>
      'Cada nodo lo opera un tercero independiente. Mostro no responde por su conducta ni por tus operaciones.';

  @override
  String get nodeVerifyKeyWarning =>
      'Verifica la clave con el operador. Un nodo falso puede ver tus órdenes.';

  @override
  String get nodeInvalidPubkeyShort => 'Esta no es una clave pública válida.';

  @override
  String get nodeNameFieldHint => 'Mostro local';

  @override
  String get nodePubkeyCopied => 'Clave copiada';

  @override
  String get nodeNotSelectableOffline => 'Este nodo no responde';

  @override
  String get nodeStatsLoading => 'Cargando datos del nodo';

  @override
  String get nodeSwitchConfirmTitle => '¿Cambiar de nodo?';

  @override
  String nodeSwitchConfirmBody(String currentNode, String newNode) {
    return 'Tienes una operación en curso en $currentNode. Sigue ahí; el libro pasará a mostrar $newNode.';
  }

  @override
  String get nodeSwitchConfirmAction => 'Cambiar de nodo';

  @override
  String get nodeTradesCheckFailed =>
      'No se pudieron consultar tus operaciones. Inténtalo de nuevo.';

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
  String get closeRatingButton => 'CERRAR';

  @override
  String get aboutScreenTitle => 'Acerca de';

  @override
  String get linkCopiedToClipboard => 'Enlace copiado al portapapeles';

  @override
  String get pubkeyLabel => 'Clave pública';

  @override
  String get relaysLabel => 'Relays';

  @override
  String get footerTagline => 'Código abierto. Sin custodia. Privado.';

  @override
  String get drawerTitle => 'Mostro';

  @override
  String get drawerTagline => 'Intercambio P2P';

  @override
  String get drawerStageBadge => 'Alfa';

  @override
  String drawerVersion(String version) {
    return 'Versión $version';
  }

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
  String get backupRitualSecondFailureMessage =>
      'Eso fue incorrecto de nuevo. Por favor revisa y respalda tus palabras secretas, luego verifica desde el principio.';

  @override
  String get cancelTradeDialogTitle => '¿Cancelar intercambio?';

  @override
  String get cancelTradeDialogContent =>
      'Se solicita una cancelación cooperativa. La otra parte también debe aceptar para que el intercambio quede cancelado.';

  @override
  String get cancelTradeDialogContentNotStarted =>
      'El intercambio aún no ha comenzado, así que se cancela de inmediato. No hace falta que la otra parte lo acepte.';

  @override
  String get cancelTradeDialogContentMaybeStarted =>
      'Si el intercambio aún no ha comenzado, se cancela de inmediato. Si ya comenzó, la otra parte también debe aceptar.';

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
  String get tradeCardCancelRequestedByMeTitle => 'Cancelación solicitada';

  @override
  String get tradeCardCancelRequestedByMeMessage =>
      'Pediste cancelar este intercambio. Sigue abierto hasta que la otra parte también cancele. Si no responde, puedes abrir una disputa.';

  @override
  String get tradeCardCancelRequestedByPeerTitle =>
      'La otra parte quiere cancelar';

  @override
  String get tradeCardCancelRequestedByPeerMessage =>
      'Pidió cancelar este intercambio. Acepta para terminarlo sin mover fondos, o sigue con el intercambio.';

  @override
  String get tradeCancelRequestedByMeNotice =>
      'Pediste cancelar este intercambio. Sigue abierto hasta que la otra parte también cancele. Si no responde, puedes abrir una disputa.';

  @override
  String get tradeCancelRequestedByPeerNotice =>
      'La otra parte pidió cancelar este intercambio. Acepta para terminarlo sin mover fondos, o sigue con el intercambio.';

  @override
  String get acceptCancelButton => 'Aceptar cancelación';

  @override
  String get cancelTradeDialogContentAccept =>
      'La otra parte pidió cancelar. Si cancelas ahora, el intercambio termina para ambos y no se mueven fondos.';

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
  String get confirmReleaseSatsButton => 'Confirmar y liberar sats';

  @override
  String get shareOrderButton => 'Compartir orden';

  @override
  String get orderPillYouAreSelling => 'ESTÁS VENDIENDO';

  @override
  String get orderPillYouAreBuying => 'ESTÁS COMPRANDO';

  @override
  String get myOrderSellTitle => 'Tu orden de venta';

  @override
  String get myOrderBuyTitle => 'Tu orden de compra';

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
  String get aboutDocumentationTitle => 'Documentación';

  @override
  String get aboutMostroNodeTitle => 'Nodo Mostro';

  @override
  String get aboutVersionLabel => 'Versión';

  @override
  String get aboutCommitHashLabel => 'Hash del commit';

  @override
  String get aboutLicenseLabel => 'Licencia';

  @override
  String get aboutLicenseName => 'AGPLv3+';

  @override
  String get aboutGithubRepoName => 'MostroP2P/app';

  @override
  String get aboutCopiedToClipboard => 'Copiado al portapapeles';

  @override
  String get aboutLicenseDialogTitle =>
      'Licencia Pública General Affero de GNU v3';

  @override
  String get aboutNodeLoadingText => 'Cargando información del nodo…';

  @override
  String get aboutNodeUnavailable => 'Información del nodo no disponible';

  @override
  String get aboutNodeRetry => 'Reintentar';

  @override
  String get aboutLightningNetworkSection => 'Red Lightning';

  @override
  String get aboutFiatCurrenciesLabel => 'Monedas fiat';

  @override
  String get aboutMostroVersionLabel => 'Versión de Mostro';

  @override
  String get aboutMostroCommitLabel => 'Commit de Mostro';

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
  String get aboutSupportedChainsLabel => 'Cadenas soportadas';

  @override
  String get aboutSupportedNetworksLabel => 'Redes soportadas';

  @override
  String get aboutSatoshisSuffix => 'Satoshis';

  @override
  String get aboutBlocksSuffix => 'bloques';

  @override
  String get aboutFiatCurrenciesAll => 'Todas';

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
  String get aboutBondAppliesToLabel => 'Se aplica a';

  @override
  String get aboutBondAppliesToTakers => 'Quien toma la orden';

  @override
  String get aboutBondAppliesToMakers => 'Quien crea la orden';

  @override
  String get aboutBondAppliesToBoth => 'Ambas partes';

  @override
  String get aboutBondAmountLabel => 'Importe de la fianza';

  @override
  String get aboutBondBaseAmountLabel => 'Fianza mínima';

  @override
  String get aboutBondNodeShareLabel => 'Parte del nodo al confiscar';

  @override
  String get aboutBondSlashOnTimeoutLabel => 'Confiscar por tiempo de espera';

  @override
  String get aboutBondClaimWindowLabel => 'Plazo para reclamar el pago';

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
  String get openDisputeTitle => 'Abrir disputa';

  @override
  String get openDisputeConfirmation =>
      '¿Seguro que quieres abrir una disputa? Esto escala la operación a un administrador y no se puede deshacer.';

  @override
  String get disputeAlreadyOpen =>
      'Ya hay una disputa abierta para este intercambio.';

  @override
  String get tradeNotDisputable =>
      'Solo se puede abrir una disputa cuando los fondos ya están bloqueados para este intercambio.';

  @override
  String get tradeWaitingInvoiceBuyerInstruction =>
      'Envía tu factura Lightning para que el vendedor pueda bloquear los fondos.';

  @override
  String get tradeWaitingInvoiceSellerInstruction =>
      'Esperando a que el comprador envíe su factura Lightning.';

  @override
  String get tradeWaitingPaymentSellerInstruction =>
      'Paga la factura hold para bloquear los fondos e iniciar el intercambio.';

  @override
  String get tradeLoadError => 'Ocurrió un error al cargar el intercambio.';

  @override
  String get tradeWaitingForHoldInvoice => 'Esperando la factura hold...';

  @override
  String get shareButtonLabel => 'Compartir';

  @override
  String get shareFailed => 'No se pudo compartir la factura';

  @override
  String get waitingForPaymentConfirmation =>
      'Esperando confirmación de pago...';

  @override
  String get orderNoLongerActive => 'Esta orden ya no está activa';

  @override
  String get tradeNoLongerYours => 'Ya no participas en este intercambio';

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
  String get privacyModesInfoTitle => 'Modos de privacidad';

  @override
  String get privacyModesInfoContent =>
      'El modo reputación permite que otros vean tus operaciones exitosas.\n\nEl modo privacidad total mantiene tu actividad completamente anónima — no se construye reputación.';

  @override
  String get failedToGenerateIdentityMessage =>
      'No se pudo generar la identidad. Inténtalo de nuevo.';

  @override
  String get invalidMnemonicMessage =>
      'Palabras secretas inválidas. Revisa tus palabras e inténtalo de nuevo.';

  @override
  String get enterValidMnemonicError => 'Ingresa tus 12 palabras secretas.';

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
  String get backedUpBadgeLabel => 'Respaldadas';

  @override
  String get backupBannerTitle => 'Asegura tu reputación';

  @override
  String get backupBannerSubtitle =>
      'Respalda tus 12 palabras — toma 60 segundos.';

  @override
  String get pendingWipeBannerTitle =>
      'Los datos del usuario anterior siguen en este dispositivo';

  @override
  String get pendingWipeBannerBody =>
      'Al eliminar la identidad anterior no se pudieron borrar sus intercambios y chats de este dispositivo. La app lo reintentará la próxima vez que se genere un nuevo usuario.';

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
      'No las guardes en fotos, capturas ni en la nube — cualquiera con estas 12 palabras puede robar tu reputación.';

  @override
  String get wordsHiddenOnLeaveNote =>
      'Se ocultarán cuando salgas de esta pantalla';

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
  String get allWordsCorrectMessage => 'Las 3 palabras correctas';

  @override
  String get reviewWordsButton => 'Ver palabras';

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
  String get backupLaterButton => 'Lo haré luego';

  @override
  String get nwcConnectionFailedMessage =>
      'La conexión falló. Revisa tu URI de NWC e inténtalo de nuevo.';

  @override
  String get clipboardInvalidNwcUriMessage =>
      'El portapapeles no contiene una URI de NWC válida.';

  @override
  String get scanQrButtonLabel => 'Escanear QR';

  @override
  String get connectButtonLabel => 'Conectar';

  @override
  String get walletDisconnectedMessage => 'Wallet desconectada';

  @override
  String get relayLabel => 'Relay';

  @override
  String get disconnectButtonLabel => 'Desconectar';

  @override
  String relaysMoreSuffix(int count) {
    return '(+$count más)';
  }

  @override
  String get chooseNotificationEventsSubtitle =>
      'Elige qué eventos muestran una notificación en la app.';

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
  String get shareLogsTooltip => 'Compartir registros';

  @override
  String get noLogsToShareTooltip => 'No hay registros para compartir';

  @override
  String get noLogEntriesMessage => 'No hay entradas de registro';

  @override
  String get failedToShareLogsMessage =>
      'No se pudieron compartir los registros';

  @override
  String get logReportShareHeading => 'Informe de registros de Mostro';

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
  String get noTradesTitle => 'Sin operaciones';

  @override
  String get noTradesSubtitle =>
      'Tus operaciones activas y completadas aparecerán aquí.';

  @override
  String get couldNotLoadTradesMessage =>
      'No se pudieron cargar las operaciones';

  @override
  String get sellingBitcoin => 'Vendiendo Bitcoin';

  @override
  String get buyingBitcoin => 'Comprando Bitcoin';

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
  String get tradeHeadlineInProgress => 'Se está preparando el intercambio';

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
  String get tradeHeadlineCancelled => 'Orden cancelada';

  @override
  String get tradeHeadlineLoading => 'Cargando operación…';

  @override
  String get tradeTimerPendingConsequence =>
      'Si expira, la orden se elimina del libro. No afectará tu reputación.';

  @override
  String get tradeTimerWaitingInvoiceConsequence =>
      'Si expira, la operación se cancela y la orden vuelve al libro.';

  @override
  String get tradeStepOrderTaken => 'Orden tomada';

  @override
  String get tradeStepInvoiceBuyer => 'El vendedor bloquea los sats';

  @override
  String get tradeStepInvoiceSeller => 'Bloqueas los sats';

  @override
  String get tradeStepFiatBuyer => 'Envías el pago fiat';

  @override
  String get tradeStepFiatSeller => 'El comprador envía el pago fiat';

  @override
  String get tradeStepReleaseBuyer => 'El vendedor libera tus sats';

  @override
  String get tradeStepReleaseSeller => 'Confirmas y liberas los sats';

  @override
  String get tradeStepRate => 'Califican la operación';

  @override
  String tradeCreatedAtLabel(String date) {
    return 'creada $date';
  }

  @override
  String stepIndicator(int current, int total) {
    return 'PASO $current DE $total';
  }

  @override
  String get addLightningInvoiceButton => 'Agregar factura Lightning';

  @override
  String get viewDisputeButton => 'Ver disputa';

  @override
  String get yourTradeTimelineTitle => 'TU OPERACIÓN';

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
  String get invoiceNoLongerExpected =>
      'Esta orden ya no espera una factura. Actualizando su estado…';

  @override
  String get invoiceSubmitInFlight =>
      'Ya se está enviando una factura para esta orden. Espera la respuesta.';

  @override
  String get waitingForTradeAmount =>
      'Esperando el monto de la operación — inténtalo de nuevo en un momento.';

  @override
  String get fetchingTradeAmount => 'Obteniendo el monto de la operación…';

  @override
  String get enterInvoiceManually => 'Ingresar factura manualmente';

  @override
  String get submitButton => 'Enviar';

  @override
  String get buyerReputation => 'Reputación del comprador';

  @override
  String get sellerReputation => 'Reputación del vendedor';

  @override
  String get ratingStatLabel => 'calificación';

  @override
  String get tradesStatLabel => 'operaciones';

  @override
  String get daysActiveStatLabel => 'días activo';

  @override
  String timeRemainingLabel(String time) {
    return 'Tiempo restante: $time';
  }

  @override
  String orderAmountOutOfRange(int min, int max) {
    return 'El monto debe estar entre $min y $max sats para este nodo Mostro';
  }

  @override
  String orderAmountOutOfRangeFiat(int min, int max, String currency) {
    return 'El monto debe estar entre $min y $max $currency para este nodo Mostro';
  }

  @override
  String get priceTypeMarket => 'Mercado';

  @override
  String get priceTypeFixed => 'Fijo';

  @override
  String get priceTypeInfoTooltip => 'Info del tipo de precio';

  @override
  String get premiumSectionLabel => 'Prima';

  @override
  String get fixedPriceRangeNotAvailable =>
      'El precio fijo no está disponible para órdenes por rango. Desactiva el rango para usar un precio fijo.';

  @override
  String get priceTypesDialogTitle => 'Tipos de precio';

  @override
  String get priceTypesDialogContent =>
      'Precio de mercado: el precio de tu orden sigue la tasa del mercado con un porcentaje de prima/descuento aplicado.\n\nPrecio fijo: estableces un precio exacto en satoshis.';

  @override
  String get newOrderTitle => 'Nueva orden';

  @override
  String get amountSectionSell => 'Cuánto vendes';

  @override
  String get amountSectionBuy => 'Cuánto compras';

  @override
  String get amountModeSingle => 'Único';

  @override
  String get amountModeRange => 'Rango';

  @override
  String get amountMinLabel => 'Mínimo';

  @override
  String get amountMaxLabel => 'Máximo';

  @override
  String paymentMethodsChosenCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count elegidos',
      one: '1 elegido',
      zero: 'ninguno elegido',
    );
    return '$_temp0';
  }

  @override
  String get paymentMethodAdd => 'Agregar';

  @override
  String get paymentMethodSearchHint => 'Buscar métodos';

  @override
  String get customPaymentMethodLabel => 'Método de pago personalizado';

  @override
  String get priceSectionTitle => 'Precio';

  @override
  String premiumSellAbove(String premium) {
    return 'Vendes $premium% sobre el precio de mercado';
  }

  @override
  String premiumSellBelow(String premium) {
    return 'Vendes $premium% por debajo del mercado';
  }

  @override
  String premiumBuyBelow(String premium) {
    return 'Pagas $premium% menos que el mercado';
  }

  @override
  String premiumBuyAbove(String premium) {
    return 'Pagas $premium% de más';
  }

  @override
  String get premiumExactMarket => 'Precio de mercado exacto';

  @override
  String get fixedPriceNote =>
      'A precio fijo la orden no sigue al mercado: el monto en sats queda tal cual lo escribes.';

  @override
  String get previewHintNoAmount =>
      'Escribe un monto y verás aquí cómo queda la orden.';

  @override
  String previewSellMarket(String amount, String premium, String active) {
    return 'Vendes BTC por $amount a precio de mercado $premium$active';
  }

  @override
  String previewSellMarketExact(String amount, String active) {
    return 'Vendes BTC por $amount a precio de mercado$active';
  }

  @override
  String previewBuyMarket(String amount, String premium, String active) {
    return 'Compras BTC por $amount a precio de mercado $premium$active';
  }

  @override
  String previewBuyMarketExact(String amount, String active) {
    return 'Compras BTC por $amount a precio de mercado$active';
  }

  @override
  String previewSellFixed(String sats, String amount, String active) {
    return 'Vendes $sats por $amount a precio fijo$active';
  }

  @override
  String previewBuyFixed(String sats, String amount, String active) {
    return 'Compras $sats por $amount a precio fijo$active';
  }

  @override
  String previewActiveSuffix(String hours) {
    return ' · activa $hours';
  }

  @override
  String get publishOrder => 'Publicar orden';

  @override
  String removePaymentMethod(String method) {
    return 'Quitar $method';
  }

  @override
  String get satsUnitLabel => 'sats';

  @override
  String satsAmount(String amount) {
    return '$amount sats';
  }

  @override
  String durationHours(int hours) {
    return '$hours h';
  }

  @override
  String get paymentMethodsLabel => 'Métodos de pago';

  @override
  String get customPaymentMethodHint => 'Método de pago personalizado...';

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
  String get unableToOpenNotification =>
      'No se pueden abrir los detalles de la notificación.';

  @override
  String get reasonBestPremium => 'Mejor prima';

  @override
  String get reasonMostReputable => 'Mejor reputado';

  @override
  String get marketPriceCaption => 'Precio de mercado';

  @override
  String reputationTradesLabel(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'operaciones',
      one: 'operación',
    );
    return '$_temp0';
  }

  @override
  String reputationDaysLabel(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'días',
      one: 'día',
    );
    return '$_temp0';
  }

  @override
  String get sortNewest => 'Más recientes';

  @override
  String ordersCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count órdenes',
      one: '1 orden',
    );
    return '$_temp0';
  }

  @override
  String get sortBestPremium => 'Mejor prima';

  @override
  String get sortBestReputation => 'Mejor reputación';

  @override
  String get sortSheetTitle => 'Ordenar por';

  @override
  String get orderCardPremiumCaption => 'prima';

  @override
  String orderFixedAmount(String sats) {
    return 'Monto fijo · por $sats';
  }

  @override
  String get reputationNew => 'Nuevo';

  @override
  String get reputationNoTrades => 'sin operaciones';

  @override
  String get bottomNavBook => 'Libro';

  @override
  String get bottomNavTrades => 'Operaciones';

  @override
  String get fabDismissHint => 'Toca fuera para cerrar';

  @override
  String get addOrderFabLabel => 'Crear orden';

  @override
  String get ordersEmptyHint =>
      'Las órdenes nuevas aparecen aquí en cuanto se publican.';

  @override
  String get ordersEmptyFilteredHint =>
      'Ninguna orden coincide con tus filtros.';

  @override
  String get clearFiltersButton => 'Quitar filtros';

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
  String get bondSlashedViewPolicy => 'Ver política';

  @override
  String get bondSlashedViewTrade => 'Ver operación';

  @override
  String bondSlashedTradeNoticeDispute(String sats) {
    return 'El nodo confiscó tu depósito de $sats sats en esta disputa.';
  }

  @override
  String bondSlashedTradeNoticeTimeout(String sats) {
    return 'El nodo confiscó tu depósito de $sats sats porque un paso venció.';
  }

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

  @override
  String aboutDaysValue(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count días',
      one: '$count día',
    );
    return '$_temp0';
  }

  @override
  String get aboutCashuEscrowSection => 'Custodia Cashu';

  @override
  String get aboutCashuMintUrlLabel => 'Mint';

  @override
  String get aboutCashuMintNotAdvertised => 'No anunciado';

  @override
  String get aboutCashuLocktimeLabel => 'Bloqueo de la custodia';

  @override
  String get aboutCashuSettlementMarginLabel => 'Margen de liquidación';

  @override
  String get escrowModeLightning => 'Lightning';

  @override
  String get escrowModeCashu => 'Cashu';

  @override
  String get escrowModeUnknown => 'No anunciado';

  @override
  String get settingsEscrowOverrideTitle => 'Backend de custodia (desarrollo)';

  @override
  String get settingsEscrowOverrideSubtitle =>
      'Prueba Cashu contra un nodo que aún no lo anuncia. Solo en compilaciones de depuración.';

  @override
  String get settingsForceCashuLabel => 'Forzar custodia Cashu';

  @override
  String get settingsCashuMintOverrideLabel => 'URL de mint alternativa';

  @override
  String get settingsCashuMintOverrideApply => 'Aplicar';

  @override
  String get settingsCashuMintOverrideInvalid =>
      'Esa no es una URL de mint válida. Usa http o https con un host.';

  @override
  String settingsEscrowEffectiveMode(String mode) {
    return 'Backend efectivo: $mode';
  }

  @override
  String settingsEscrowEffectiveMint(String mint) {
    return 'Mint efectivo: $mint';
  }

  @override
  String get settingsEscrowCashuUnavailable =>
      'Cashu no puede funcionar sin un mint: configura uno abajo.';

  @override
  String get tradeStatusPayoutPending => 'Pago pendiente';

  @override
  String get tradeHeadlinePayoutPending => 'Esperando el pago al comprador';

  @override
  String get tradeInstructionPayoutPending =>
      'El vendedor liberó los fondos en custodia. Esperando que se complete el pago Lightning al comprador.';

  @override
  String get tradeScreenTitle => 'Tu operación';

  @override
  String get tradeChipWaiting => 'ESPERANDO';

  @override
  String get tradeChipActive => 'ACTIVA';

  @override
  String get tradeChipYourTurn => 'TE TOCA';

  @override
  String get tradeChipDispute => 'DISPUTA';

  @override
  String get tradeChatLockedNote =>
      'Todavía no hay chat: hasta que la operación esté activa, ninguna de las dos partes sabe quién es la otra.';

  @override
  String get tradeChatEncrypted => 'Chat cifrado de extremo a extremo';

  @override
  String get tradeBodyWaitingPaymentBuyer =>
      'Está pagando la factura hold. Cuando los sats estén bloqueados, te toca pagar el fiat.';

  @override
  String tradeBodyActiveSeller(String method) {
    return 'Pásale tus datos de $method por el chat de arriba.';
  }

  @override
  String tradeBodyActiveBuyer(String method) {
    return 'Por $method, con los datos que te pasó por el chat. Cuando lo hayas enviado, márcalo abajo.';
  }

  @override
  String tradeBodyFiatSentSeller(String method) {
    return 'El comprador marcó el pago como enviado. Revisa tu cuenta de $method antes de liberar.';
  }

  @override
  String get tradeReleaseIrreversible =>
      'Liberar los sats no se puede deshacer.';

  @override
  String get tradeTimerYouHave => 'Te quedan';

  @override
  String get tradeTimerTheyHave => 'Le quedan';

  @override
  String get tradeTimerOrderHas => 'Queda';

  @override
  String get tradeTimerNoteCoordinate =>
      'Si necesitan más tiempo, coordínenlo por el chat antes de que expire.';

  @override
  String get tradeRoleBuyer => 'Comprador';

  @override
  String get tradeRoleSeller => 'Vendedor';

  @override
  String reputationTradesCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count operaciones',
      one: '1 operación',
    );
    return '$_temp0';
  }

  @override
  String reputationDaysOnMostro(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count días en Mostro',
      one: '1 día en Mostro',
    );
    return '$_temp0';
  }

  @override
  String get tradeFiatSentAction => 'Ya envié el pago';

  @override
  String get tradeCloseAction => 'Cerrar';

  @override
  String get tradeSendRatingAction => 'Enviar calificación';

  @override
  String get tradeCompletedTitle => 'Operación completada';

  @override
  String tradeRatedCounterpart(String alias, String score) {
    return 'Calificaste a $alias con $score';
  }

  @override
  String get tradeIdLabel => 'ID';

  @override
  String tradeCreatedTodayLabel(String time) {
    return 'creada hoy $time';
  }

  @override
  String get releaseSheetTitle => '¿Liberar los sats?';

  @override
  String get releaseSheetBody =>
      'No se puede deshacer. Libera solo si el dinero ya está en tu cuenta.';

  @override
  String get releaseSheetConfirm => 'Sí, liberar';

  @override
  String get releaseSheetBack => 'Volver';

  @override
  String get orderSideChipSell => 'Vendes BTC';

  @override
  String get orderSideChipBuy => 'Compras BTC';

  @override
  String orderDetailMarketPremium(String premium) {
    return 'Precio de mercado · $premium de prima';
  }

  @override
  String myOrderWaitingNote(String ago) {
    return 'Publicada $ago. Te avisamos apenas alguien la tome: puedes cerrar esta pantalla.';
  }

  @override
  String get orderStatusTakenWaitingInvoice => 'Tomada · esperando factura';

  @override
  String get orderStatusTakenWaitingPayment => 'Tomada · esperando pago';

  @override
  String get orderDetailCreatedLabel => 'Creada';

  @override
  String get orderDetailIdLabel => 'ID';

  @override
  String paymentMethodsMore(String first, int count) {
    return '$first +$count';
  }

  @override
  String get paymentMethodsSheetTitle => 'Métodos de pago';

  @override
  String get cancelOrderSheetTitle => '¿Cancelar la orden?';

  @override
  String get cancelOrderSheetBody =>
      'Se retira del libro de órdenes y no se puede deshacer.';

  @override
  String get goBackButtonLabel => 'Volver';

  @override
  String get takeOrderYouPay => 'Pagas';

  @override
  String get takeOrderYouReceive => 'Recibes';

  @override
  String get takeOrderYouSend => 'Entregas';

  @override
  String takeOrderSatsFrom(String sats) {
    return 'desde $sats';
  }

  @override
  String takeOrderMarketFooter(String premium) {
    return 'Precio de mercado · $premium de prima. La cifra final se fija al tomarla.';
  }

  @override
  String takeOrderFixedFooterSeller(String sats) {
    return 'Monto fijo · el vendedor pide $sats';
  }

  @override
  String takeOrderFixedFooterBuyer(String sats) {
    return 'Monto fijo · el comprador ofrece $sats';
  }

  @override
  String get counterpartySeller => 'Vendedor';

  @override
  String get counterpartyBuyer => 'Comprador';

  @override
  String counterpartyTrades(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count operaciones',
      one: '$count operación',
    );
    return '$_temp0';
  }

  @override
  String counterpartyDaysOnMostro(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count días en Mostro',
      one: '$count día en Mostro',
    );
    return '$_temp0';
  }

  @override
  String get takeOrderPayWithLabel => 'Pagas con';

  @override
  String get takeOrderPaidWithLabel => 'Te pagan con';

  @override
  String get takeOrderPublishedLabel => 'Publicada';

  @override
  String get takeOrderNoteBuyer =>
      'Al tomarla, el vendedor bloquea los sats en Mostro. Recién pagas cuando estén bloqueados.';

  @override
  String get takeOrderNoteSeller =>
      'Al tomarla, bloqueas los sats en Mostro. El comprador paga después.';

  @override
  String get takeOrderButton => 'Tomar orden';

  @override
  String get takeOrderTaking => 'Tomando…';

  @override
  String get takeOrderUnavailable => 'Ya no está disponible';

  @override
  String get takeOrderClosed => 'Cerrada';

  @override
  String get easterEggWhitepaper =>
      '31 de octubre de 2008: nueve páginas, sin pedirle permiso a nadie. Feliz Halloween.';

  @override
  String get easterEggGenesis =>
      'The Times 03/Jan/2009 Chancellor on brink of second bailout for banks';

  @override
  String get easterEggPizzaDay =>
      '22 de mayo de 2010: 10.000 BTC por dos pizzas. Ojalá estuvieran ricas.';

  @override
  String get settingsGroupApp => 'Aplicación';

  @override
  String get settingsGroupPayments => 'Pagos';

  @override
  String get settingsGroupNetwork => 'Red';

  @override
  String get settingsGroupHelp => 'Ayuda';

  @override
  String get fiatCurrencySettingTitle => 'Moneda fiat';

  @override
  String notificationsEnabledOfTotal(int count, int total) {
    return '$count de $total';
  }

  @override
  String get notificationsAllOff => 'Desactivadas';

  @override
  String get lightningAddressUnset => 'Sin configurar';

  @override
  String get nwcWalletNotConnected => 'Sin conectar';

  @override
  String relaysConnectedOfTotal(int connected, int total) {
    return '$connected de $total conectados';
  }

  @override
  String get relaysSummaryHealthy =>
      'Recibes órdenes y mensajes con normalidad';

  @override
  String get relaysSummaryAtRisk => 'Puedes dejar de ver órdenes nuevas';

  @override
  String get relayStatusConnected => 'Conectado';

  @override
  String get relayStatusOffline => 'Sin conexión';

  @override
  String get addRelayButtonLabel => 'Agregar relay';

  @override
  String get relaysFootnote =>
      'Los relays transportan tus órdenes y mensajes. Con menos de dos conectados puedes dejar de ver órdenes nuevas.';

  @override
  String get lastRelayBlockedMessage =>
      'Mantén al menos un relay activo: sin relays no puedes ver ni publicar órdenes.';

  @override
  String get nwcExplainerTitle => 'Conectar tu billetera';

  @override
  String get nwcExplainerSubtitle => 'Con Nostr Wallet Connect';

  @override
  String get nwcExplainerBody =>
      'Mostro cobrará y pagará las facturas de tus operaciones desde esta billetera, sin que tengas que copiar facturas a mano.';

  @override
  String get nwcUriFieldLabel => 'URI de conexión';

  @override
  String get nwcUriPlaceholder => 'nostr+walletconnect://…';

  @override
  String get nwcStorageFootnote =>
      'La URI se guarda solo en este dispositivo y nunca se publica en Nostr.';

  @override
  String get walletConnectedMessage => 'Billetera conectada';

  @override
  String get nwcConnectedStatus => 'Conectada';

  @override
  String nwcBalanceSats(String sats) {
    return '$sats sats';
  }

  @override
  String get notificationsSystemDenied =>
      'Las notificaciones están desactivadas en el sistema.';

  @override
  String get openSystemSettingsAction => 'Abrir ajustes';

  @override
  String get notificationsPrivacyFootnote =>
      'Las notificaciones no incluyen montos ni contrapartes. Un push pasa por los servidores de Google o de Apple y solo dice que hay algo que ver.';

  @override
  String get pushMasterToggleTitle => 'Notificaciones push';

  @override
  String get pushMasterToggleSubtitle =>
      'Despierta la app cuando llega una actualización de operación o un mensaje. La notificación en sí no lleva nada.';

  @override
  String get pushStatusOff =>
      'Desactivadas: nada registrado en el servidor push';

  @override
  String pushStatusCleanupPending(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Desactivadas — quedan $count registros push por eliminar',
      one: 'Desactivadas — queda 1 registro push por eliminar',
    );
    return '$_temp0';
  }

  @override
  String get pushStatusNoToken => 'Esperando el token push de este dispositivo';

  @override
  String get pushStatusIdle =>
      'Activadas: no hay operaciones abiertas que registrar';

  @override
  String pushStatusRegistered(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Registrado para $count operaciones',
      one: 'Registrado para 1 operación',
    );
    return '$_temp0';
  }

  @override
  String pushStatusLastRegistered(String ago) {
    return 'último registro $ago';
  }

  @override
  String get pushStatusUnreachable => 'Servidor push inaccesible: reintentando';

  @override
  String get pushStatusNodeRefused =>
      'El servidor push no acepta este nodo Mostro';

  @override
  String get pushStatusRateLimited =>
      'Límite de solicitudes push alcanzado: reintentando en breve';

  @override
  String get pushUnsupportedPlatform =>
      'Las notificaciones push no están disponibles en esta plataforma';

  @override
  String get pushToggleSaveFailed =>
      'No se pudieron cambiar las notificaciones push';

  @override
  String get pushNewMessageBody => 'Tienes un mensaje nuevo';

  @override
  String get notificationPrefSaveFailed => 'No se pudo guardar la preferencia';

  @override
  String get logsScreenTitle => 'Registros';

  @override
  String get logFilterAll => 'Todos';

  @override
  String get logFilterRelays => 'Relays';

  @override
  String get logFilterOrders => 'Órdenes';

  @override
  String get logFilterPayments => 'Pagos';

  @override
  String get verboseLoggingTitle => 'Registro detallado';

  @override
  String get verboseLoggingSubtitle => 'Más detalle, más consumo';

  @override
  String get newLogsChipLabel => 'Nuevos registros';

  @override
  String get noLogsForFilter => 'Sin entradas para este filtro';

  @override
  String get aboutAppSection => 'Aplicación';

  @override
  String get aboutSourceCodeLabel => 'Código fuente';

  @override
  String get aboutUserGuideLabel => 'Guía de usuario';

  @override
  String get aboutTechnicalDocsLabel => 'Documentación técnica';

  @override
  String get aboutLanguageSpanish => 'Español';

  @override
  String get aboutLanguageEnglish => 'Inglés';

  @override
  String get aboutConnectedNodeTitle => 'Nodo conectado';

  @override
  String get aboutMinOrderCell => 'Orden mínima';

  @override
  String get aboutMaxOrderCell => 'Orden máxima';

  @override
  String get aboutFeeCell => 'Comisión';

  @override
  String aboutFeeValue(String value) {
    return '$value %';
  }

  @override
  String get aboutLimitsFootnote => 'Límites en satoshis por orden';

  @override
  String get aboutNodeTechnicalDataRow => 'Datos técnicos del nodo';

  @override
  String aboutFieldCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count campos',
      one: '$count campo',
    );
    return '$_temp0';
  }

  @override
  String get aboutTechnicalDataTitle => 'Datos técnicos';

  @override
  String get aboutPublicKeyLabel => 'Clave pública';

  @override
  String get aboutOrderExpiryLabel => 'Expiración de orden';

  @override
  String get aboutWaitingTimeoutLabel => 'Tiempo máx. de espera';

  @override
  String aboutHoursShort(int count) {
    return '$count h';
  }

  @override
  String aboutSecondsShort(int count) {
    return '$count s';
  }

  @override
  String get aboutAliasLabel => 'Alias';

  @override
  String get aboutNodePublicKeyLabel => 'Clave pública del nodo';

  @override
  String get aboutNodeUriLabel => 'URI del nodo';

  @override
  String get aboutCommitLabel => 'Commit';

  @override
  String get aboutChainNetworkLabel => 'Cadena y red';

  @override
  String get aboutTechnicalFootnote =>
      'Estos datos identifican al nodo con el que operas. Útiles para soporte o para verificarlo antes de enviar fondos.';

  @override
  String get aboutCopyAllData => 'Copiar todos los datos';

  @override
  String get tradesGroupNeedsAction => 'Requieren tu acción';

  @override
  String get tradesGroupInProgress => 'En curso';

  @override
  String get tradesGroupClosed => 'Cerradas';

  @override
  String get tradesDirectionSell => 'Vendes';

  @override
  String get tradesDirectionBondClaim => 'Reclamo de depósito';

  @override
  String get tradesDirectionBuy => 'Compras';

  @override
  String tradesCounterpartyTo(String handle) {
    return 'a $handle';
  }

  @override
  String tradesCounterpartyFrom(String handle) {
    return 'a $handle';
  }

  @override
  String get tradeListChipYourTurn => 'Te toca';

  @override
  String get tradeListChipPublished => 'Publicada';

  @override
  String get tradeListChipInProgress => 'En curso';

  @override
  String get tradeListChipWaitingInvoice => 'Esperando factura';

  @override
  String get tradeListChipWaitingPayment => 'Esperando pago';

  @override
  String get tradeListChipWaitingSats => 'Esperando sats';

  @override
  String get tradeListChipDispute => 'En disputa';

  @override
  String get tradeListChipCompleted => 'Completada';

  @override
  String get tradeListChipCancelled => 'Cancelada';

  @override
  String get tradeListChipExpired => 'Expirada';

  @override
  String get tradeVerbAddInvoice => 'Agregar factura';

  @override
  String get tradeVerbPayBond => 'Pagar depósito';

  @override
  String get tradeHeadlineWaitingBond => 'Bloquea tu depósito para continuar';

  @override
  String get tradeInstructionWaitingBond =>
      'El nodo retiene esta toma hasta que pagues el depósito reembolsable. Mientras tanto la orden sigue abierta a otros.';

  @override
  String get takeOrderBondNotice =>
      'Este nodo pide a quien toma la orden bloquear primero un depósito reembolsable; vuelve al terminar la operación de buena fe.';

  @override
  String takeOrderBondNoticeEstimate(String sats) {
    return 'Este nodo pide a quien toma la orden bloquear primero un depósito reembolsable de ≈ $sats sats; vuelve al terminar la operación de buena fe.';
  }

  @override
  String get tradeVerbPayInvoice => 'Pagar factura';

  @override
  String get tradeVerbSendPayment => 'Enviar pago';

  @override
  String get tradeVerbReleaseSats => 'Liberar sats';

  @override
  String get tradeVerbRate => 'Calificar';

  @override
  String get tradeListFilterAll => 'Todas';

  @override
  String get tradeListFilterActive => 'Activas';

  @override
  String get tradeListFilterCompleted => 'Completadas';

  @override
  String get tradeListFilterCancelled => 'Canceladas';

  @override
  String get tradeListFilterTitle => 'Mostrar operaciones';

  @override
  String get relativeTimeNow => 'ahora';

  @override
  String relativeTimeMinutes(int count) {
    return 'hace $count min';
  }

  @override
  String relativeTimeHours(int count) {
    return 'hace $count h';
  }

  @override
  String get relativeTimeYesterday => 'ayer';

  @override
  String satsFigureEstimate(String sats) {
    return '≈ $sats sats';
  }

  @override
  String satsFigureExact(String sats) {
    return '$sats sats';
  }

  @override
  String get chatGroupActive => 'Operaciones activas';

  @override
  String chatContextSellActive(String amount, String currency) {
    return 'Le vendes $amount $currency';
  }

  @override
  String chatContextBuyActive(String amount, String currency) {
    return 'Le compras $amount $currency';
  }

  @override
  String chatContextSellClosed(String amount, String currency) {
    return 'Le vendiste $amount $currency';
  }

  @override
  String chatContextBuyClosed(String amount, String currency) {
    return 'Le compraste $amount $currency';
  }

  @override
  String get chatTurnAddInvoice => 'te toca la factura';

  @override
  String get chatTurnPayBond => 'te toca pagar el depósito';

  @override
  String get chatTurnPayInvoice => 'te toca pagar la factura';

  @override
  String get chatTurnSendPayment => 'te toca pagar';

  @override
  String get chatTurnRelease => 'te toca liberar';

  @override
  String get chatTurnRate => 'te toca calificar';

  @override
  String get chatYouLabel => 'Tú:';

  @override
  String get chatListFootnote =>
      'Cada conversación pertenece a una operación y está cifrada de extremo a extremo. Cuando la operación termina, queda aquí para consulta.';

  @override
  String get chatListEmptyTitle => 'Todavía no tienes conversaciones';

  @override
  String get chatListEmptyBody =>
      'El chat se abre cuando una operación queda activa.';

  @override
  String get chatClosedNotice =>
      'La operación terminó. La conversación queda aquí para consulta.';

  @override
  String disputeOpenedByYou(String time) {
    return 'La abriste $time';
  }

  @override
  String disputeOpenedByPeer(String time) {
    return 'La abrió la contraparte $time';
  }

  @override
  String get invoiceReceiveTitle => 'Recibir tus sats';

  @override
  String get invoiceLockTitle => 'Bloquear tus sats';

  @override
  String get bondTitle => 'Depósito de garantía';

  @override
  String get bondRefundableLabel => 'DEPÓSITO REEMBOLSABLE';

  @override
  String get bondComesBack => 'vuelve a ti al completar';

  @override
  String bondFiatComesBack(String fiat) {
    return '≈ $fiat · vuelve a ti al completar';
  }

  @override
  String bondPaySemantics(String sats) {
    return 'Depósito reembolsable de $sats sats';
  }

  @override
  String bondReleasesIn(String time) {
    return 'La orden se libera si no pagas en $time';
  }

  @override
  String bondRowHeld(String bold) {
    return 'Los sats quedan $bold, no se gastan';
  }

  @override
  String get bondRowHeldBold => 'retenidos en tu billetera';

  @override
  String bondRowReleased(String bold) {
    return 'Si la operación termina bien, $bold';
  }

  @override
  String get bondRowReleasedBold => 'se libera solo';

  @override
  String bondRowLost(String bold) {
    return 'Solo lo pierdes si hay disputa y $bold';
  }

  @override
  String bondRowLostTimeout(String bold) {
    return 'Lo pierdes si dejas vencer un paso, o si hay disputa y $bold';
  }

  @override
  String get bondRowLostBold => 'la pierdes';

  @override
  String get bondWhyTitle => 'Por qué Mostro pide un depósito';

  @override
  String get bondWhyCustody =>
      'Mostro no custodia fondos, así que no puede castigar a quien abandona una operación; el depósito hace ese trabajo, y protege a todos los usuarios contra estafadores.';

  @override
  String bondWhyHold(String hold) {
    return 'Es una factura $hold: la billetera reserva los sats sin enviarlos; al completar, la reserva se cancela sola.';
  }

  @override
  String get bondWhyDispute =>
      'Si abres disputa y ganas, también lo recuperas. Solo se cobra al perder una disputa.';

  @override
  String get bondWhyDisputeTimeout =>
      'Si abres disputa y ganas, también lo recuperas. Solo se cobra al perder una disputa o al dejar vencer un paso.';

  @override
  String get bondReadDocs => 'Leer la documentación';

  @override
  String get bondContextOrder => 'Orden';

  @override
  String bondContextBuy(String fiat) {
    return 'Compras $fiat';
  }

  @override
  String bondContextSell(String fiat) {
    return 'Vendes $fiat';
  }

  @override
  String get bondContextEquals => 'Depósito equivale a';

  @override
  String bondContextPercent(String pct) {
    return '$pct % del monto';
  }

  @override
  String get bondDontPublish => 'No publicar la orden';

  @override
  String get bondAbandoned =>
      'Orden descartada. No se publicó nada ni se cobró nada.';

  @override
  String bondPublishesIn(String time) {
    return 'Aún no publicada: la orden se descarta si no pagas en $time';
  }

  @override
  String get bondInvoiceMissingMaker =>
      'Este dispositivo no tiene copia de la factura del depósito y el nodo no la reenvía para una orden que creaste. Descarta la orden y créala de nuevo.';

  @override
  String get bondExpiredBodyMaker =>
      'No se pagó a tiempo: la orden nunca se publicó y no salió ningún sat de tu wallet.';

  @override
  String get bondExpiredNoticeMaker =>
      'La factura del depósito expiró; la orden no se publicó';

  @override
  String get orderStatusWaitingBond =>
      'Esperando tu depósito — aún no publicada';

  @override
  String get bondCancelNotAllowed =>
      'Esta orden no se puede cancelar mientras su depósito esté pendiente. Descártala desde la pantalla del depósito.';

  @override
  String createOrderBondNoticeEstimate(String sats) {
    return 'Este nodo te pide bloquear un depósito reembolsable de ≈ $sats sats antes de publicar la orden; vuelve al terminar la operación de buena fe.';
  }

  @override
  String get createOrderBondNotice =>
      'Este nodo te pide bloquear un depósito reembolsable antes de publicar la orden; vuelve al terminar la operación de buena fe.';

  @override
  String get bondClaimTitle => 'Reclama tu parte';

  @override
  String get bondClaimShareLabel => 'TU PARTE';

  @override
  String bondClaimShareSemantics(String sats) {
    return 'Parte de $sats sats por reclamar';
  }

  @override
  String bondClaimContext(String context) {
    return 'De la operación de $context';
  }

  @override
  String bondClaimDeadline(String date) {
    return 'Reclama antes del $date';
  }

  @override
  String get bondClaimExplainer =>
      'El depósito de la otra parte se perdió a tu favor. Agrega una factura por exactamente este monto y el nodo te lo paga.';

  @override
  String get bondClaimFieldLabel => 'Factura Lightning';

  @override
  String get bondClaimFieldHint => 'lnbc… por exactamente la parte';

  @override
  String get bondClaimSubmit => 'Enviar factura';

  @override
  String get bondClaimSent => 'Factura enviada al nodo';

  @override
  String get bondClaimSubmittedTitle => 'Factura enviada';

  @override
  String get bondClaimSubmittedBody => 'Esperando a que el nodo la confirme.';

  @override
  String get bondClaimAcknowledgedTitle => 'Pago en curso';

  @override
  String get bondClaimAcknowledgedBody =>
      'El nodo aceptó tu factura y la está pagando. Si no puede enrutarla, te pedirá una nueva.';

  @override
  String get bondClaimCompletedTitle => 'Pagado';

  @override
  String bondClaimCompletedBody(String sats) {
    return '$sats sats llegaron a tu wallet.';
  }

  @override
  String get bondClaimExpiredTitle => 'La ventana para reclamar terminó';

  @override
  String bondClaimExpiredBody(String date) {
    return 'Cerró el $date. La parte ya no se puede reclamar.';
  }

  @override
  String get bondClaimMissing => 'No hay ningún reclamo para esta orden.';

  @override
  String get bondClaimErrorAmount =>
      'La factura debe ser por exactamente la parte indicada.';

  @override
  String get bondClaimErrorExpired =>
      'La ventana para reclamar terminó; la parte ya no se puede reclamar.';

  @override
  String get bondClaimErrorRejected =>
      'El nodo no aceptó la factura. Prueba con otra.';

  @override
  String get bondClaimErrorNotClaimable =>
      'Este reclamo no acepta una factura en este momento.';

  @override
  String get bondClaimErrorNoKey =>
      'Este dispositivo no tiene la clave de esa operación, así que no puede reclamar la parte.';

  @override
  String get tradeVerbClaimPayout => 'Reclamar pago';

  @override
  String get chatTurnClaimPayout => 'te toca reclamar el pago';

  @override
  String get tradeBadgePayoutPending => 'Pago pendiente';

  @override
  String get tradeBadgePayoutInProgress => 'Pago en curso';

  @override
  String get tradeBadgePayoutPaid => 'Pago recibido';

  @override
  String bondBannerPendingTitle(String sats) {
    return '$sats sats están listos para volver a ti';
  }

  @override
  String bondBannerPendingBody(String sats) {
    return 'El depósito de la otra parte se perdió a tu favor. Agrega cualquier factura Lightning por $sats sats para reclamarlo.';
  }

  @override
  String get bondBannerAddInvoice => 'Agregar factura de pago';

  @override
  String get bondBannerView => 'Ver reclamo';

  @override
  String get bondBannerInProgressTitle => 'Pago en curso';

  @override
  String bondBannerInProgressBody(String sats) {
    return 'El nodo está pagando tu parte de $sats sats.';
  }

  @override
  String get bondBannerPaidTitle => 'Pago recibido';

  @override
  String bondBannerPaidBody(String sats, String date) {
    return 'Se te pagaron $sats sats el $date.';
  }

  @override
  String bondBannerExpired(String date) {
    return 'El reclamo sobre el depósito de la otra parte cerró el $date.';
  }

  @override
  String get bondClaimNewTitle => 'Pago de depósito por reclamar';

  @override
  String bondClaimNewMessage(String sats) {
    return 'Puedes reclamar $sats sats de un depósito confiscado. Agrega una factura Lightning para recibirlos.';
  }

  @override
  String get bondClaimPaidTitle => 'Pago de depósito recibido';

  @override
  String bondClaimPaidMessage(String sats) {
    return 'Pago de depósito de $sats sats recibido.';
  }

  @override
  String get bondDontTake => 'No tomar la orden';

  @override
  String get bondLockedNowEscrow =>
      'Depósito bloqueado. Ahora bloquea el monto de la operación.';

  @override
  String get bondLostRace =>
      'Otro usuario tomó esta orden antes de que pagaras el depósito';

  @override
  String get bondMakerCanceled => 'El creador canceló esta orden';

  @override
  String get bondExpiredNotice =>
      'La factura del depósito venció; la orden volvió al libro';

  @override
  String get bondExpiredTitle => 'La factura del depósito venció';

  @override
  String get bondExpiredBody =>
      'No se pagó a tiempo: la orden volvió al libro y ningún sat salió de tu billetera.';

  @override
  String get bondInvoiceMissing =>
      'Este dispositivo no tiene copia de la factura del depósito. Pídesela de nuevo al nodo para seguir tomando la orden.';

  @override
  String get bondRequestAgain => 'Pedir la factura de nuevo';

  @override
  String get bondRequestFailed => 'El nodo no reenvió la factura del depósito';

  @override
  String get invoiceOrderIdCopied => 'ID de la orden copiado';

  @override
  String get invoiceYouReceiveLabel => 'Vas a recibir';

  @override
  String get invoiceToPayLabel => 'A pagar';

  @override
  String invoiceReceiveSemantics(String sats) {
    return '$sats satoshis a recibir';
  }

  @override
  String invoicePaySemantics(String sats) {
    return '$sats satoshis a pagar';
  }

  @override
  String invoiceFeeIncluded(String sats) {
    return 'Incluye $sats sats de comisión de Mostro';
  }

  @override
  String invoiceTimeToSend(String time) {
    return 'Tienes $time para enviarla';
  }

  @override
  String invoiceExpiresIn(String time) {
    return 'La factura vence en $time';
  }

  @override
  String get invoiceFieldLabel => 'Factura o dirección Lightning';

  @override
  String get invoiceFieldHint => 'lnbc… o usuario@dominio';

  @override
  String get invoiceFieldPromptLabel => 'Pega tu factura aquí';

  @override
  String get invoiceFieldFilledLabel => 'Factura Lightning';

  @override
  String get invoiceFieldAddressLabel => 'Dirección Lightning';

  @override
  String get invoiceScanButton => 'Escanear';

  @override
  String get invoiceReplaceButton => 'Reemplazar';

  @override
  String get invoiceFieldSemantics =>
      'Factura o dirección Lightning, requerido';

  @override
  String invoiceFilledSemantics(String sats) {
    return 'Factura Lightning de $sats sats';
  }

  @override
  String get invoiceValidAddress =>
      'Dirección válida · se pedirá la factura al enviar';

  @override
  String invoiceValidInvoice(String sats) {
    return 'Factura válida · $sats sats';
  }

  @override
  String invoiceErrorWrongAmount(String actual, String expected) {
    return 'La factura es por $actual sats, deben ser $expected';
  }

  @override
  String get invoiceErrorExpired => 'La factura ya expiró';

  @override
  String invoiceErrorExpiresTooSoon(String minutes) {
    return 'La factura vence en menos de $minutes minutos, el nodo necesita más tiempo para pagarla';
  }

  @override
  String get invoiceErrorMalformed =>
      'Esta factura está incompleta o mal copiada';

  @override
  String get invoiceErrorUnrecognized =>
      'No es una factura (lnbc…) ni una dirección Lightning (usuario@dominio)';

  @override
  String get invoiceSellerLabel => 'Vendedor';

  @override
  String get invoiceBuyerLabel => 'Comprador';

  @override
  String get invoiceYouPayLabel => 'Pagas';

  @override
  String get invoiceYouGetLabel => 'Recibes';

  @override
  String get invoiceNoTrades => 'sin operaciones';

  @override
  String get invoiceSendButton => 'Enviar factura';

  @override
  String get invoiceCancelTrade => 'Cancelar operación';

  @override
  String get invoiceOpenWallet => 'Abrir en mi billetera';

  @override
  String invoiceHoldNote(String hold) {
    return 'Es una factura $hold: los sats quedan retenidos, no salen de tu billetera hasta que confirmes el pago del comprador.';
  }

  @override
  String invoiceQrSemantics(String invoice) {
    return 'Código QR de la factura Lightning: $invoice';
  }

  @override
  String get invoiceExpiredTitle => 'La factura venció';

  @override
  String get invoiceExpiredBody =>
      'No se pagó a tiempo: Mostro cancela la operación y ningún sat salió de tu billetera.';

  @override
  String get invoiceBackToBook => 'Volver al libro de órdenes';

  @override
  String get invoiceTimeUpTitle => 'Se acabó el tiempo';

  @override
  String get invoiceTimeUpBody =>
      'La factura no se envió a tiempo: Mostro cancela la operación. De tu lado no se comprometió nada.';

  @override
  String invoiceErrorWrongNetwork(String invoice, String node) {
    return 'La factura es de $invoice, el nodo usa $node';
  }

  @override
  String invoiceCountdownHours(String hours, String minutes) {
    return '$hours h $minutes';
  }

  @override
  String get tradeCardWaitingBuyerInvoiceTitle =>
      'Esperando la factura del comprador';

  @override
  String get tradeCardWaitingBuyerInvoiceMessage =>
      'El intercambio continúa cuando el comprador agregue una factura Lightning.';

  @override
  String get tradeCardWaitingPaymentTitle => 'Esperando el pago del vendedor';

  @override
  String get tradeCardWaitingPaymentMessage =>
      'El intercambio continúa cuando el vendedor pague la factura hold.';

  @override
  String get tradeCardWaitingTakerBondTitle => 'Pago de depósito pendiente';

  @override
  String get tradeCardWaitingTakerBondMessage =>
      'El depósito antiabuso del tomador debe pagarse antes de que empiece el intercambio.';

  @override
  String get tradeCardActiveTitle => 'Intercambio activo';

  @override
  String get tradeCardActiveMessage =>
      'Los sats están bloqueados. El comprador ya puede enviar el pago fiat.';

  @override
  String get tradeCardFiatSentTitle => 'Fiat marcado como enviado';

  @override
  String get tradeCardFiatSentMessage =>
      'El comprador marcó el pago fiat como enviado.';

  @override
  String get tradeCardSettledHoldInvoiceTitle => 'Sats liberados';

  @override
  String get tradeCardSettledHoldInvoiceMessage =>
      'El vendedor liberó los sats. El pago al comprador está en camino.';

  @override
  String get tradeCardSuccessTitle => 'Intercambio completado';

  @override
  String get tradeCardSuccessMessage => 'El intercambio terminó con éxito.';

  @override
  String get tradeCardCanceledTitle => 'Intercambio cancelado';

  @override
  String get tradeCardCanceledMessage => 'El intercambio fue cancelado.';

  @override
  String get tradeCardExpiredTitle => 'Orden expirada';

  @override
  String get tradeCardExpiredMessage =>
      'La orden expiró antes de que el intercambio pudiera continuar.';

  @override
  String get tradeCardCooperativelyCanceledTitle =>
      'Intercambio cancelado de mutuo acuerdo';

  @override
  String get tradeCardCooperativelyCanceledMessage =>
      'Ambas partes acordaron cancelar el intercambio.';

  @override
  String get tradeCardDisputeTitle => 'Disputa abierta';

  @override
  String get tradeCardDisputeMessage =>
      'Se abrió una disputa en este intercambio.';

  @override
  String get tradeCardCanceledByAdminTitle => 'Cancelado por el resolutor';

  @override
  String get tradeCardCanceledByAdminMessage =>
      'El resolutor de disputas canceló el intercambio.';

  @override
  String get tradeCardSettledByAdminTitle => 'Resuelto por el resolutor';

  @override
  String get tradeCardSettledByAdminMessage =>
      'El resolutor de disputas liberó los sats al comprador.';

  @override
  String get tradeCardCompletedByAdminTitle => 'Completado por el resolutor';

  @override
  String get tradeCardCompletedByAdminMessage =>
      'El resolutor de disputas completó el intercambio.';

  @override
  String get tradeCardUpdatedTitle => 'Intercambio actualizado';

  @override
  String get tradeCardUpdatedMessage => 'El estado de este intercambio cambió.';

  @override
  String get tradeCardCanceledByMakerMessage => 'El creador canceló la orden.';

  @override
  String get tradeCardCanceledBondLostRaceMessage =>
      'Otro usuario tomó esta orden antes de que se pagara el depósito.';

  @override
  String get tradeCardCanceledBondExpiredMessage =>
      'La factura del depósito expiró sin pagarse.';

  @override
  String get chatCardTitle => 'Mensajes nuevos';

  @override
  String get chatCardSolverTitle => 'Mensajes del resolutor';

  @override
  String chatCardMessage(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count mensajes nuevos de tu contraparte',
      one: '1 mensaje nuevo de tu contraparte',
    );
    return '$_temp0';
  }

  @override
  String chatCardSolverMessage(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count mensajes nuevos del resolutor de disputas',
      one: '1 mensaje nuevo del resolutor de disputas',
    );
    return '$_temp0';
  }

  @override
  String get invalidTradeIndexError =>
      'Tu cuenta no está sincronizada con este nodo Mostro, así que rechazó la orden. Inténtalo de nuevo en un momento';

  @override
  String get recoveringTradesMessage =>
      'Cuenta importada. Recuperando tus operaciones desde Mostro…';

  @override
  String recoveredTradesMessage(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Cuenta importada. Se recuperaron $count operaciones',
      one: 'Cuenta importada. Se recuperó 1 operación',
      zero: 'Cuenta importada. No tenías operaciones en curso',
    );
    return '$_temp0';
  }

  @override
  String get recoverTradesFailedMessage =>
      'Cuenta importada, pero Mostro no respondió, así que no se recuperaron tus operaciones en curso';

  @override
  String get paymentMethodsChosenLabel => 'Elegidos';

  @override
  String paymentMethodsSelectedCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count métodos seleccionados',
      one: '1 método seleccionado',
      zero: 'Elige al menos un método',
    );
    return '$_temp0';
  }

  @override
  String get paymentMethodsConfirm => 'Confirmar métodos';

  @override
  String get paymentMethodAddCustom => 'Agregar método personalizado';

  @override
  String get paymentMethodsDiscardTitle => '¿Descartar los cambios?';

  @override
  String get paymentMethodsDiscardConfirm => 'Descartar';

  @override
  String get paymentMethodsKeepEditing => 'Seguir editando';

  @override
  String get fundsAtRiskTitle => 'Este usuario todavía tiene sats en juego';

  @override
  String get fundsAtRiskBody =>
      'Si continúas, las llaves de este usuario se reemplazan y nada de lo que aparece aquí podrá terminarse ni recuperarse desde este dispositivo. No se recomienda: puedes perder estos sats.';

  @override
  String get fundsAtRiskSellerEscrow =>
      'Sats retenidos en garantía por una venta';

  @override
  String get fundsAtRiskBondLocked => 'Fianza retenida';

  @override
  String get fundsAtRiskPayoutClaim => 'Pago de fianza aún sin cobrar';

  @override
  String get fundsAtRiskTradeInProgress => 'Operación en curso';

  @override
  String get fundsAtRiskBondInvoicePending => 'Factura de fianza aún pagable';

  @override
  String get fundsAtRiskKeep => 'Conservar este usuario';

  @override
  String get fundsAtRiskContinue => 'Continuar de todos modos';

  @override
  String get restoreSheetTitle => 'Restaurando tu cuenta';

  @override
  String get restoreSheetWaiting => 'Puede tardar unos segundos';

  @override
  String restoreSheetLoading(int done, int total) {
    return '$done de $total órdenes recuperadas';
  }

  @override
  String get restoreStageConnecting => 'Conectando con el nodo Mostro';

  @override
  String get restoreStageConnected => 'Conectado con el nodo Mostro';

  @override
  String get restoreStageRequesting => 'Solicitando tus órdenes';

  @override
  String restoreStageFound(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count órdenes encontradas',
      one: '1 orden encontrada',
    );
    return '$_temp0';
  }

  @override
  String get restoreStageLoading => 'Cargando detalles';

  @override
  String get restoreStageNoResponse => 'Sin respuesta';

  @override
  String restoreLoadingCountSemantics(int done, int total) {
    return '$done de $total órdenes';
  }

  @override
  String get restoreFailedTitle => 'No pudimos restaurar tus órdenes';

  @override
  String get restoreFailedSubtitle => 'Tu cuenta sí quedó importada';

  @override
  String restoreFailedBody(String place) {
    return 'Revisa tu conexión e inténtalo de nuevo. Puedes reintentar cuando quieras desde $place.';
  }

  @override
  String get restoreContinueWithout => 'Continuar sin restaurar';

  @override
  String get restoreDoneTitle => 'Cuenta restaurada';

  @override
  String get restoreDoneSubtitle => 'Recuperamos todo lo que el nodo tenía';

  @override
  String get restoreDoneEmptySubtitle =>
      'Esta cuenta no tenía órdenes en el nodo';

  @override
  String get restoreSummaryOrders => 'Órdenes';

  @override
  String get restoreSummaryInProgress => 'En curso';

  @override
  String restoreActionNotice(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Tienes $count órdenes activas esperando tu acción',
      one: 'Tienes 1 orden activa esperando tu acción',
    );
    return '$_temp0';
  }

  @override
  String restorePartialNotice(int missing, int total) {
    return '$missing de $total órdenes no se pudieron cargar';
  }
}

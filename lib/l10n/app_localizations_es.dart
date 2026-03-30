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
}

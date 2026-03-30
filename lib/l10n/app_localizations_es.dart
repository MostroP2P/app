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
}

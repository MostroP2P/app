// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Portuguese (`pt`).
class AppLocalizationsPt extends AppLocalizations {
  AppLocalizationsPt([String locale = 'pt']) : super(locale);

  @override
  String get appName => 'Mostro';

  @override
  String get loading => 'Carregando…';

  @override
  String get actionFailedAnnouncement => 'Falha na ação';

  @override
  String get cancel => 'Cancelar';

  @override
  String get confirm => 'Confirmar';

  @override
  String get done => 'Concluído';

  @override
  String get skip => 'Pular';

  @override
  String get chatTimestampYesterday => 'Ontem';

  @override
  String get disputesEmptyState => 'Suas disputas aparecerão aqui';

  @override
  String get disputeAttachFile => 'Anexar arquivo';

  @override
  String get disputeWriteMessageHint => 'Escreva uma mensagem…';

  @override
  String get disputeSend => 'Enviar';

  @override
  String get orderDispute => 'Disputa da ordem';

  @override
  String get disputeSolverAssigned =>
      'Um mediador assumiu sua disputa e entrará em contato com você aqui em breve.';

  @override
  String get disputeChatClosed =>
      'Esta disputa foi resolvida. O chat está encerrado.';

  @override
  String get messageCopied => 'Copiado';

  @override
  String get disputeLoadError =>
      'Não foi possível carregar as disputas. Tente novamente.';

  @override
  String get disputeSolverNotAssigned =>
      'Nenhum mediador assumiu esta disputa ainda. Você poderá escrever assim que um assumir.';

  @override
  String get disputeNotFound => 'Disputa não encontrada.';

  @override
  String get disputeNotFoundForOrder =>
      'Nenhuma disputa encontrada para esta ordem.';

  @override
  String get disputeResolved => 'Resolvida';

  @override
  String get disputeSuccessfullyCompleted => 'Concluída com sucesso';

  @override
  String get disputeCoopCancelMessage =>
      'A ordem foi cancelada de forma cooperativa. Nenhum fundo foi transferido.';

  @override
  String orderLabel(String orderId) {
    return 'Ordem $orderId';
  }

  @override
  String get disputeStatusClosed => 'Encerrada';

  @override
  String disputeWith(String role, String counterparty) {
    return 'Disputa com $role: $counterparty';
  }

  @override
  String get seller => 'Vendedor';

  @override
  String get buyer => 'Comprador';

  @override
  String get disputeStatusInitiated => 'Iniciada';

  @override
  String get disputeStatusInProgress => 'Em andamento';

  @override
  String get disputeStatusResolved => 'Resolvida';

  @override
  String get disputeInProgress =>
      'Esta disputa está em andamento. Um mediador está analisando seu caso.';

  @override
  String get disputeInstruction1 =>
      'Aguarde até que um mediador assuma sua disputa. Depois, compartilhe todas as evidências relevantes para ajudar a esclarecer a situação.';

  @override
  String get disputeInstruction2 =>
      'A decisão final se baseará nas evidências apresentadas.';

  @override
  String get disputeInstruction3 =>
      'Se você não responder, o sistema vai entender que você não quer cooperar e você poderá perder a disputa.';

  @override
  String disputeOpenedByYouAgainstSeller(String counterparty) {
    return 'Você abriu esta disputa contra o vendedor $counterparty; leia com atenção as informações abaixo:';
  }

  @override
  String disputeOpenedByYouAgainstBuyer(String counterparty) {
    return 'Você abriu esta disputa contra o comprador $counterparty; leia com atenção as informações abaixo:';
  }

  @override
  String get disputeWaitingForAdmin => 'Aguardando a designação de um mediador';

  @override
  String get disputeLostFundsToBuyer =>
      'O mediador resolveu a disputa a favor do comprador. Os sats foram liberados para o comprador.';

  @override
  String get disputeLostFundsToSeller =>
      'O mediador cancelou a ordem e devolveu os sats ao vendedor. Você não recebeu os sats.';

  @override
  String get walkthroughWelcomeTitle => 'Bitcoin P2P, sem KYC';

  @override
  String get walkthroughWelcomeBody1 =>
      'O Mostro é uma exchange peer-to-peer que permite comprar e vender Bitcoin com qualquer moeda e método de pagamento, sem KYC e sem precisar entregar seus dados a ninguém.';

  @override
  String get walkthroughWelcomeBody2 =>
      'Ele funciona sobre o Nostr, o que o torna resistente à censura. Ninguém pode impedir você de operar.';

  @override
  String get walkthroughPrivacyTitle => 'Privacidade por padrão';

  @override
  String get walkthroughPrivacyBody1 =>
      'O Mostro gera uma nova identidade para cada operação, então suas operações não podem ser vinculadas entre si.';

  @override
  String get walkthroughPrivacyBody2 =>
      'Você também pode decidir quanta privacidade quer:';

  @override
  String get walkthroughReputationModeName => 'Modo reputação';

  @override
  String get walkthroughReputationModeBody =>
      'Permite que outras pessoas vejam suas operações bem-sucedidas e seu nível de confiança.';

  @override
  String get walkthroughFullPrivacyModeName => 'Modo privacidade total';

  @override
  String get walkthroughFullPrivacyModeBody =>
      'Você não constrói reputação, mas sua atividade é totalmente anônima.';

  @override
  String get walkthroughPrivacyFooter =>
      'Mude de modo quando quiser na tela Conta. É lá também que você deve salvar suas palavras secretas. Elas são a única forma de recuperar sua conta.';

  @override
  String get walkthroughHeldTitle => 'Segurança em cada etapa';

  @override
  String get walkthroughHeldBody1 =>
      'Os sats do vendedor ficam bloqueados até o fim da operação. Isso protege os dois lados.';

  @override
  String get walkthroughHeldBody2 =>
      'O app também foi pensado para ser intuitivo e fácil para todo tipo de usuário.';

  @override
  String get walkthroughChatTitle => 'Chat totalmente criptografado';

  @override
  String get walkthroughChatBody1 =>
      'Cada operação tem seu próprio chat privado, com criptografia de ponta a ponta. Só você e sua contraparte podem lê-lo, a menos que um de vocês compartilhe a chave do chat.';

  @override
  String get walkthroughChatBody2 =>
      'Em uma disputa, compartilhar essa chave com um mediador permite que ele leia o chat e ajude a resolvê-la.';

  @override
  String get walkthroughTakeTitle => 'Aceite uma ordem';

  @override
  String get walkthroughTakeBody1 =>
      'Navegue pelo livro de ordens, escolha uma ordem que funcione para você e acompanhe a operação passo a passo.';

  @override
  String get walkthroughTakeBody2 =>
      'Você poderá ver o perfil da sua contraparte, conversar com segurança e concluir a operação com facilidade.';

  @override
  String get walkthroughMakeTitle => 'Não encontrou o que procura?';

  @override
  String get walkthroughMakeBody1 =>
      'Você também pode criar sua própria ordem e esperar que alguém a aceite.';

  @override
  String get walkthroughMakeBody2 =>
      'Defina o valor e seu método de pagamento preferido. O Mostro cuida do resto.';

  @override
  String get walkthroughNext => 'Próximo';

  @override
  String walkthroughStepCounter(int current, int total) {
    return '$current / $total';
  }

  @override
  String walkthroughStepSemantics(int current, int total) {
    return 'Passo $current de $total';
  }

  @override
  String get tabBuyBtc => 'Comprar BTC';

  @override
  String get tabSellBtc => 'Vender BTC';

  @override
  String get filterButtonLabel => 'Filtrar';

  @override
  String filtersActiveCount(int count) {
    final intl.NumberFormat countNumberFormat = intl
        .NumberFormat.decimalPattern(localeName);
    final String countString = countNumberFormat.format(count);

    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$countString filtros ativos',
      one: '1 filtro ativo',
      zero: '0 filtros ativos',
    );
    return '$_temp0';
  }

  @override
  String get noOrdersAvailable => 'Nenhuma ordem disponível';

  @override
  String get justNow => 'Agora mesmo';

  @override
  String minutesAgo(int m) {
    return 'há $m min';
  }

  @override
  String hoursAgo(int h) {
    return 'há $h h';
  }

  @override
  String daysAgo(int d) {
    return 'há $d d';
  }

  @override
  String get invoiceRejected =>
      'O nó rejeitou esta fatura. Verifique o valor e a validade dela e adicione uma nova.';

  @override
  String get invoiceCopied => 'Fatura copiada';

  @override
  String get submitButtonLabel => 'Enviar';

  @override
  String get orderAlreadyTaken => 'Esta ordem já foi aceita';

  @override
  String get nodeProtocolUnsupported =>
      'Este nó Mostro usa uma versão de protocolo que este app não suporta. Escolha outro nó em Configurações ou verifique se há uma atualização do app';

  @override
  String get nodeCapabilitiesUnknown =>
      'Ainda verificando o que o nó Mostro selecionado suporta. Tente novamente em instantes';

  @override
  String get tradeOnOtherNode =>
      'Esta operação pertence a outro nó Mostro. Mude para esse nó para realizar ações nela';

  @override
  String get mostroMaintenanceMode =>
      'O nó Mostro ao qual você está conectado está em manutenção. Tente novamente mais tarde ou conecte-se a outro nó Mostro em Configurações';

  @override
  String get storageUnavailable =>
      'O app não pode criar nem aceitar ordens enquanto o banco de dados local estiver indisponível. Reinicie o app e tente novamente';

  @override
  String get rangeOrderWithSats =>
      'Uma ordem com faixa não pode ter um valor fixo em sats: seu preço é o de mercado no momento em que é aceita.';

  @override
  String get orderIdCopied => 'ID da ordem copiado';

  @override
  String get comingSoonMessage => 'Em breve';

  @override
  String get tradeStatusCompleted => 'Concluída';

  @override
  String get tradeStatusCancelled => 'Cancelada';

  @override
  String get tradeStatusDisputed => 'Em disputa';

  @override
  String get accountScreenTitle => 'Conta';

  @override
  String get secretWordsTitle => 'Palavras secretas';

  @override
  String get privacyCardTitle => 'Privacidade';

  @override
  String get reputationMode => 'Modo reputação';

  @override
  String get reputationModeSubtitle =>
      'Suas operações contam para sua reputação pública';

  @override
  String get fullPrivacyMode => 'Modo privacidade total';

  @override
  String get fullPrivacyModeSubtitle =>
      'Cada operação usa uma nova identidade, sem reputação';

  @override
  String get generateNewUserButton => 'Gerar novo usuário';

  @override
  String get importMostroUserButton => 'Importar usuário Mostro';

  @override
  String get generateNewUserDialogTitle => 'Gerar novo usuário?';

  @override
  String get generateNewUserDialogContent =>
      'Isso criará uma identidade totalmente nova. Suas palavras secretas atuais deixarão de funcionar — certifique-se de ter feito backup delas antes de continuar.';

  @override
  String get continueButtonLabel => 'Continuar';

  @override
  String get importMnemonicDialogTitle => 'Importar palavras secretas';

  @override
  String get importMnemonicHintText => 'Insira suas 12 palavras secretas';

  @override
  String get importButtonLabel => 'Importar';

  @override
  String get refreshUserDialogTitle => 'Atualizar usuário?';

  @override
  String get refreshUserDialogContent =>
      'Isso buscará novamente suas operações e ordens na instância Mostro. Use esta opção se achar que seus dados estão dessincronizados ou que faltam ordens.';

  @override
  String get hideButtonLabel => 'Ocultar';

  @override
  String get showWordsButton => 'Mostrar palavras';

  @override
  String get settingsScreenTitle => 'Configurações';

  @override
  String get languageSettingTitle => 'Idioma';

  @override
  String get appearanceSettingTitle => 'Aparência';

  @override
  String get appearanceDialogTitle => 'Aparência';

  @override
  String get allCurrencies => 'Todas as moedas';

  @override
  String get lightningAddressSettingTitle => 'Endereço Lightning';

  @override
  String get nwcWalletSettingTitle => 'Carteira NWC';

  @override
  String get relaysSettingTitle => 'Relays';

  @override
  String get pushNotificationsSettingTitle => 'Notificações push';

  @override
  String get logReportSettingTitle => 'Relatório de logs';

  @override
  String get mostroNodeSettingTitle => 'Nó Mostro';

  @override
  String get themeDark => 'Escuro';

  @override
  String get themeLight => 'Claro';

  @override
  String get themeSystemDefault => 'Padrão do sistema';

  @override
  String get lightningAddressDialogTitle => 'Endereço Lightning';

  @override
  String get lightningAddressHintText => 'usuario@dominio.com';

  @override
  String get invalidLightningAddressFormat =>
      'Deve estar no formato usuario@dominio';

  @override
  String get clearButtonLabel => 'Limpar';

  @override
  String get saveButtonLabel => 'Salvar';

  @override
  String get scanQrCodeTitle => 'Escanear código QR';

  @override
  String get selectLanguageTitle => 'Selecionar idioma';

  @override
  String get selectCurrencyDialogTitle => 'Selecionar moeda';

  @override
  String get addRelayDialogTitle => 'Adicionar relay';

  @override
  String get addButtonLabel => 'Adicionar';

  @override
  String get relayHintText => 'wss://relay.example.com';

  @override
  String get relayErrorMustStartWithWss => 'Deve começar com wss://';

  @override
  String get relayErrorUrlTooShort => 'A URL é curta demais';

  @override
  String get relayErrorDuplicate => 'O relay já está na lista';

  @override
  String get pasteQrCodeHeading => 'Colar conteúdo do código QR';

  @override
  String get pasteButtonLabel => 'Colar';

  @override
  String get clipboardEmptyError => 'A área de transferência está vazia';

  @override
  String get enterValueError => 'Insira um valor';

  @override
  String get trustedBadgeLabel => 'Confiável';

  @override
  String get confirmButtonLabel => 'Confirmar';

  @override
  String get selectMostroNode => 'Escolha um nó';

  @override
  String get addCustomNode => 'Adicionar seu próprio nó';

  @override
  String get nodePubkeyFieldLabel => 'Chave pública';

  @override
  String get nodePubkeyFieldHint => 'Hex de 64 caracteres ou npub…';

  @override
  String get nodeNameOptionalLabel => 'Nome (opcional)';

  @override
  String get invalidPubkeyFormat =>
      'Insira uma chave pública válida (hex de 64 caracteres ou npub)';

  @override
  String get privateKeyNotAllowed =>
      'Isso é uma chave privada — nunca a compartilhe. Insira a chave pública do nó';

  @override
  String get nodeAlreadyExists => 'Este nó já está na lista';

  @override
  String get nodeAddedSuccess => 'Nó adicionado';

  @override
  String nodeSwitchedSuccess(String nodeName) {
    return 'Agora usando $nodeName';
  }

  @override
  String get errorSwitchingNode => 'Não foi possível mudar de nó';

  @override
  String get cannotRemoveActiveNode =>
      'O nó ativo não pode ser removido — mude primeiro para outro nó';

  @override
  String get deleteCustomNodeTitle => 'Remover nó';

  @override
  String get deleteCustomNodeMessage =>
      'Remover este nó personalizado da sua lista?';

  @override
  String get deleteCustomNodeConfirm => 'Remover';

  @override
  String get nodeRemovedSuccess => 'Nó removido';

  @override
  String get nodeStorageUnavailable =>
      'O banco de dados local não está pronto. Reinicie o app e tente novamente';

  @override
  String nodeSelectorSubtitle(String code) {
    return 'Ordens e moedas para $code, sua moeda';
  }

  @override
  String get nodeSelectorSubtitleNoCurrency => 'Ordens abertas em cada nó';

  @override
  String nodeMissingCurrencyChip(String code) {
    return 'SEM $code';
  }

  @override
  String get nodeOrdersNowLabel => 'ordens agora';

  @override
  String get nodeNoOrdersLabel => 'sem ordens';

  @override
  String nodeOrdersInCurrency(int count, String code) {
    return '· $count em $code';
  }

  @override
  String get nodeFeeLabel => 'taxa';

  @override
  String get nodeFeeTooltip => 'O Mostro divide a taxa entre as duas partes.';

  @override
  String get nodePerTradeLabel => 'por operação';

  @override
  String get nodeCustodyLightning => 'Custódia Lightning';

  @override
  String nodeCustodyCashu(String mint) {
    return 'Custódia Cashu · $mint';
  }

  @override
  String get nodeCustodyUnknown => 'Custódia —';

  @override
  String nodeBondPct(String pct) {
    return 'Depósito $pct%';
  }

  @override
  String get nodeBondNone => 'Sem depósito';

  @override
  String nodeStatusOnline(int count) {
    final intl.NumberFormat countNumberFormat = intl
        .NumberFormat.decimalPattern(localeName);
    final String countString = countNumberFormat.format(count);

    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$countString ordens',
      one: '1 ordem',
      zero: '0 ordens',
    );
    return 'Online · $_temp0';
  }

  @override
  String get nodeStatusNoUsefulOrders => 'Nenhuma ordem nas suas moedas';

  @override
  String nodeStatusUnreachable(String ago) {
    return 'Não responde · último sinal $ago';
  }

  @override
  String get nodeStatusUnreachableNoSignal => 'Não responde';

  @override
  String get nodeChoiceSubtitle =>
      'Selecione o nó Mostro em que você quer operar';

  @override
  String get nodeOperatorDisclaimer =>
      'A equipe de desenvolvimento do Mostro não se responsabiliza pela forma como os operadores de nós usam a plataforma. Cada operador controla seu próprio nó Mostro e é o único responsável por suas ações. Ao usar o Mostro, você assume total responsabilidade pelas suas operações e reconhece que a equipe de desenvolvimento não tem controle sobre os operadores de nós individuais.';

  @override
  String get nodeChoiceConfirm => 'Usar este nó';

  @override
  String get nodeChoiceSaveFailed =>
      'Não foi possível salvar sua escolha. Tente novamente.';

  @override
  String get nodeVerifyKeyWarning =>
      'Confirme a chave com o operador. Um nó falso pode ver suas ordens.';

  @override
  String get nodeInvalidPubkeyShort => 'Esta não é uma chave pública válida.';

  @override
  String get nodeNameFieldHint => 'Mostro local';

  @override
  String get nodePubkeyCopied => 'Chave copiada';

  @override
  String get nodeNotSelectableOffline => 'Este nó não está respondendo';

  @override
  String get nodeStatsLoading => 'Carregando dados do nó';

  @override
  String get nodeSwitchConfirmTitle => 'Mudar de nó?';

  @override
  String nodeSwitchConfirmBody(String currentNode, String newNode) {
    return 'Você tem uma operação em andamento em $currentNode. Ela continua lá; o livro de ordens agora mostrará $newNode.';
  }

  @override
  String get nodeSwitchConfirmAction => 'Mudar de nó';

  @override
  String get nodeTradesCheckFailed =>
      'Não foi possível verificar suas operações. Tente novamente.';

  @override
  String get notificationsScreenTitle => 'Notificações';

  @override
  String get markAllAsReadMenuItem => 'Marcar todas como lidas';

  @override
  String get clearAllMenuItem => 'Limpar tudo';

  @override
  String get youMustBackUpYourAccount =>
      'Você precisa fazer backup da sua conta';

  @override
  String get tapToViewAndSaveSecretWords =>
      'Toque para ver e salvar suas palavras secretas.';

  @override
  String get noNotifications => 'Nenhuma notificação';

  @override
  String get markAsRead => 'Marcar como lida';

  @override
  String get deleteNotificationLabel => 'Excluir';

  @override
  String get rateScreenHeader => 'AVALIAR';

  @override
  String get successfulOrder => 'Ordem bem-sucedida';

  @override
  String get closeRatingButton => 'FECHAR';

  @override
  String get aboutScreenTitle => 'Sobre';

  @override
  String get linkCopiedToClipboard =>
      'Link copiado para a área de transferência';

  @override
  String get pubkeyLabel => 'Chave pública';

  @override
  String get relaysLabel => 'Relays';

  @override
  String get footerTagline => 'Código aberto. Sem custódia. Privado.';

  @override
  String get drawerTitle => 'Mostro';

  @override
  String get drawerTagline => 'Exchange P2P';

  @override
  String get drawerStageBadge => 'Beta';

  @override
  String drawerVersion(String version) {
    return 'Versão $version';
  }

  @override
  String get drawerAccountMenuItem => 'Conta';

  @override
  String get drawerSettingsMenuItem => 'Configurações';

  @override
  String get drawerAboutMenuItem => 'Sobre';

  @override
  String get navOrderBook => 'Livro de ordens';

  @override
  String get navMyTrades => 'Minhas operações';

  @override
  String get navChat => 'Chat';

  @override
  String get loadingOrders => 'Carregando ordens…';

  @override
  String get errorLoadingOrders =>
      'Não foi possível carregar as ordens. Verifique sua conexão.';

  @override
  String get retry => 'Tentar novamente';

  @override
  String disableRelayLabel(String url) {
    return 'Desativar relay $url';
  }

  @override
  String enableRelayLabel(String url) {
    return 'Ativar relay $url';
  }

  @override
  String get removeRelayTooltip => 'Remover relay';

  @override
  String get relayAddFailed => 'Não foi possível adicionar o relay';

  @override
  String get relayRemoveFailed => 'Não foi possível remover o relay';

  @override
  String get backupRitualSecondFailureMessage =>
      'Incorreto novamente. Revise suas palavras secretas e faça backup delas; depois, verifique desde o início.';

  @override
  String get cancelTradeDialogTitle => 'Cancelar operação?';

  @override
  String get cancelTradeDialogContent =>
      'Será solicitado um cancelamento cooperativo. A contraparte também precisa concordar para que a operação seja totalmente cancelada.';

  @override
  String get cancelTradeDialogContentNotStarted =>
      'A operação ainda não começou, então será cancelada imediatamente. A contraparte não precisa concordar.';

  @override
  String get cancelTradeDialogContentMaybeStarted =>
      'Se a operação ainda não começou, ela será cancelada imediatamente. Se já começou, a contraparte também precisa concordar.';

  @override
  String get noButtonLabel => 'Não';

  @override
  String get yesButtonLabel => 'Sim';

  @override
  String get yesCancelButtonLabel => 'Sim, cancelar';

  @override
  String get cancelRequestSent => 'Solicitação de cancelamento enviada';

  @override
  String get cancelRequestFailed =>
      'Não foi possível cancelar. Tente novamente.';

  @override
  String get tradeCardCancelRequestedByMeTitle => 'Cancelamento solicitado';

  @override
  String get tradeCardCancelRequestedByMeMessage =>
      'Você pediu para cancelar esta operação. Ela continua aberta até que a contraparte também cancele. Se não houver resposta, você pode abrir uma disputa.';

  @override
  String get tradeCardCancelRequestedByPeerTitle =>
      'A contraparte quer cancelar';

  @override
  String get tradeCardCancelRequestedByPeerMessage =>
      'A contraparte pediu para cancelar esta operação. Aceite para encerrá-la sem movimentar fundos, ou siga com a operação.';

  @override
  String get tradeCancelRequestedByMeNotice =>
      'Você pediu para cancelar esta operação. Ela continua aberta até que a contraparte também cancele. Se não houver resposta, você pode abrir uma disputa.';

  @override
  String get tradeCancelRequestedByPeerNotice =>
      'A contraparte pediu para cancelar esta operação. Aceite para encerrá-la sem movimentar fundos, ou siga com a operação.';

  @override
  String get acceptCancelButton => 'Aceitar cancelamento';

  @override
  String get cancelTradeDialogContentAccept =>
      'A contraparte pediu para cancelar. Se você cancelar agora, a operação termina para os dois e nenhum fundo é movimentado.';

  @override
  String get fiatSentFailed =>
      'Não foi possível marcar o pagamento como enviado. Tente novamente.';

  @override
  String get releaseFailed => 'Não foi possível liberar. Tente novamente.';

  @override
  String get releasePendingLabel => 'Liberando… aguardando o nó';

  @override
  String get releaseSentNotice =>
      'Liberação enviada. O nó pode levar até um minuto para confirmá-la.';

  @override
  String get releaseUnconfirmedNotice =>
      'O nó ainda não confirmou a liberação. Se a ordem não for atualizada, você pode liberar novamente.';

  @override
  String get cancelTradeButton => 'Cancelar operação';

  @override
  String get payHoldInvoiceButton => 'Pagar fatura';

  @override
  String get openDisputeButton => 'Abrir disputa';

  @override
  String get releaseSatsButton => 'Liberar sats';

  @override
  String get confirmReleaseSatsButton => 'Confirmar e liberar sats';

  @override
  String get shareOrderButton => 'Compartilhar ordem';

  @override
  String get orderPillYouAreSelling => 'VOCÊ ESTÁ VENDENDO';

  @override
  String get orderPillYouAreBuying => 'VOCÊ ESTÁ COMPRANDO';

  @override
  String get myOrderSellTitle => 'Sua ordem de venda';

  @override
  String get myOrderBuyTitle => 'Sua ordem de compra';

  @override
  String get cancelOrderFailed =>
      'Não foi possível cancelar a ordem. Tente novamente.';

  @override
  String get closeButtonLabel => 'Fechar';

  @override
  String get copyButtonLabel => 'Copiar';

  @override
  String get orderStatusWaitingForTaker => 'Aguardando alguém aceitar';

  @override
  String get orderStatusInProgress => 'Em andamento';

  @override
  String get orderStatusExpired => 'Expirada';

  @override
  String get copyOrderIdTooltip => 'Copiar ID da ordem';

  @override
  String get orderNotFoundTitle => 'Ordem não encontrada';

  @override
  String get orderNotFoundMessage => 'Esta ordem não está mais disponível.';

  @override
  String get orderCancelledSuccess => 'Ordem cancelada com sucesso.';

  @override
  String get aboutDocumentationTitle => 'Documentação';

  @override
  String get aboutMostroNodeTitle => 'Nó Mostro';

  @override
  String get aboutVersionLabel => 'Versão';

  @override
  String get aboutCommitHashLabel => 'Hash do commit';

  @override
  String get aboutLicenseLabel => 'Licença';

  @override
  String get aboutLicenseName => 'AGPLv3+';

  @override
  String get aboutGithubRepoName => 'MostroP2P/app';

  @override
  String get aboutCopiedToClipboard => 'Copiado para a área de transferência';

  @override
  String get aboutLicenseDialogTitle => 'Licença Pública Geral Affero GNU v3';

  @override
  String get aboutNodeLoadingText => 'Carregando informações do nó…';

  @override
  String get aboutNodeUnavailable => 'Informações do nó indisponíveis';

  @override
  String get aboutNodeRetry => 'Tentar novamente';

  @override
  String get aboutLightningNetworkSection => 'Lightning Network';

  @override
  String get aboutFiatCurrenciesLabel => 'Moedas fiat';

  @override
  String get aboutPriceSourceLabel => 'Fonte';

  @override
  String get aboutPriceSection => 'Preço';

  @override
  String get aboutPriceSourcesFootnote =>
      'As fontes de preço são os provedores das cotações que o nó publica agora; uma fonte que falhou ou foi descartada não aparece na lista.';

  @override
  String get aboutMostroVersionLabel => 'Versão do Mostro';

  @override
  String get aboutMostroCommitLabel => 'Commit do Mostro';

  @override
  String get aboutHoldInvoiceExpLabel => 'Validade da fatura de retenção';

  @override
  String get aboutHoldInvoiceCltvLabel => 'CLTV da fatura de retenção';

  @override
  String get aboutInvoiceExpWindowLabel => 'Janela de validade da fatura';

  @override
  String get aboutProofOfWorkLabel => 'Prova de trabalho';

  @override
  String get aboutMaxOrdersPerResponseLabel => 'Máx. de ordens/resposta';

  @override
  String get aboutLndVersionLabel => 'Versão do LND';

  @override
  String get aboutSupportedChainsLabel => 'Cadeias suportadas';

  @override
  String get aboutSupportedNetworksLabel => 'Redes suportadas';

  @override
  String get aboutSatoshisSuffix => 'Satoshis';

  @override
  String get aboutBlocksSuffix => 'blocos';

  @override
  String get aboutFiatCurrenciesAll => 'Todas';

  @override
  String get aboutAntiAbuseBondSection => 'Depósito antiabuso';

  @override
  String get aboutBondEnabledValue => 'Ativado';

  @override
  String get aboutBondDisabledValue => 'Desativado';

  @override
  String get aboutBondUnsupportedValue => 'Não suportado';

  @override
  String get aboutBondStatusLabel => 'Status do depósito';

  @override
  String get aboutBondAppliesToLabel => 'Aplica-se a';

  @override
  String get aboutBondAppliesToTakers => 'Quem aceita a ordem';

  @override
  String get aboutBondAppliesToMakers => 'Criador da ordem';

  @override
  String get aboutBondAppliesToBoth => 'Ambas as partes';

  @override
  String get aboutBondAmountLabel => 'Valor do depósito';

  @override
  String get aboutBondBaseAmountLabel => 'Depósito mínimo';

  @override
  String get aboutBondNodeShareLabel => 'Parte do nó em caso de confisco';

  @override
  String get aboutBondSlashOnTimeoutLabel =>
      'Confisco por tempo de espera esgotado';

  @override
  String get aboutBondClaimWindowLabel => 'Prazo para resgatar o pagamento';

  @override
  String aboutBondClaimWindowValue(int count) {
    final intl.NumberFormat countNumberFormat = intl
        .NumberFormat.decimalPattern(localeName);
    final String countString = countNumberFormat.format(count);

    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$countString dias',
      one: '$countString dia',
      zero: '$countString dias',
    );
    return '$_temp0';
  }

  @override
  String get openDisputeFailed =>
      'Não foi possível abrir a disputa. Tente novamente.';

  @override
  String get openDisputeTitle => 'Abrir disputa';

  @override
  String get openDisputeConfirmation =>
      'Tem certeza de que quer abrir uma disputa? Isso encaminha a operação a um mediador e não pode ser desfeito.';

  @override
  String get disputeAlreadyOpen =>
      'Já existe uma disputa aberta para esta operação.';

  @override
  String get tradeNotDisputable =>
      'Só é possível abrir uma disputa depois que os fundos desta operação estiverem bloqueados.';

  @override
  String get tradeWaitingInvoiceBuyerInstruction =>
      'Envie sua fatura Lightning para que o vendedor possa bloquear os fundos.';

  @override
  String get tradeWaitingInvoiceSellerInstruction =>
      'Aguardando o comprador enviar a fatura Lightning dele.';

  @override
  String get tradeWaitingPaymentSellerInstruction =>
      'Pague a fatura para bloquear os fundos e iniciar a operação.';

  @override
  String get tradeLoadError => 'Ocorreu um erro ao carregar a operação.';

  @override
  String get tradeWaitingForHoldInvoice => 'Aguardando a fatura do nó…';

  @override
  String get shareButtonLabel => 'Compartilhar';

  @override
  String get shareFailed => 'Não foi possível compartilhar a fatura';

  @override
  String get waitingForPaymentConfirmation =>
      'Aguardando a confirmação do pagamento…';

  @override
  String get orderNoLongerActive => 'Esta ordem não está mais ativa';

  @override
  String get tradeNoLongerYours => 'Você não faz mais parte desta operação';

  @override
  String get sessionTimeoutMessage =>
      'Nenhuma resposta recebida. Verifique sua conexão e tente novamente mais tarde';

  @override
  String get noRelayAcceptedMessage =>
      'Nenhum relay aceitou sua mensagem. Verifique seus relays em Configurações e tente novamente';

  @override
  String get noIdentityFoundMessage =>
      'Nenhuma identidade encontrada — tente reiniciar o app.';

  @override
  String get failedToLoadSecretWordsMessage =>
      'Não foi possível carregar as palavras secretas. Tente novamente.';

  @override
  String get privacyModesInfoTitle => 'Modos de privacidade';

  @override
  String get privacyModesInfoContent =>
      'O modo reputação permite que outras pessoas vejam suas operações bem-sucedidas.\n\nO modo privacidade total mantém sua atividade completamente anônima — nenhuma reputação é construída.';

  @override
  String get failedToGenerateIdentityMessage =>
      'Não foi possível gerar a identidade. Tente novamente.';

  @override
  String get pendingWipeBannerTitle =>
      'Os dados do usuário anterior ainda estão neste dispositivo';

  @override
  String get pendingWipeBannerBody =>
      'Ao excluir a identidade anterior, não foi possível remover as operações e os chats dela deste dispositivo. O app tentará novamente na próxima vez que um novo usuário for gerado ou importado.';

  @override
  String get pendingWipeBlockedMessage =>
      'Não foi possível remover os dados do usuário anterior deste dispositivo, então o novo usuário não foi configurado e seu usuário atual foi mantido. Tente novamente.';

  @override
  String get wipeNotRecordedMessage =>
      'Não foi possível remover o usuário atual com segurança, então nada foi alterado. Tente novamente.';

  @override
  String get identitySwapStorageUnavailableMessage =>
      'O armazenamento deste dispositivo não está disponível no momento, então o usuário atual foi mantido e nada foi alterado. Reinicie o app e tente novamente.';

  @override
  String get identitySwapPreviousNotReloadedMessage =>
      'O novo usuário não foi configurado, e não foi possível restaurar totalmente o usuário atual. Reinicie o app para carregá-lo novamente.';

  @override
  String get invalidMnemonicMessage =>
      'Palavras secretas inválidas. Verifique suas palavras e tente novamente.';

  @override
  String get enterValidMnemonicError => 'Insira suas 12 palavras secretas.';

  @override
  String get orderBookRefreshedMessage => 'Livro de ordens atualizado';

  @override
  String get refreshFailedMessage => 'Falha ao atualizar';

  @override
  String get refreshButtonLabel => 'Atualizar';

  @override
  String get okButtonLabel => 'OK';

  @override
  String get moreInformationTooltip => 'Mais informações';

  @override
  String get backedUpBadgeLabel => 'Backup feito';

  @override
  String get backupBannerTitle => 'Proteja sua reputação';

  @override
  String get backupBannerSubtitle =>
      'Faça backup das suas 12 palavras — leva 60 segundos.';

  @override
  String get failedToSaveBackupStatusMessage =>
      'Não foi possível salvar o status do backup. Tente novamente.';

  @override
  String get backupRitualStep1Title => 'Passo 1 de 3 · Anote suas palavras';

  @override
  String get backupRitualStep2Title => 'Passo 2 de 3 · Verificar';

  @override
  String get backupRitualStep3Title => 'Passo 3 de 3 · Pronto';

  @override
  String get backupRitualWarningTitle => 'Anote-as em papel. ';

  @override
  String get backupRitualWarningBody =>
      'Não as guarde em fotos, capturas de tela ou na nuvem — qualquer pessoa com estas 12 palavras pode roubar sua reputação.';

  @override
  String get wordsHiddenOnLeaveNote =>
      'Elas serão ocultadas quando você sair desta tela';

  @override
  String get wroteThemDownVerifyButton => 'Já anotei — verificar';

  @override
  String get tapCorrectWordsTitle => 'Toque nas palavras corretas';

  @override
  String get verifyInstructionsBody =>
      'Pedimos 3 delas aleatoriamente. Se você acertar, sabemos que estão bem anotadas.';

  @override
  String optionsForWordLabel(int number) {
    return 'OPÇÕES PARA A PALAVRA #$number';
  }

  @override
  String get wrongPickMessage => 'Quase — confira seu papel e tente novamente.';

  @override
  String get allWordsCorrectMessage => 'As 3 palavras estão corretas';

  @override
  String get reviewWordsButton => 'Ver palavras';

  @override
  String get accountBackedUpTitle => 'Backup da sua conta concluído';

  @override
  String get accountBackedUpBody =>
      'Sua reputação está segura. Se algum dia você perder o celular, restaure sua conta com suas 12 palavras.';

  @override
  String wordNumberLabel(int number) {
    return 'Palavra #$number';
  }

  @override
  String get backupTriggerBody =>
      'Sua reputação vive em uma chave que só você tem. Se perder o celular, você perde essa reputação — ';

  @override
  String get backupTriggerBodyHighlight => 'faça backup em 60 segundos.';

  @override
  String get backupStepWriteDown => 'Anote suas 12 palavras em papel';

  @override
  String get backupStepVerifyRandom =>
      'Pedimos 3 aleatoriamente para confirmar';

  @override
  String get backupStepSecured => 'Pronto — sua conta está protegida';

  @override
  String get backupNowButton => 'Fazer backup agora';

  @override
  String get backupLaterButton => 'Vou fazer depois';

  @override
  String get nwcConnectionFailedMessage =>
      'Falha na conexão. Verifique sua URI NWC e tente novamente.';

  @override
  String get clipboardInvalidNwcUriMessage =>
      'A área de transferência não contém uma URI NWC válida.';

  @override
  String get scanQrButtonLabel => 'Escanear QR';

  @override
  String get connectButtonLabel => 'Conectar';

  @override
  String get walletDisconnectedMessage => 'Carteira desconectada';

  @override
  String get relayLabel => 'Relay';

  @override
  String get disconnectButtonLabel => 'Desconectar';

  @override
  String relaysMoreSuffix(int count) {
    return '(mais $count)';
  }

  @override
  String get chooseNotificationEventsSubtitle =>
      'Escolha quais eventos mostram uma notificação no app.';

  @override
  String get notifTradeUpdatesTitle => 'Atualizações de operações';

  @override
  String get notifTradeUpdatesSubtitle =>
      'Mudanças de status nas suas operações ativas';

  @override
  String get notifNewMessagesTitle => 'Novas mensagens';

  @override
  String get notifNewMessagesSubtitle => 'Mensagens da sua contraparte';

  @override
  String get notifPaymentAlertsTitle => 'Alertas de pagamento';

  @override
  String get notifPaymentAlertsSubtitle =>
      'Confirmações e falhas de pagamentos Lightning';

  @override
  String get notifDisputeUpdatesTitle => 'Atualizações de disputas';

  @override
  String get notifDisputeUpdatesSubtitle =>
      'Ações do mediador e resoluções de disputas';

  @override
  String get notifAnnouncementsTitle => 'Anúncios';

  @override
  String get notifAnnouncementsSubtitle =>
      'Versões, quedas e mudanças de relays, assinados pelo projeto Mostro';

  @override
  String get announcementsGroupSubtitle =>
      'Os anúncios são lidos dos relays e nunca respondidos: nada sobre você é enviado.';

  @override
  String get announcementLevelInfo => 'Anúncio';

  @override
  String get announcementLevelWarning => 'Aviso';

  @override
  String get announcementLevelCritical => 'Atualização de segurança';

  @override
  String get announcementOpenLink => 'Abrir link';

  @override
  String get notificationsBellCritical =>
      'Notificações, uma atualização de segurança não lida';

  @override
  String get searchCurrenciesHint => 'Buscar moedas…';

  @override
  String get noCurrenciesFoundMessage => 'Nenhuma moeda encontrada';

  @override
  String get shareLogsTooltip => 'Compartilhar logs';

  @override
  String get noLogsToShareTooltip => 'Nenhum log para compartilhar';

  @override
  String get noLogEntriesMessage => 'Nenhuma entrada de log';

  @override
  String get failedToShareLogsMessage =>
      'Não foi possível compartilhar os logs';

  @override
  String get logReportShareHeading => 'Relatório de logs do Mostro';

  @override
  String get tradeFilterAll => 'Todas';

  @override
  String get tradeFilterPending => 'Pendente';

  @override
  String get tradeFilterWaitingInvoice => 'Aguardando fatura';

  @override
  String get tradeFilterWaitingPayment => 'Aguardando pagamento';

  @override
  String get tradeFilterActive => 'Ativa';

  @override
  String get tradeFilterFiatSent => 'Fiat enviado';

  @override
  String get tradeFilterSuccess => 'Sucesso';

  @override
  String get tradeFilterCanceled => 'Cancelada';

  @override
  String get tradeFilterDispute => 'Disputa';

  @override
  String get menuTooltip => 'Menu';

  @override
  String get noTradesTitle => 'Nenhuma operação';

  @override
  String get noTradesSubtitle =>
      'Suas operações ativas e concluídas aparecerão aqui.';

  @override
  String get couldNotLoadTradesMessage =>
      'Não foi possível carregar as operações';

  @override
  String get sellingBitcoin => 'Vendendo Bitcoin';

  @override
  String get buyingBitcoin => 'Comprando Bitcoin';

  @override
  String get tradeInstructionActiveBuyer =>
      'Depois de enviar o dinheiro, marque abaixo. Só abra uma disputa se o vendedor parar de responder.';

  @override
  String get tradeInstructionFiatSentBuyer =>
      'Pagamento marcado como enviado. Aguardando o vendedor confirmar o recebimento e liberar seus sats.';

  @override
  String get tradeInstructionActiveSeller =>
      'Envie ao comprador as instruções de pagamento pelo chat acima.';

  @override
  String get tradeInstructionFiatSentSeller =>
      'O comprador confirmou que enviou o pagamento. Depois de confirmar o recebimento, libere os sats.';

  @override
  String get tradeInstructionDisputed =>
      'Um mediador foi designado para a disputa e entrará em contato com você pelo app.';

  @override
  String get tradeInstructionPending =>
      'Sua ordem está publicada e aguardando que uma contraparte a aceite. Você pode cancelá-la a qualquer momento.';

  @override
  String get tradeInstructionCancelled =>
      'Esta operação foi cancelada. Nenhum valor foi transferido.';

  @override
  String get tradeInstructionInProgress => 'Operação em andamento.';

  @override
  String get theAgreedAmount => 'o valor combinado';

  @override
  String get tradeHeadlinePending => 'Aguardando alguém aceitar sua ordem';

  @override
  String get tradeHeadlineInProgress => 'A operação está sendo preparada';

  @override
  String get tradeHeadlineWaitingInvoiceBuyer =>
      'Compartilhe uma fatura Lightning para receber seus sats';

  @override
  String get tradeHeadlineWaitingInvoiceSeller =>
      'Aguardando o comprador compartilhar uma fatura';

  @override
  String get tradeHeadlineWaitingPaymentBuyer =>
      'Aguardando o vendedor bloquear os sats';

  @override
  String get tradeHeadlineWaitingPaymentSeller =>
      'Pague a fatura para bloquear os sats';

  @override
  String tradeHeadlineActiveBuyer(String amount) {
    return 'Envie $amount ao vendedor';
  }

  @override
  String tradeHeadlineActiveSeller(String amount) {
    return 'Aguardando o comprador enviar $amount';
  }

  @override
  String get tradeHeadlineFiatSentBuyer =>
      'Aguardando o vendedor liberar seus sats';

  @override
  String tradeHeadlineFiatSentSeller(String amount) {
    return 'Confirme que você recebeu $amount';
  }

  @override
  String get tradeHeadlineDisputed => 'Disputa em andamento';

  @override
  String get tradeHeadlineCancelled => 'Ordem cancelada';

  @override
  String get tradeHeadlineLoading => 'Carregando operação…';

  @override
  String get tradeTimerPendingConsequence =>
      'Se expirar, a ordem é removida do livro. Isso não afeta sua reputação.';

  @override
  String get tradeTimerExpiryBackToBook =>
      'Se expirar, a ordem volta para o livro.';

  @override
  String get tradeTimerExpiryCancelled => 'Se expirar, a ordem é cancelada.';

  @override
  String get tradeTimerEscrowCancels =>
      'Tempo aproximado. Se acabar, o Mostro cancela a operação.';

  @override
  String get tradeTimerEscrowDisputes =>
      'Tempo aproximado. Se acabar, o Mostro abre uma disputa.';

  @override
  String get tradeTimerEscrowCancellingBuyer =>
      'O Mostro está prestes a cancelar a operação e devolver os sats ao vendedor.';

  @override
  String get tradeTimerEscrowCancellingSeller =>
      'O Mostro está prestes a cancelar a operação. Seus sats ficam na sua carteira.';

  @override
  String get tradeTimerEscrowDisputing =>
      'Uma disputa está prestes a ser aberta.';

  @override
  String get tradeStepOrderTaken => 'Ordem aceita';

  @override
  String get tradeStepWaitingTaker => 'Aguardando alguém aceitar';

  @override
  String get tradeStepInvoiceBuyer => 'O vendedor bloqueia os sats';

  @override
  String get tradeStepInvoiceSeller => 'Você bloqueia os sats';

  @override
  String get tradeStepFiatBuyer => 'Você envia o pagamento';

  @override
  String get tradeStepFiatSeller => 'O comprador envia o pagamento';

  @override
  String get tradeStepReleaseBuyer => 'O vendedor libera seus sats';

  @override
  String get tradeStepReleaseSeller => 'Você confirma e libera os sats';

  @override
  String get tradeStepPayoutBuyer => 'O Mostro envia seus sats';

  @override
  String get tradeStepRate => 'Avaliar a operação';

  @override
  String tradeCreatedAtLabel(String date) {
    return 'criada em $date';
  }

  @override
  String stepIndicator(int current, int total) {
    return 'PASSO $current DE $total';
  }

  @override
  String get addLightningInvoiceButton => 'Adicionar fatura Lightning';

  @override
  String get viewDisputeButton => 'Ver disputa';

  @override
  String get yourTradeTimelineTitle => 'SUA OPERAÇÃO';

  @override
  String get messageSendFailed =>
      'Não foi possível enviar a mensagem. Tente novamente.';

  @override
  String get invalidTradeId => 'ID da operação inválido';

  @override
  String get selectForDetailsHint => 'Selecione ℹ ou 👤\npara ver detalhes';

  @override
  String noMessagesYet(String handle) {
    return 'Nenhuma mensagem ainda.\nDiga olá para $handle!';
  }

  @override
  String get exchangeInfoTooltip => 'Informações da operação';

  @override
  String get userInfoTooltip => 'Informações do usuário';

  @override
  String chattingWith(String handle) {
    return 'Você está conversando com $handle';
  }

  @override
  String get unknownPeerHandle => 'Desconhecido';

  @override
  String get messagesTab => 'Mensagens';

  @override
  String get disputesTab => 'Disputas';

  @override
  String get tradeInformationTitle => 'Informações da operação';

  @override
  String get orderIdLabel => 'ID da ordem';

  @override
  String get fiatAmountLabel => 'Valor em fiat';

  @override
  String get satsAmountLabel => 'Valor em sats';

  @override
  String get peerReputationUnavailable =>
      'A reputação deste usuário não está disponível';

  @override
  String get statusLabel => 'Status';

  @override
  String get paymentMethodLabel => 'Método de pagamento';

  @override
  String get createdLabel => 'Criada';

  @override
  String get userInformationTitle => 'Informações do usuário';

  @override
  String get fileTypeVideo => 'Vídeo';

  @override
  String get fileTypeImage => 'Imagem';

  @override
  String get fileTypeArchive => 'Arquivo compactado';

  @override
  String get fileTypeFile => 'Arquivo';

  @override
  String buyingSatsAmount(String sats) {
    return 'Comprando $sats sats';
  }

  @override
  String sellingSatsAmount(String sats) {
    return 'Vendendo $sats sats';
  }

  @override
  String get viewOrderLink => 'Ver ordem';

  @override
  String timeLeftLabel(String time) {
    return 'Restam $time';
  }

  @override
  String get invoiceNoLongerExpected =>
      'Esta ordem não está mais aguardando uma fatura. Atualizando o status…';

  @override
  String get invoiceAwaitingNode =>
      'Enviado. O nó ainda não respondeu — abriremos a operação assim que ele responder.';

  @override
  String get invoiceAwaitingNodeLong =>
      'Ainda sem resposta do nó. Se a operação não avançar, envie novamente.';

  @override
  String get invoiceSubmitInFlight =>
      'Uma fatura para esta ordem já está sendo enviada. Aguarde a resposta.';

  @override
  String get waitingForTradeAmount =>
      'Aguardando o valor da operação — tente novamente em instantes.';

  @override
  String get fetchingTradeAmount => 'Obtendo o valor da operação…';

  @override
  String get enterInvoiceManually => 'Inserir fatura manualmente';

  @override
  String get rangeAmountTakeAction => 'Aceitar ordem';

  @override
  String orderAmountOutOfRange(int min, int max) {
    return 'O valor deve estar entre $min e $max sats para este nó Mostro';
  }

  @override
  String orderCurrencyNotAccepted(String currency) {
    return 'Este nó Mostro não aceita $currency. Escolha outra moeda';
  }

  @override
  String orderAmountOutOfRangeFiat(int min, int max, String currency) {
    return 'O valor deve estar entre $min e $max $currency para este nó Mostro';
  }

  @override
  String get priceTypeMarket => 'Mercado';

  @override
  String get priceTypeFixed => 'Fixo';

  @override
  String get priceTypeInfoTooltip => 'Informações sobre o tipo de preço';

  @override
  String get premiumSectionLabel => 'Prêmio';

  @override
  String get fixedPriceRangeNotAvailable =>
      'O preço fixo não está disponível para ordens com faixa. Desative a faixa para usar um preço fixo.';

  @override
  String get priceTypesDialogTitle => 'Tipos de preço';

  @override
  String get priceTypesDialogContent =>
      'Preço de mercado: sua ordem segue a cotação do mercado, com o prêmio ou desconto que você definir.\n\nPreço fixo: você define a quantidade exata de sats; ela não acompanha o mercado.';

  @override
  String get newOrderTitle => 'Nova ordem';

  @override
  String get amountSectionSell => 'Quanto você vende';

  @override
  String get amountSectionBuy => 'Quanto você compra';

  @override
  String get amountModeSingle => 'Único';

  @override
  String get amountModeRange => 'Faixa';

  @override
  String get amountMinLabel => 'Mínimo';

  @override
  String get amountMaxLabel => 'Máximo';

  @override
  String paymentMethodsChosenCount(int count) {
    final intl.NumberFormat countNumberFormat = intl
        .NumberFormat.decimalPattern(localeName);
    final String countString = countNumberFormat.format(count);

    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$countString selecionados',
      one: '1 selecionado',
      zero: 'nenhum selecionado',
    );
    return '$_temp0';
  }

  @override
  String get paymentMethodAdd => 'Adicionar';

  @override
  String get paymentMethodSearchHint => 'Buscar métodos';

  @override
  String get customPaymentMethodLabel => 'Método de pagamento personalizado';

  @override
  String get priceSectionTitle => 'Preço';

  @override
  String premiumSellAbove(String premium) {
    return 'Você vende $premium% acima do preço de mercado';
  }

  @override
  String premiumSellBelow(String premium) {
    return 'Você vende $premium% abaixo do mercado';
  }

  @override
  String premiumBuyBelow(String premium) {
    return 'Você paga $premium% menos que o mercado';
  }

  @override
  String premiumBuyAbove(String premium) {
    return 'Você paga $premium% a mais';
  }

  @override
  String get premiumExactMarket => 'Preço exato de mercado';

  @override
  String get fixedPriceNote =>
      'Com preço fixo, a ordem não segue o mercado: o valor em sats fica exatamente como você escrever.';

  @override
  String get previewHintNoAmount =>
      'Insira um valor para ver aqui como a ordem vai ficar.';

  @override
  String previewSellMarket(String amount, String premium, String active) {
    return 'Você vende BTC por $amount a preço de mercado $premium$active';
  }

  @override
  String previewSellMarketExact(String amount, String active) {
    return 'Você vende BTC por $amount a preço de mercado$active';
  }

  @override
  String previewBuyMarket(String amount, String premium, String active) {
    return 'Você compra BTC por $amount a preço de mercado $premium$active';
  }

  @override
  String previewBuyMarketExact(String amount, String active) {
    return 'Você compra BTC por $amount a preço de mercado$active';
  }

  @override
  String previewSellFixed(String sats, String amount, String active) {
    return 'Você vende $sats por $amount a preço fixo$active';
  }

  @override
  String previewBuyFixed(String sats, String amount, String active) {
    return 'Você compra $sats por $amount a preço fixo$active';
  }

  @override
  String previewActiveSuffix(String hours) {
    return ' · ativa por $hours';
  }

  @override
  String get publishOrder => 'Publicar ordem';

  @override
  String removePaymentMethod(String method) {
    return 'Remover $method';
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
  String get paymentMethodsLabel => 'Métodos de pagamento';

  @override
  String get customPaymentMethodHint => 'Método de pagamento personalizado…';

  @override
  String amountRangeError(String min, String max) {
    return 'O valor deve estar entre $min e $max';
  }

  @override
  String get enterAmountTitle => 'Insira o valor';

  @override
  String minMaxRangeLabel(String min, String max, String currency) {
    return 'Mín: $min – Máx: $max $currency';
  }

  @override
  String get ratingFailed =>
      'Não foi possível enviar a avaliação. Tente novamente.';

  @override
  String get submitUppercaseButton => 'ENVIAR';

  @override
  String selectStarTooltip(int count) {
    final intl.NumberFormat countNumberFormat = intl
        .NumberFormat.decimalPattern(localeName);
    final String countString = countNumberFormat.format(count);

    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Selecionar $countString estrelas',
      one: 'Selecionar 1 estrela',
      zero: 'Selecionar 0 estrelas',
    );
    return '$_temp0';
  }

  @override
  String get disputeDetailsTitle => 'Detalhes da disputa';

  @override
  String get disputeIdLabel => 'ID da disputa';

  @override
  String disputeReasonLabel(String reason) {
    return 'Motivo: $reason';
  }

  @override
  String get solverLabel => 'Mediador';

  @override
  String get serberoLabel => 'Serbero';

  @override
  String get disputeSerberoAssigned =>
      'Serbero, um assistente automático, está ajudando com a sua disputa. Ele fará algumas perguntas aqui e passará o caso para uma pessoa, se necessário.';

  @override
  String get disputeSolverTookOver => 'Um mediador assumiu a sua disputa.';

  @override
  String get disputeScreenTitle => 'Disputa';

  @override
  String get filtersDialogTitle => 'Filtros';

  @override
  String get resetButton => 'Redefinir';

  @override
  String get currencyLabel => 'Moeda';

  @override
  String get ratingLabel => 'Avaliação';

  @override
  String get applyButton => 'Aplicar';

  @override
  String get successLabel => 'Sucesso';

  @override
  String get copyButton => 'Copiar';

  @override
  String get shareButton => 'Compartilhar';

  @override
  String sendSatsToAddress(String sats) {
    return 'Envie $sats sats para:';
  }

  @override
  String get changeButton => 'Alterar';

  @override
  String get unableToOpenNotification =>
      'Não foi possível abrir os detalhes da notificação.';

  @override
  String get reasonBestPremium => 'Melhor prêmio';

  @override
  String get reasonMostReputable => 'Maior reputação';

  @override
  String get marketPriceCaption => 'Preço de mercado';

  @override
  String get sortNewest => 'Mais recentes';

  @override
  String ordersCount(int count) {
    final intl.NumberFormat countNumberFormat = intl
        .NumberFormat.decimalPattern(localeName);
    final String countString = countNumberFormat.format(count);

    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$countString ordens',
      one: '1 ordem',
      zero: '0 ordens',
    );
    return '$_temp0';
  }

  @override
  String get sortBestPremium => 'Melhor prêmio';

  @override
  String get sortBestReputation => 'Melhor reputação';

  @override
  String get sortSheetTitle => 'Ordenar por';

  @override
  String get orderCardPremiumCaption => 'prêmio';

  @override
  String get orderCardPriceCaption => 'preço';

  @override
  String orderFixedAmount(String sats) {
    return 'Valor fixo · por $sats';
  }

  @override
  String get reputationNew => 'Novo';

  @override
  String get bottomNavBook => 'Livro';

  @override
  String get bottomNavTrades => 'Operações';

  @override
  String get fabDismissHint => 'Toque fora para fechar';

  @override
  String get addOrderFabLabel => 'Criar ordem';

  @override
  String get ordersEmptyHint =>
      'Novas ordens aparecem aqui assim que são publicadas.';

  @override
  String get ordersEmptyFilteredHint =>
      'Nenhuma ordem corresponde aos seus filtros.';

  @override
  String get clearFiltersButton => 'Limpar filtros';

  @override
  String get hideEarlierEvents => 'Ocultar eventos anteriores';

  @override
  String viewEarlierEvents(int count) {
    final intl.NumberFormat countNumberFormat = intl
        .NumberFormat.decimalPattern(localeName);
    final String countString = countNumberFormat.format(count);

    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Ver $countString eventos anteriores',
      one: 'Ver 1 evento anterior',
      zero: 'Ver $countString eventos anteriores',
    );
    return '$_temp0';
  }

  @override
  String get goToTrade => 'Ir para a operação';

  @override
  String get disputeWord => 'Disputa';

  @override
  String get tradeWord => 'Operação';

  @override
  String get notifSectionRecent => 'Recentes';

  @override
  String notificationDeletedSnack(int count) {
    final intl.NumberFormat countNumberFormat = intl
        .NumberFormat.decimalPattern(localeName);
    final String countString = countNumberFormat.format(count);

    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$countString notificações excluídas',
      one: 'Notificação excluída',
      zero: '$countString notificações excluídas',
    );
    return '$_temp0';
  }

  @override
  String get notificationDeletedUndo => 'Desfazer';

  @override
  String get payingStatus => 'Pagando…';

  @override
  String get payWithWalletButton => 'Pagar com carteira';

  @override
  String get generatingInvoiceNwc => 'Gerando fatura via NWC…';

  @override
  String get unableToGenerateInvoice =>
      'Não foi possível gerar a fatura automaticamente';

  @override
  String get avatarIconLabel => 'Ícone de avatar';

  @override
  String get disputeDescResolvedBuyerFavour =>
      'Disputa resolvida a favor do comprador';

  @override
  String get disputeDescResolvedYourFavour => 'Disputa resolvida a seu favor';

  @override
  String get disputeDescResolvedSellerFavour =>
      'Disputa resolvida a favor do vendedor';

  @override
  String get disputeDescCooperativeCancel =>
      'Ordem cancelada de forma cooperativa';

  @override
  String get disputeDescResolved => 'Disputa resolvida';

  @override
  String get disputeDescYouOpened => 'Você abriu esta disputa';

  @override
  String get disputeDescCounterpartOpened =>
      'Sua contraparte abriu esta disputa';

  @override
  String get notificationsBellNoUnread => 'Notificações, nenhuma não lida';

  @override
  String get notificationsBellBackupActive =>
      'Notificações, lembrete de backup ativo';

  @override
  String notificationsBellUnread(int count) {
    final intl.NumberFormat countNumberFormat = intl
        .NumberFormat.decimalPattern(localeName);
    final String countString = countNumberFormat.format(count);

    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Notificações, $countString não lidas',
      one: 'Notificações, 1 não lida',
      zero: 'Notificações, $countString não lidas',
    );
    return '$_temp0';
  }

  @override
  String drawerBadgeNewCount(int count) {
    final intl.NumberFormat countNumberFormat = intl
        .NumberFormat.decimalPattern(localeName);
    final String countString = countNumberFormat.format(count);

    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$countString novos',
      one: '1 novo',
      zero: '$countString novos',
    );
    return '$_temp0';
  }

  @override
  String get bondSlashedViewPolicy => 'Ver política';

  @override
  String get bondSlashedViewTrade => 'Ver operação';

  @override
  String bondSlashedTradeNoticeDispute(String sats) {
    return 'O nó confiscou seu depósito de $sats sats nesta disputa.';
  }

  @override
  String bondSlashedTradeNoticeTimeout(String sats) {
    return 'O nó confiscou seu depósito de $sats sats porque o prazo de uma etapa expirou.';
  }

  @override
  String get bondSlashedTitle => 'Depósito confiscado';

  @override
  String bondSlashedMessageTimeout(String amount, String orderId) {
    return 'Seu depósito antiabuso de $amount sats para a ordem $orderId foi confiscado porque o tempo de espera se esgotou. O status da sua ordem não mudou.';
  }

  @override
  String bondSlashedMessageDispute(String amount, String orderId) {
    return 'Seu depósito antiabuso de $amount sats para a ordem $orderId foi confiscado após a resolução de uma disputa. O status da sua ordem não mudou.';
  }

  @override
  String get bondSlashedCauseTimeout => 'Tempo de espera esgotado';

  @override
  String get bondSlashedCauseDispute => 'Resolução de disputa';

  @override
  String get bondSlashedDetailOrder => 'Ordem';

  @override
  String get bondSlashedDetailAmount => 'Valor do depósito';

  @override
  String get bondSlashedDetailCause => 'Motivo';

  @override
  String get bondSlashedDetailFiat => 'Fiat';

  @override
  String get bondSlashedDetailPaymentMethod => 'Método de pagamento';

  @override
  String aboutDaysValue(int count) {
    final intl.NumberFormat countNumberFormat = intl
        .NumberFormat.decimalPattern(localeName);
    final String countString = countNumberFormat.format(count);

    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$countString dias',
      one: '$countString dia',
      zero: '$countString dias',
    );
    return '$_temp0';
  }

  @override
  String get aboutCashuEscrowSection => 'Custódia Cashu';

  @override
  String get aboutCashuMintUrlLabel => 'Mint';

  @override
  String get aboutCashuLocktimeLabel => 'Prazo de bloqueio da custódia';

  @override
  String get aboutCashuSettlementMarginLabel => 'Margem de liquidação';

  @override
  String get escrowModeLightning => 'Lightning';

  @override
  String get escrowModeCashu => 'Cashu';

  @override
  String get escrowModeUnknown => 'Não anunciado';

  @override
  String get settingsEscrowOverrideTitle =>
      'Backend de custódia (desenvolvedor)';

  @override
  String get settingsEscrowOverrideSubtitle =>
      'Teste o Cashu com um nó que ainda não o anuncia. Apenas em builds de depuração.';

  @override
  String get settingsForceCashuLabel => 'Forçar custódia Cashu';

  @override
  String get settingsCashuMintOverrideLabel => 'URL alternativa do mint';

  @override
  String get settingsCashuMintOverrideApply => 'Aplicar';

  @override
  String get settingsCashuMintOverrideInvalid =>
      'Essa não é uma URL de mint válida. Use http ou https com um host.';

  @override
  String settingsEscrowEffectiveMode(String mode) {
    return 'Backend em uso: $mode';
  }

  @override
  String settingsEscrowEffectiveMint(String mint) {
    return 'Mint em uso: $mint';
  }

  @override
  String get settingsEscrowCashuUnavailable =>
      'O Cashu não funciona sem um mint — defina um abaixo.';

  @override
  String get tradeStatusPayoutPending => 'Pagamento pendente';

  @override
  String get tradeHeadlinePayoutPending => 'Aguardando seus sats';

  @override
  String get tradeInstructionPayoutPending =>
      'O vendedor liberou seus sats e o Mostro os envia para você. Se o pagamento falhar, você pode adicionar uma nova fatura Lightning.';

  @override
  String get tradeScreenTitle => 'Sua operação';

  @override
  String get tradeChipWaiting => 'AGUARDANDO';

  @override
  String get tradeChipActive => 'ATIVA';

  @override
  String get tradeChipYourTurn => 'SUA VEZ';

  @override
  String get tradeChipDispute => 'DISPUTA';

  @override
  String get tradeChatLockedNote =>
      'Ainda não há chat: até a operação ficar ativa, nenhuma das partes sabe quem é a outra.';

  @override
  String get tradeChatEncrypted => 'Criptografado de ponta a ponta';

  @override
  String get tradeChatClosed => 'Conversa encerrada · ver mensagens';

  @override
  String get tradeChatWithBuyer => 'Chat com o comprador';

  @override
  String get tradeChatWithSeller => 'Chat com o vendedor';

  @override
  String get tradeChatWithCounterpart => 'Chat com sua contraparte';

  @override
  String tradeChatNewMessages(int count) {
    final intl.NumberFormat countNumberFormat = intl
        .NumberFormat.decimalPattern(localeName);
    final String countString = countNumberFormat.format(count);

    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$countString novas mensagens',
      one: '1 nova mensagem',
      zero: '$countString novas mensagens',
    );
    return '$_temp0';
  }

  @override
  String get tradeChatOpen => 'Abrir';

  @override
  String get tradeChatClosedAnnouncement =>
      'A conversa foi encerrada. Você ainda pode ler as mensagens';

  @override
  String get tradeBodyWaitingPaymentBuyer =>
      'O vendedor está pagando a fatura que bloqueia os sats. Assim que estiverem bloqueados, é a sua vez de pagar.';

  @override
  String tradeBodyActiveSeller(String method) {
    return 'Envie seus dados de $method pelo chat acima.';
  }

  @override
  String tradeBodyActiveBuyer(String method) {
    return 'Por $method, com os dados que o vendedor enviou no chat. Depois de enviar, marque abaixo.';
  }

  @override
  String tradeBodyFiatSentSeller(String method) {
    return 'O comprador marcou o pagamento como enviado. Confira sua conta de $method antes de liberar.';
  }

  @override
  String tradeBodyActiveBuyerStablecoin(String method) {
    return 'Envie por $method, para o endereço que o vendedor enviou no chat: em outra rede, pode se perder. Depois cole o ID da transação no chat (é sua prova em uma disputa) e marque abaixo.';
  }

  @override
  String tradeBodyActiveSellerStablecoin(String method) {
    return 'Envie seu endereço de $method pelo chat acima.';
  }

  @override
  String tradeBodyFiatSentSellerStablecoin(String method) {
    return 'O comprador marcou o pagamento como enviado. Antes de liberar, confira se ele chegou ao seu endereço de $method, com o ID da transação do chat.';
  }

  @override
  String get tradeReleaseIrreversible =>
      'A liberação dos sats não pode ser desfeita.';

  @override
  String get tradeTimerYouHave => 'Você tem';

  @override
  String get tradeTimerTheyHave => 'A contraparte tem';

  @override
  String get tradeTimerOrderHas => 'Tempo restante';

  @override
  String get tradeRoleBuyer => 'Comprador';

  @override
  String get tradeRoleSeller => 'Vendedor';

  @override
  String get tradeFiatSentAction => 'Já enviei o pagamento';

  @override
  String get tradeCloseAction => 'Fechar';

  @override
  String get tradeSendRatingAction => 'Enviar avaliação';

  @override
  String get tradeCompletedTitle => 'Operação concluída';

  @override
  String tradeRatedCounterpart(String alias, String score) {
    return 'Você avaliou $alias com $score';
  }

  @override
  String get tradeIdLabel => 'ID';

  @override
  String tradeCreatedTodayLabel(String time) {
    return 'criada hoje às $time';
  }

  @override
  String get releaseSheetTitle => 'Liberar os sats?';

  @override
  String get releaseSheetBody =>
      'Isso não pode ser desfeito. Só libere quando o dinheiro estiver na sua conta.';

  @override
  String get releaseSheetConfirm => 'Sim, liberar';

  @override
  String get releaseSheetBack => 'Voltar';

  @override
  String get orderSideChipSell => 'Vendendo BTC';

  @override
  String get orderSideChipBuy => 'Comprando BTC';

  @override
  String orderDetailMarketPremium(String premium) {
    return 'Preço de mercado · prêmio de $premium';
  }

  @override
  String myOrderWaitingNote(String ago) {
    return 'Publicada $ago. Avisaremos você assim que alguém a aceitar: pode fechar esta tela.';
  }

  @override
  String get orderStatusTakenWaitingInvoice => 'Aceita · aguardando fatura';

  @override
  String get orderStatusTakenWaitingPayment => 'Aceita · aguardando pagamento';

  @override
  String get orderDetailCreatedLabel => 'Criada';

  @override
  String get orderDetailIdLabel => 'ID';

  @override
  String paymentMethodsMore(String first, int count) {
    return '$first +$count';
  }

  @override
  String get paymentMethodsSheetTitle => 'Métodos de pagamento';

  @override
  String get cancelOrderSheetTitle => 'Cancelar a ordem?';

  @override
  String get cancelOrderSheetBody =>
      'Ela será removida do livro de ordens, e isso não pode ser desfeito.';

  @override
  String get goBackButtonLabel => 'Voltar';

  @override
  String get takeOrderYouPay => 'Você paga';

  @override
  String get takeOrderYouReceive => 'Você recebe';

  @override
  String get takeOrderYouSend => 'Você envia';

  @override
  String takeOrderSatsFrom(String sats) {
    return 'a partir de $sats';
  }

  @override
  String takeOrderMarketFooter(String premium) {
    return 'Preço de mercado · prêmio de $premium. O valor final é definido quando você a aceitar.';
  }

  @override
  String takeOrderFixedFooterSeller(String sats) {
    return 'Valor fixo · o vendedor pede $sats';
  }

  @override
  String takeOrderFixedFooterBuyer(String sats) {
    return 'Valor fixo · o comprador oferece $sats';
  }

  @override
  String get counterpartySeller => 'Vendedor';

  @override
  String get counterpartyBuyer => 'Comprador';

  @override
  String get takeOrderPayWithLabel => 'Você paga via';

  @override
  String get takeOrderPaidWithLabel => 'Você recebe via';

  @override
  String get takeOrderPublishedLabel => 'Publicada';

  @override
  String get takeOrderNoteBuyer =>
      'Ao aceitá-la, o vendedor bloqueia os sats no Mostro. Você só paga depois que eles estiverem bloqueados.';

  @override
  String get takeOrderNoteSeller =>
      'Ao aceitá-la, você bloqueia os sats no Mostro. O comprador paga depois.';

  @override
  String get takeOrderButton => 'Aceitar ordem';

  @override
  String get takeOrderTaking => 'Aceitando…';

  @override
  String get takeOrderUnavailable => 'Não está mais disponível';

  @override
  String get takeOrderFailed =>
      'Não foi possível aceitar a ordem. Tente novamente.';

  @override
  String get takeOrderClosed => 'Encerrada';

  @override
  String get easterEggWhitepaper =>
      '31 de outubro de 2008: nove páginas, sem pedir permissão a ninguém. Feliz Halloween.';

  @override
  String get easterEggGenesis =>
      'The Times 03/Jan/2009 Chancellor on brink of second bailout for banks';

  @override
  String get easterEggPizzaDay =>
      '22 de maio de 2010: 10.000 BTC por duas pizzas. Espero que estivessem boas.';

  @override
  String get settingsGroupApp => 'Aplicativo';

  @override
  String get settingsGroupPayments => 'Pagamentos';

  @override
  String get settingsGroupNetwork => 'Rede';

  @override
  String get settingsGroupHelp => 'Ajuda';

  @override
  String get fiatCurrencySettingTitle => 'Moeda fiat';

  @override
  String notificationsEnabledOfTotal(int count, int total) {
    return '$count de $total';
  }

  @override
  String get notificationsAllOff => 'Desativadas';

  @override
  String get lightningAddressUnset => 'Não definido';

  @override
  String get nwcWalletNotConnected => 'Não conectada';

  @override
  String relaysConnectedOfTotal(int connected, int total) {
    return '$connected de $total conectados';
  }

  @override
  String get relaysSummaryHealthy =>
      'Você recebe ordens e mensagens normalmente';

  @override
  String get relaysSummaryAtRisk => 'Você pode deixar de ver novas ordens';

  @override
  String get relayStatusConnected => 'Conectado';

  @override
  String get relayStatusOffline => 'Sem conexão';

  @override
  String get addRelayButtonLabel => 'Adicionar relay';

  @override
  String get relaysFootnote =>
      'Os relays transportam suas ordens e mensagens. Com menos de dois conectados, você pode deixar de ver novas ordens.';

  @override
  String get lastRelayBlockedMessage =>
      'Mantenha pelo menos um relay ativo: sem relays, você não consegue ver nem publicar ordens.';

  @override
  String get nwcExplainerTitle => 'Conecte sua carteira';

  @override
  String get nwcExplainerSubtitle => 'Com Nostr Wallet Connect';

  @override
  String get nwcExplainerBody =>
      'O Mostro vai usar esta carteira para receber e pagar as faturas das suas operações, para você nunca precisar copiar uma fatura à mão.';

  @override
  String get nwcUriFieldLabel => 'URI de conexão';

  @override
  String get nwcUriPlaceholder => 'nostr+walletconnect://…';

  @override
  String get nwcStorageFootnote =>
      'A URI fica salva só neste dispositivo e nunca é publicada no Nostr.';

  @override
  String get walletConnectedMessage => 'Carteira conectada';

  @override
  String get nwcConnectedStatus => 'Conectada';

  @override
  String nwcBalanceSats(String sats) {
    return '$sats sats';
  }

  @override
  String get notificationsSystemDenied =>
      'As notificações estão desativadas nas configurações do sistema.';

  @override
  String get openSystemSettingsAction => 'Abrir configurações';

  @override
  String get notificationsPermissionNotAsked =>
      'Este navegador ainda não tem permissão para mostrar notificações.';

  @override
  String get allowNotificationsAction => 'Permitir notificações';

  @override
  String get notificationsPrivacyFootnote =>
      'As notificações não trazem valores nem contrapartes. Um push passa pelos servidores do Google ou da Apple e só diz que há algo para ver.';

  @override
  String get pushMasterToggleTitle => 'Notificações push';

  @override
  String get pushMasterToggleSubtitle =>
      'Acorda o app quando chega uma atualização de operação ou uma mensagem de chat. A notificação em si não traz nada.';

  @override
  String get pushWebStopsWithTab =>
      'Deixa de funcionar de 30 a 48 h depois da última vez que esta aba executou o Mostro';

  @override
  String get pushStatusOff =>
      'Desativadas — nada está registrado no servidor push';

  @override
  String pushStatusCleanupPending(int count) {
    final intl.NumberFormat countNumberFormat = intl
        .NumberFormat.decimalPattern(localeName);
    final String countString = countNumberFormat.format(count);

    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Desativadas — remoção pendente de $countString registros push',
      one: 'Desativadas — remoção pendente de 1 registro push',
      zero: 'Desativadas — remoção pendente de $countString registros push',
    );
    return '$_temp0';
  }

  @override
  String get pushStatusNoToken => 'Aguardando o token push deste dispositivo';

  @override
  String get pushStatusIdle =>
      'Ativadas — nenhuma operação aberta para registrar';

  @override
  String pushStatusRegistered(int count) {
    final intl.NumberFormat countNumberFormat = intl
        .NumberFormat.decimalPattern(localeName);
    final String countString = countNumberFormat.format(count);

    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Registrado para $countString operações',
      one: 'Registrado para 1 operação',
      zero: 'Registrado para $countString operações',
    );
    return '$_temp0';
  }

  @override
  String pushStatusLastRegistered(String ago) {
    return 'último registro $ago';
  }

  @override
  String get pushStatusUnreachable =>
      'Servidor push inacessível — tentando novamente';

  @override
  String get pushStatusNodeRefused =>
      'Este nó Mostro não é aceito pelo servidor push';

  @override
  String get pushStatusRateLimited =>
      'Limite de solicitações push atingido — tentando novamente em breve';

  @override
  String get pushUnsupportedPlatform =>
      'Notificações push não estão disponíveis nesta plataforma';

  @override
  String get pushToggleSaveFailed =>
      'Não foi possível alterar as notificações push';

  @override
  String get pushNewMessageBody => 'Você tem uma nova mensagem';

  @override
  String get notificationPrefSaveFailed =>
      'Não foi possível salvar essa preferência';

  @override
  String get logsScreenTitle => 'Logs';

  @override
  String get logFilterAll => 'Todos';

  @override
  String get logFilterRelays => 'Relays';

  @override
  String get logFilterOrders => 'Ordens';

  @override
  String get logFilterPayments => 'Pagamentos';

  @override
  String get verboseLoggingTitle => 'Logs detalhados';

  @override
  String get verboseLoggingSubtitle => 'Mais detalhes, mais bateria';

  @override
  String get newLogsChipLabel => 'Novos logs';

  @override
  String get noLogsForFilter => 'Nenhuma entrada para este filtro';

  @override
  String get aboutAppSection => 'Aplicativo';

  @override
  String get aboutSourceCodeLabel => 'Código-fonte';

  @override
  String get aboutUserGuideLabel => 'Guia do usuário';

  @override
  String get aboutTechnicalDocsLabel => 'Documentação técnica';

  @override
  String get aboutLanguageSpanish => 'Espanhol';

  @override
  String get aboutLanguageEnglish => 'Inglês';

  @override
  String get aboutConnectedNodeTitle => 'Nó conectado';

  @override
  String get aboutMinOrderCell => 'Ordem mínima';

  @override
  String get aboutMaxOrderCell => 'Ordem máxima';

  @override
  String get aboutFeeCell => 'Taxa';

  @override
  String aboutFeeValue(String value) {
    return '$value%';
  }

  @override
  String get aboutNodeDepositNone => 'Não';

  @override
  String aboutNodeDepositFloor(String amount) {
    return 'mín. $amount sats';
  }

  @override
  String get aboutDepositCell => 'Depósito';

  @override
  String get aboutCurrenciesCell => 'Moedas';

  @override
  String get aboutOrderExpiryCell => 'Expiração';

  @override
  String get aboutNodeTechnicalDataRow => 'Dados técnicos do nó';

  @override
  String aboutFieldCount(int count) {
    final intl.NumberFormat countNumberFormat = intl
        .NumberFormat.decimalPattern(localeName);
    final String countString = countNumberFormat.format(count);

    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$countString campos',
      one: '$countString campo',
      zero: '$countString campos',
    );
    return '$_temp0';
  }

  @override
  String get aboutTechnicalDataTitle => 'Dados técnicos';

  @override
  String get aboutPublicKeyLabel => 'Chave pública';

  @override
  String get aboutOrderExpiryLabel => 'Expiração da ordem';

  @override
  String get aboutWaitingTimeoutLabel => 'Tempo limite de espera';

  @override
  String aboutHoursShort(int count) {
    return '$count h';
  }

  @override
  String aboutSecondsShort(int count) {
    return '$count s';
  }

  @override
  String get aboutAliasLabel => 'Alias';

  @override
  String get aboutNodePublicKeyLabel => 'Chave pública do nó';

  @override
  String get aboutNodeUriLabel => 'URI do nó';

  @override
  String get aboutCommitLabel => 'Commit';

  @override
  String get aboutChainNetworkLabel => 'Cadeia e rede';

  @override
  String get aboutTechnicalFootnote =>
      'Estes dados identificam o nó com o qual você opera. Úteis para suporte ou para verificá-lo antes de enviar fundos.';

  @override
  String get aboutCopyAllData => 'Copiar todos os dados';

  @override
  String get tradesGroupNeedsAction => 'Precisam da sua ação';

  @override
  String get tradesGroupInProgress => 'Em andamento';

  @override
  String get tradesGroupClosed => 'Encerradas';

  @override
  String get tradesDirectionSell => 'Você vende';

  @override
  String get tradesDirectionBondClaim => 'Resgate de depósito';

  @override
  String get tradesDirectionBuy => 'Você compra';

  @override
  String tradesCounterpartyTo(String handle) {
    return 'para $handle';
  }

  @override
  String tradesCounterpartyFrom(String handle) {
    return 'de $handle';
  }

  @override
  String get tradeListChipYourTurn => 'Sua vez';

  @override
  String get tradeListChipPublished => 'Publicada';

  @override
  String get tradeListChipInProgress => 'Em andamento';

  @override
  String get tradeListChipWaitingInvoice => 'Aguardando fatura';

  @override
  String get tradeListChipWaitingPayment => 'Aguardando pagamento';

  @override
  String get tradeListChipWaitingSats => 'Aguardando sats';

  @override
  String get tradeListChipDispute => 'Em disputa';

  @override
  String get tradeListChipCompleted => 'Concluída';

  @override
  String get tradeListChipCancelled => 'Cancelada';

  @override
  String get tradeListChipExpired => 'Expirada';

  @override
  String get tradeVerbAddInvoice => 'Adicionar fatura';

  @override
  String get tradeVerbPayBond => 'Pagar depósito';

  @override
  String get tradeHeadlineWaitingBond => 'Bloqueie seu depósito para continuar';

  @override
  String get tradeInstructionWaitingBond =>
      'O nó mantém sua aceitação pendente até o depósito reembolsável ser pago. Enquanto isso, a ordem continua aberta para outros.';

  @override
  String get takeOrderBondNotice =>
      'Este nó pede que quem aceita a ordem bloqueie antes um depósito reembolsável; ele é devolvido quando a operação termina de forma honesta.';

  @override
  String takeOrderBondNoticeEstimate(String sats) {
    return 'Este nó pede que quem aceita a ordem bloqueie antes um depósito reembolsável de ≈ $sats sats; ele é devolvido quando a operação termina de forma honesta.';
  }

  @override
  String get tradeVerbPayInvoice => 'Pagar fatura';

  @override
  String get tradeVerbSendPayment => 'Enviar pagamento';

  @override
  String get tradeVerbReleaseSats => 'Liberar sats';

  @override
  String get tradeVerbRate => 'Avaliar';

  @override
  String get tradeListFilterAll => 'Todas';

  @override
  String get tradeListFilterActive => 'Ativas';

  @override
  String get tradeListFilterCompleted => 'Concluídas';

  @override
  String get tradeListFilterCancelled => 'Canceladas';

  @override
  String get tradeListFilterTitle => 'Mostrar operações';

  @override
  String get relativeTimeNow => 'agora';

  @override
  String relativeTimeMinutes(int count) {
    return 'há $count min';
  }

  @override
  String relativeTimeHours(int count) {
    return 'há $count h';
  }

  @override
  String get relativeTimeYesterday => 'ontem';

  @override
  String satsFigureEstimate(String sats) {
    return '≈ $sats sats';
  }

  @override
  String satsFigureExact(String sats) {
    return '$sats sats';
  }

  @override
  String get chatGroupActive => 'Operações ativas';

  @override
  String chatContextSellActive(String amount, String currency) {
    return 'Você vende $amount $currency';
  }

  @override
  String chatContextBuyActive(String amount, String currency) {
    return 'Você compra $amount $currency';
  }

  @override
  String chatContextSellClosed(String amount, String currency) {
    return 'Você vendeu $amount $currency';
  }

  @override
  String chatContextBuyClosed(String amount, String currency) {
    return 'Você comprou $amount $currency';
  }

  @override
  String get chatTurnAddInvoice => 'sua vez de adicionar a fatura';

  @override
  String get chatTurnPayBond => 'sua vez de pagar o depósito';

  @override
  String get chatTurnPayInvoice => 'sua vez de pagar a fatura';

  @override
  String get chatTurnSendPayment => 'sua vez de pagar';

  @override
  String get chatTurnRelease => 'sua vez de liberar';

  @override
  String get chatTurnRate => 'sua vez de avaliar';

  @override
  String get chatYouLabel => 'Você:';

  @override
  String get chatListFootnote =>
      'Cada conversa pertence a uma operação e tem criptografia de ponta a ponta. Quando a operação termina, ela continua aqui para leitura.';

  @override
  String get chatListEmptyTitle => 'Nenhuma conversa ainda';

  @override
  String get chatListEmptyBody =>
      'Um chat é aberto quando uma operação fica ativa.';

  @override
  String get chatClosedNotice =>
      'Esta operação terminou. A conversa continua aqui para leitura.';

  @override
  String disputeOpenedByYou(String time) {
    return 'Aberta por você $time';
  }

  @override
  String disputeOpenedByPeer(String time) {
    return 'Aberta pela contraparte $time';
  }

  @override
  String get invoiceReceiveTitle => 'Receba seus sats';

  @override
  String get invoiceLockTitle => 'Bloqueie seus sats';

  @override
  String get bondTitle => 'Depósito antiabuso';

  @override
  String get bondRefundableLabel => 'Depósito reembolsável';

  @override
  String get bondComesBack => 'volta para você quando a operação for concluída';

  @override
  String bondFiatComesBack(String fiat) {
    return '≈ $fiat · volta para você quando a operação for concluída';
  }

  @override
  String bondPaySemantics(String sats) {
    return 'Depósito reembolsável de $sats sats';
  }

  @override
  String bondReleasesIn(String time) {
    return 'A ordem volta a ficar disponível se você não pagar em $time';
  }

  @override
  String bondRowHeld(String bold) {
    return 'Os sats ficam $bold, não são gastos';
  }

  @override
  String get bondRowHeldBold => 'retidos na sua carteira';

  @override
  String bondRowReleased(String bold) {
    return 'Se a operação terminar bem, $bold';
  }

  @override
  String get bondRowReleasedBold => 'ele é liberado automaticamente';

  @override
  String bondRowLost(String bold) {
    return 'Você só o perde se houver uma disputa e $bold';
  }

  @override
  String bondRowLostTimeout(String bold) {
    return 'Você o perde se deixar uma etapa expirar, ou se houver uma disputa e $bold';
  }

  @override
  String get bondRowLostBold => 'você a perder';

  @override
  String get bondWhyTitle => 'Por que o Mostro pede um depósito';

  @override
  String get bondWhyCustody =>
      'O Mostro não guarda fundos, então não pode punir quem abandona uma operação; o depósito cumpre esse papel e protege todos os usuários contra golpistas.';

  @override
  String get bondWhyHold =>
      'Sua carteira retém os sats sem enviá-los; quando a operação é concluída, eles são liberados automaticamente.';

  @override
  String get bondWhyDispute =>
      'Se você abrir uma disputa e ganhar, também o recebe de volta. Ele só é cobrado quando você perde uma disputa.';

  @override
  String get bondWhyDisputeTimeout =>
      'Se você abrir uma disputa e ganhar, também o recebe de volta. Ele só é cobrado quando você perde uma disputa ou deixa uma etapa de espera expirar.';

  @override
  String get bondReadDocs => 'Ler a documentação';

  @override
  String get bondContextOrder => 'Ordem';

  @override
  String bondContextBuy(String fiat) {
    return 'Você compra $fiat';
  }

  @override
  String bondContextSell(String fiat) {
    return 'Você vende $fiat';
  }

  @override
  String get bondContextEquals => 'Depósito equivale a';

  @override
  String bondContextPercent(String pct) {
    return '$pct% do valor';
  }

  @override
  String get bondDontPublish => 'Não publicar a ordem';

  @override
  String get bondAbandoned =>
      'Ordem descartada. Nada foi publicado e nada foi cobrado.';

  @override
  String bondPublishesIn(String time) {
    return 'Ainda não publicada: a ordem é descartada se você não pagar em $time';
  }

  @override
  String get bondInvoiceMissingMaker =>
      'Este dispositivo não tem uma cópia da fatura do depósito, e o nó não a reenvia para uma ordem criada por você. Descarte a ordem e crie-a novamente.';

  @override
  String get bondExpiredBodyMaker =>
      'Ela não foi paga a tempo: a ordem nunca foi publicada e nenhum sat saiu da sua carteira.';

  @override
  String get bondExpiredNoticeMaker =>
      'A fatura do depósito expirou; a ordem não foi publicada';

  @override
  String get orderStatusWaitingBond =>
      'Aguardando seu depósito — ainda não publicada';

  @override
  String get bondAlreadyLocked =>
      'Seu depósito já foi pago, então a ordem está publicada. Cancele-a na tela da ordem.';

  @override
  String get bondCancelRefusedTitle => 'O nó não cancelou o depósito';

  @override
  String get bondCancelRefusedBody =>
      'Talvez este nó Mostro ainda não permita cancelar um depósito não pago, ou seu depósito acabou de ser pago. Se você não o pagou, pode remover a ordem deste dispositivo. Se a fatura for paga depois, a ordem ainda será publicada.';

  @override
  String get bondRemoveFromDevice => 'Remover deste dispositivo';

  @override
  String get bondLeaveMakerTitle => 'Não publicar esta ordem?';

  @override
  String get bondLeaveMakerBody =>
      'A ordem não será publicada e a fatura do depósito será cancelada.';

  @override
  String get bondLeaveTakerTitle => 'Não aceitar esta ordem?';

  @override
  String get bondLeaveTakerBody =>
      'A ordem continua no livro para outros e a fatura do depósito é cancelada.';

  @override
  String get bondKeepWaiting => 'Continuar aguardando';

  @override
  String createOrderBondNoticeEstimate(String sats) {
    return 'Este nó pede que você bloqueie um depósito reembolsável de ≈ $sats sats antes de a ordem ser publicada; ele é devolvido quando a operação termina de forma honesta.';
  }

  @override
  String get createOrderBondNotice =>
      'Este nó pede que você bloqueie um depósito reembolsável antes de a ordem ser publicada; ele é devolvido quando a operação termina de forma honesta.';

  @override
  String get bondClaimTitle => 'Resgate sua parte';

  @override
  String get bondClaimShareLabel => 'Sua parte';

  @override
  String bondClaimShareSemantics(String sats) {
    return 'Parte de $sats sats a resgatar';
  }

  @override
  String bondClaimContext(String context) {
    return 'Da operação de $context';
  }

  @override
  String bondClaimDeadline(String date) {
    return 'Resgate antes de $date';
  }

  @override
  String get bondClaimExplainer =>
      'O depósito da sua contraparte foi confiscado a seu favor. Adicione uma fatura de exatamente este valor e o nó vai pagá-la para você.';

  @override
  String get bondClaimFieldLabel => 'Fatura Lightning';

  @override
  String get bondClaimFieldHint => 'lnbc… exatamente no valor da parte';

  @override
  String get bondClaimSubmit => 'Enviar fatura';

  @override
  String get bondClaimSent => 'Fatura enviada ao nó';

  @override
  String get bondClaimSubmittedTitle => 'Fatura enviada';

  @override
  String get bondClaimSubmittedBody => 'Aguardando a confirmação do nó.';

  @override
  String get bondClaimAcknowledgedTitle => 'Pagamento em andamento';

  @override
  String get bondClaimAcknowledgedBody =>
      'O nó aceitou sua fatura e está pagando. Se o pagamento não encontrar uma rota, uma nova fatura será solicitada.';

  @override
  String get bondClaimCompletedTitle => 'Pago';

  @override
  String bondClaimCompletedBody(String sats) {
    return '$sats sats chegaram à sua carteira.';
  }

  @override
  String get bondClaimExpiredTitle => 'O prazo para resgatar terminou';

  @override
  String bondClaimExpiredBody(String date) {
    return 'Ele terminou em $date. A parte não pode mais ser resgatada.';
  }

  @override
  String get bondClaimMissing => 'Nenhum resgate encontrado para esta ordem.';

  @override
  String get bondClaimErrorAmount =>
      'A fatura deve ser exatamente no valor da parte indicada.';

  @override
  String get bondClaimErrorExpired =>
      'O prazo para resgatar terminou; a parte não pode mais ser resgatada.';

  @override
  String get bondClaimErrorRejected =>
      'O nó não aceitou a fatura. Tente outra.';

  @override
  String get bondClaimErrorNotClaimable =>
      'Este resgate não aceita uma fatura no momento.';

  @override
  String get bondClaimErrorNoKey =>
      'Este dispositivo não tem a chave dessa operação, então não pode resgatar a parte.';

  @override
  String get tradeVerbClaimPayout => 'Resgatar pagamento';

  @override
  String get chatTurnClaimPayout => 'sua vez de resgatar o pagamento';

  @override
  String get tradeBadgePayoutPending => 'Pagamento pendente';

  @override
  String get tradeBadgePayoutInProgress => 'Pagamento em andamento';

  @override
  String get tradeBadgePayoutPaid => 'Pagamento recebido';

  @override
  String bondBannerPendingTitle(String sats) {
    return '$sats sats estão prontos para voltar para você';
  }

  @override
  String bondBannerPendingBody(String sats) {
    return 'O depósito da sua contraparte foi confiscado a seu favor. Adicione qualquer fatura Lightning de $sats sats para resgatá-lo.';
  }

  @override
  String get bondBannerAddInvoice => 'Adicionar fatura de pagamento';

  @override
  String get bondBannerView => 'Ver resgate';

  @override
  String get bondBannerInProgressTitle => 'Pagamento em andamento';

  @override
  String bondBannerInProgressBody(String sats) {
    return 'O nó está pagando sua parte de $sats sats.';
  }

  @override
  String get bondBannerPaidTitle => 'Pagamento recebido';

  @override
  String bondBannerPaidBody(String sats, String date) {
    return '$sats sats foram pagos a você em $date.';
  }

  @override
  String bondBannerExpired(String date) {
    return 'O prazo para resgatar o depósito da sua contraparte terminou em $date.';
  }

  @override
  String get bondClaimNewTitle => 'Pagamento de depósito para resgatar';

  @override
  String bondClaimNewMessage(String sats) {
    return 'Você pode resgatar $sats sats de um depósito confiscado. Adicione uma fatura Lightning para recebê-los.';
  }

  @override
  String get bondClaimPaidTitle => 'Pagamento de depósito recebido';

  @override
  String bondClaimPaidMessage(String sats) {
    return 'Pagamento de depósito de $sats sats recebido.';
  }

  @override
  String get bondDontTake => 'Não aceitar a ordem';

  @override
  String get bondLockedNowEscrow =>
      'Depósito bloqueado. Agora bloqueie o valor da operação.';

  @override
  String get bondLostRace =>
      'Outro usuário aceitou esta ordem antes de o seu depósito ser pago';

  @override
  String get bondMakerCanceled => 'O criador cancelou esta ordem';

  @override
  String get bondExpiredNotice =>
      'A fatura do depósito expirou; a ordem voltou para o livro';

  @override
  String get bondExpiredTitle => 'A fatura do depósito expirou';

  @override
  String get bondExpiredBody =>
      'Ela não foi paga a tempo: a ordem voltou para o livro e nenhum sat saiu da sua carteira.';

  @override
  String get bondInvoiceMissing =>
      'Este dispositivo não tem uma cópia da fatura do depósito. Peça-a novamente ao nó para continuar aceitando a ordem.';

  @override
  String get bondRequestAgain => 'Solicitar a fatura novamente';

  @override
  String get bondRequestFailed => 'O nó não reenviou a fatura do depósito';

  @override
  String get invoiceYouReceiveLabel => 'Você vai receber';

  @override
  String get invoiceToPayLabel => 'A pagar';

  @override
  String invoiceReceiveSemantics(String sats) {
    return '$sats satoshis a receber';
  }

  @override
  String invoicePaySemantics(String sats) {
    return '$sats satoshis a pagar';
  }

  @override
  String invoiceFeeIncluded(String sats) {
    return 'Inclui $sats sats de taxa do Mostro';
  }

  @override
  String invoiceTimeToSend(String time) {
    return 'Você tem $time para enviá-la';
  }

  @override
  String invoiceExpiresIn(String time) {
    return 'A fatura expira em $time';
  }

  @override
  String get invoiceFieldHint => 'lnbc… ou usuario@dominio';

  @override
  String get invoiceFieldPromptLabel => 'Cole sua fatura aqui';

  @override
  String get invoiceFieldFilledLabel => 'Fatura Lightning';

  @override
  String get invoiceFieldAddressLabel => 'Endereço Lightning';

  @override
  String get invoiceScanButton => 'Escanear';

  @override
  String get invoiceReplaceButton => 'Substituir';

  @override
  String get invoiceFieldSemantics =>
      'Fatura ou endereço Lightning, obrigatório';

  @override
  String invoiceFilledSemantics(String sats) {
    return 'Fatura Lightning de $sats sats';
  }

  @override
  String get invoiceValidAddress =>
      'Endereço válido · a fatura será solicitada no envio';

  @override
  String invoiceValidInvoice(String sats) {
    return 'Fatura válida · $sats sats';
  }

  @override
  String invoiceErrorWrongAmount(String actual, String expected) {
    return 'A fatura é de $actual sats, deve ser de $expected';
  }

  @override
  String get invoiceErrorExpired => 'A fatura já expirou';

  @override
  String invoiceErrorExpiresTooSoon(String minutes) {
    return 'A fatura expira em menos de $minutes minutos; o nó precisa de mais tempo para pagá-la';
  }

  @override
  String get invoiceErrorMalformed =>
      'Esta fatura está incompleta ou com erro de digitação';

  @override
  String get invoiceErrorUnrecognized =>
      'Não é uma fatura (lnbc…) nem um endereço Lightning (usuario@dominio)';

  @override
  String get invoiceSellerLabel => 'Vendedor';

  @override
  String get invoiceBuyerLabel => 'Comprador';

  @override
  String get invoiceYouPayLabel => 'Você paga';

  @override
  String get invoiceYouGetLabel => 'Você recebe';

  @override
  String get invoiceSendButton => 'Enviar fatura';

  @override
  String get invoiceCancelTrade => 'Cancelar operação';

  @override
  String get invoiceOpenWallet => 'Abrir na minha carteira';

  @override
  String get invoiceHoldNote =>
      'Os sats ficam retidos: eles não saem da sua carteira até você confirmar o pagamento do comprador.';

  @override
  String invoiceQrSemantics(String invoice) {
    return 'Código QR da fatura Lightning: $invoice';
  }

  @override
  String get invoiceBackToBook => 'Voltar ao livro de ordens';

  @override
  String get invoiceStepElapsed =>
      'O tempo acabou. O Mostro vai encerrar esta etapa em breve, a menos que ela seja concluída.';

  @override
  String get stepElapsedBackToBook =>
      'O tempo acabou. Se a etapa não for concluída, o Mostro vai devolver a ordem ao livro em breve.';

  @override
  String get stepElapsedCancelled =>
      'O tempo acabou. Se a etapa não for concluída, o Mostro vai cancelar a ordem em breve.';

  @override
  String invoiceErrorWrongNetwork(String invoice, String node) {
    return 'A fatura é da rede $invoice, o nó usa $node';
  }

  @override
  String invoiceCountdownHours(String hours, String minutes) {
    return '$hours h $minutes';
  }

  @override
  String get countdownExpiresInLabel => 'Expira em';

  @override
  String get bondPayWithinLabel => 'Prazo para pagar';

  @override
  String get tradeCardWaitingBuyerInvoiceTitle =>
      'Aguardando a fatura do comprador';

  @override
  String get tradeCardWaitingBuyerInvoiceMessage =>
      'A operação continua quando o comprador adicionar uma fatura Lightning.';

  @override
  String get tradeCardWaitingPaymentTitle =>
      'Aguardando o pagamento do vendedor';

  @override
  String get tradeCardWaitingPaymentMessage =>
      'A operação continua quando o vendedor bloquear os sats.';

  @override
  String get tradeCardWaitingTakerBondTitle => 'Pagamento do depósito pendente';

  @override
  String get tradeCardWaitingTakerBondMessage =>
      'O depósito antiabuso de quem aceitou a ordem precisa ser pago antes de a operação começar.';

  @override
  String get tradeCardActiveTitle => 'Operação ativa';

  @override
  String get tradeCardActiveMessage =>
      'Os sats estão bloqueados. O comprador já pode enviar o pagamento.';

  @override
  String get tradeCardFiatSentTitle => 'Pagamento marcado como enviado';

  @override
  String get tradeCardFiatSentMessage =>
      'O comprador marcou o pagamento como enviado.';

  @override
  String get tradeCardSettledHoldInvoiceTitle => 'Sats liberados';

  @override
  String get tradeCardSettledHoldInvoiceMessage =>
      'O vendedor liberou os sats. O pagamento do comprador está a caminho.';

  @override
  String get tradeCardSuccessTitle => 'Operação concluída';

  @override
  String get tradeCardSuccessMessage => 'A operação foi concluída com sucesso.';

  @override
  String get tradeCardCanceledTitle => 'Operação cancelada';

  @override
  String get tradeCardCanceledMessage => 'A operação foi cancelada.';

  @override
  String get tradeCardExpiredTitle => 'Ordem expirada';

  @override
  String get tradeCardExpiredMessage =>
      'A ordem expirou antes que a operação pudesse continuar.';

  @override
  String get tradeCardCooperativelyCanceledTitle =>
      'Operação cancelada em comum acordo';

  @override
  String get tradeCardCooperativelyCanceledMessage =>
      'As duas partes concordaram em cancelar a operação.';

  @override
  String get tradeCardDisputeTitle => 'Disputa aberta';

  @override
  String get tradeCardDisputeMessage =>
      'Uma disputa foi aberta nesta operação.';

  @override
  String get tradeCardCanceledByAdminTitle => 'Cancelada pelo mediador';

  @override
  String get tradeCardCanceledByAdminMessage =>
      'O mediador da disputa cancelou a operação.';

  @override
  String get tradeCardSettledByAdminTitle => 'Resolvida pelo mediador';

  @override
  String get tradeCardSettledByAdminMessage =>
      'O mediador da disputa liberou os sats para o comprador.';

  @override
  String get tradeCardCompletedByAdminTitle => 'Concluída pelo mediador';

  @override
  String get tradeCardCompletedByAdminMessage =>
      'O mediador da disputa concluiu a operação.';

  @override
  String get tradeCardUpdatedTitle => 'Operação atualizada';

  @override
  String get tradeCardUpdatedMessage => 'O status desta operação mudou.';

  @override
  String get tradeCardCanceledByMakerMessage => 'O criador cancelou a ordem.';

  @override
  String get tradeCardCanceledBondLostRaceMessage =>
      'Outro usuário aceitou esta ordem antes de o depósito ser pago.';

  @override
  String get tradeCardCanceledBondExpiredMessage =>
      'A fatura do depósito expirou sem ser paga.';

  @override
  String get chatCardTitle => 'Novas mensagens';

  @override
  String get chatCardSolverTitle => 'Mensagens do mediador';

  @override
  String chatCardMessage(int count) {
    final intl.NumberFormat countNumberFormat = intl
        .NumberFormat.decimalPattern(localeName);
    final String countString = countNumberFormat.format(count);

    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$countString novas mensagens da sua contraparte',
      one: '1 nova mensagem da sua contraparte',
      zero: '$countString novas mensagens da sua contraparte',
    );
    return '$_temp0';
  }

  @override
  String chatCardSolverMessage(int count) {
    final intl.NumberFormat countNumberFormat = intl
        .NumberFormat.decimalPattern(localeName);
    final String countString = countNumberFormat.format(count);

    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$countString novas mensagens do mediador da disputa',
      one: '1 nova mensagem do mediador da disputa',
      zero: '$countString novas mensagens do mediador da disputa',
    );
    return '$_temp0';
  }

  @override
  String get invalidTradeIndexError =>
      'Sua conta está fora de sincronia com este nó Mostro, por isso ele recusou a ordem. Tente novamente em instantes';

  @override
  String get invalidFiatCurrencyError =>
      'Este nó Mostro não aceita essa moeda, por isso recusou a ordem. Escolha outra moeda';

  @override
  String get recoveringTradesMessage =>
      'Conta importada. Recuperando suas operações do Mostro…';

  @override
  String recoveredTradesMessage(int count) {
    final intl.NumberFormat countNumberFormat = intl
        .NumberFormat.decimalPattern(localeName);
    final String countString = countNumberFormat.format(count);

    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Conta importada. $countString operações recuperadas',
      one: 'Conta importada. 1 operação recuperada',
      zero: 'Conta importada. Você não tinha operações em andamento',
    );
    return '$_temp0';
  }

  @override
  String get recoverTradesFailedMessage =>
      'Conta importada, mas o Mostro não respondeu, então suas operações em andamento não foram recuperadas';

  @override
  String get paymentMethodsChosenLabel => 'Selecionados';

  @override
  String paymentMethodsSelectedCount(int count) {
    final intl.NumberFormat countNumberFormat = intl
        .NumberFormat.decimalPattern(localeName);
    final String countString = countNumberFormat.format(count);

    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$countString métodos selecionados',
      one: '1 método selecionado',
      zero: 'Selecione pelo menos um método',
    );
    return '$_temp0';
  }

  @override
  String get paymentMethodsConfirm => 'Confirmar métodos';

  @override
  String get paymentMethodAddCustom =>
      'Adicionar método de pagamento personalizado';

  @override
  String get paymentMethodsDiscardTitle => 'Descartar as alterações?';

  @override
  String get paymentMethodsDiscardConfirm => 'Descartar';

  @override
  String get paymentMethodsKeepEditing => 'Continuar editando';

  @override
  String get fundsAtRiskTitle => 'Este usuário ainda tem sats em jogo';

  @override
  String get fundsAtRiskBody =>
      'Se você continuar, as chaves deste usuário serão substituídas e nada do que está listado aqui poderá ser concluído ou recuperado neste dispositivo. Isso não é recomendado: você pode perder esses sats.';

  @override
  String get fundsAtRiskSellerEscrow =>
      'Sats bloqueados em custódia para uma venda';

  @override
  String get fundsAtRiskBondLocked => 'Depósito bloqueado';

  @override
  String get fundsAtRiskPayoutClaim =>
      'Pagamento de depósito ainda não resgatado';

  @override
  String get fundsAtRiskTradeInProgress => 'Operação em andamento';

  @override
  String get fundsAtRiskBondInvoicePending =>
      'Fatura do depósito ainda em aberto';

  @override
  String get fundsAtRiskCashuBalance => 'Ecash na carteira Cashu';

  @override
  String get fundsAtRiskCashuHint =>
      'Só as palavras secretas deste usuário o recuperam';

  @override
  String get fundsAtRiskKeep => 'Manter este usuário';

  @override
  String get fundsAtRiskContinue => 'Continuar mesmo assim';

  @override
  String get restoreSheetTitle => 'Restaurando sua conta';

  @override
  String get restoreSheetWaiting => 'Isso pode levar alguns segundos';

  @override
  String restoreSheetLoading(int done, int total) {
    return '$done de $total ordens recuperadas';
  }

  @override
  String get restoreStageConnecting => 'Conectando ao nó Mostro';

  @override
  String get restoreStageConnected => 'Conectado ao nó Mostro';

  @override
  String get restoreStageRequesting => 'Solicitando suas ordens';

  @override
  String restoreStageFound(int count) {
    final intl.NumberFormat countNumberFormat = intl
        .NumberFormat.decimalPattern(localeName);
    final String countString = countNumberFormat.format(count);

    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$countString ordens encontradas',
      one: '1 ordem encontrada',
      zero: '$countString ordens encontradas',
    );
    return '$_temp0';
  }

  @override
  String get restoreStageLoading => 'Carregando detalhes';

  @override
  String get restoreStageNoResponse => 'Sem resposta';

  @override
  String restoreLoadingCountSemantics(int done, int total) {
    return '$done de $total ordens';
  }

  @override
  String get restoreFailedTitle => 'Não foi possível restaurar suas ordens';

  @override
  String get restoreFailedSubtitle => 'Sua conta foi importada';

  @override
  String restoreFailedBody(String place) {
    return 'Verifique sua conexão e tente novamente. Você pode tentar de novo a qualquer momento em $place.';
  }

  @override
  String get restoreContinueWithout => 'Continuar sem restaurar';

  @override
  String get restoreDoneTitle => 'Conta restaurada';

  @override
  String get restoreDoneSubtitle => 'Recuperamos tudo o que o nó tinha';

  @override
  String get restoreDoneEmptySubtitle => 'Esta conta não tinha ordens no nó';

  @override
  String get restoreSummaryOrders => 'Ordens';

  @override
  String get restoreSummaryInProgress => 'Em andamento';

  @override
  String restoreActionNotice(int count) {
    final intl.NumberFormat countNumberFormat = intl
        .NumberFormat.decimalPattern(localeName);
    final String countString = countNumberFormat.format(count);

    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Você tem $countString ordens ativas aguardando você',
      one: 'Você tem 1 ordem ativa aguardando você',
      zero: 'Você tem $countString ordens ativas aguardando você',
    );
    return '$_temp0';
  }

  @override
  String restorePartialNotice(int missing, int total) {
    return '$missing de $total ordens não puderam ser carregadas';
  }

  @override
  String get attachSheetTitle => 'Enviar um arquivo';

  @override
  String get attachSheetBody =>
      'Ele é criptografado no seu dispositivo. Só sua contraparte pode abri-lo.';

  @override
  String get attachSheetBodySolver =>
      'Ele é criptografado no seu dispositivo. Só o mediador pode abri-lo.';

  @override
  String get attachSourcePhoto => 'Foto';

  @override
  String get attachSourceCamera => 'Câmera';

  @override
  String get attachSourcePdf => 'Documento PDF';

  @override
  String get attachConfirmTitle => 'Enviar este arquivo?';

  @override
  String attachConfirmBody(String fileName, String size) {
    return '$fileName ($size)';
  }

  @override
  String get attachmentTooLarge => 'Os arquivos podem ter até 25 MB.';

  @override
  String get attachmentUnsupported =>
      'Só é possível enviar arquivos JPEG, PNG e PDF.';

  @override
  String get attachmentInvalidImage => 'Não foi possível ler esta imagem.';

  @override
  String get attachmentReadFailed => 'Não foi possível ler o arquivo.';

  @override
  String get attachmentPeerUnknown =>
      'Você poderá enviar arquivos quando alguém aceitar a ordem.';

  @override
  String get attachmentUploadFailed =>
      'O envio falhou. Verifique sua conexão e tente novamente.';

  @override
  String get attachmentSendFailed => 'Não foi possível enviar o arquivo.';

  @override
  String get attachmentDownloadFailed => 'Não foi possível baixar o arquivo.';

  @override
  String get attachmentDecryptFailed =>
      'Não foi possível descriptografar este arquivo.';

  @override
  String get attachmentUploading => 'Enviando…';

  @override
  String get attachmentDiscard => 'Descartar';

  @override
  String get attachmentSave => 'Salvar';

  @override
  String get attachmentSaved => 'Arquivo salvo';

  @override
  String get attachmentSaveFailed => 'Não foi possível salvar o arquivo.';

  @override
  String attachmentImageSemantics(String fileName) {
    return 'Imagem: $fileName';
  }

  @override
  String get attachmentOpenImage => 'Abrir imagem';

  @override
  String get attachmentOpenWith => 'Abrir com…';

  @override
  String get attachmentShare => 'Compartilhar';

  @override
  String get attachmentMoreActions => 'Mais opções';

  @override
  String get attachmentNoAppToOpen =>
      'Nenhum app neste dispositivo consegue abrir este arquivo.';

  @override
  String get attachmentOpenFailed => 'Não foi possível abrir o arquivo.';

  @override
  String get attachmentShareFailed =>
      'Não foi possível compartilhar o arquivo.';

  @override
  String get attachmentSaveOnly => 'Este tipo de arquivo só pode ser salvo.';

  @override
  String get cashuWalletTitle => 'Carteira Cashu';

  @override
  String get cashuBalanceLabel => 'Saldo';

  @override
  String cashuMintLabel(String mint) {
    return 'Mint: $mint';
  }

  @override
  String get cashuNotConnected => 'Não conectada a um mint';

  @override
  String get cashuNoMintSet =>
      'Nenhum mint definido. Defina um ou receba um token para usar o mint dele.';

  @override
  String get cashuSetMintButton => 'Definir mint';

  @override
  String get cashuChangeMintButton => 'Alterar mint';

  @override
  String get cashuMintDialogTitle => 'Mint Cashu';

  @override
  String get cashuMintFieldLabel => 'URL do mint';

  @override
  String get cashuMintFieldHint => 'https://mint.example.com';

  @override
  String get cashuChangeMintTitle => 'Alterar o mint?';

  @override
  String cashuChangeMintWarning(String sats, String mint) {
    return 'Seus $sats sats ficam em $mint. Eles voltam quando você se conectar a esse mint de novo.';
  }

  @override
  String get cashuErrorNoMint => 'Defina primeiro um mint na carteira Cashu.';

  @override
  String get cashuErrorInvalidMintUrl =>
      'Essa não é uma URL de mint que você possa usar. Ela precisa começar com https://.';

  @override
  String get cashuErrorWalletOnOtherMint =>
      'Sua carteira Cashu usa outro mint. Mude-a para o mint deste nó em Configurações → Carteira Cashu e tente novamente.';

  @override
  String get cashuReceiveButton => 'Receber';

  @override
  String get cashuSendButton => 'Enviar';

  @override
  String get cashuReceiveHint => 'Cole ou escaneie um token Cashu';

  @override
  String get cashuReceiveTitle => 'Receber um token';

  @override
  String get cashuTokenFieldLabel => 'Token Cashu';

  @override
  String get cashuPasteTokenHint => 'Cole um token Cashu';

  @override
  String get qrScanUnavailable => 'Indisponível neste dispositivo';

  @override
  String get cashuAmountLabel => 'Valor em sats';

  @override
  String cashuReceived(int sats) {
    return '$sats sats recebidos';
  }

  @override
  String get cashuSyncButton => 'Sincronizar com o mint';

  @override
  String get cashuSynced => 'Sincronizado com o mint';

  @override
  String get cashuTokenTitle => 'Seu token';

  @override
  String get cashuTokenWarning =>
      'Quem resgatar este token fica com os fundos. Trate-o como dinheiro vivo: envie uma vez, para uma só pessoa.';

  @override
  String get cashuCopyToken => 'Copiar';

  @override
  String get cashuTokenCopied => 'Token copiado';

  @override
  String get cashuWalletExplanation =>
      'Esta carteira guarda ecash do mint que você escolher. Ela existe para financiar e receber operações Cashu — não é uma carteira de uso geral.';

  @override
  String get cashuErrorNotEnabled =>
      'Este nó Mostro não liquida operações com Cashu.';

  @override
  String get cashuErrorNotConnected =>
      'A carteira ainda não está conectada a um mint.';

  @override
  String get cashuErrorMintUnreachable =>
      'Não foi possível acessar o mint. Verifique sua conexão e tente novamente.';

  @override
  String get cashuErrorMintUnusable =>
      'Este mint não tem recursos de que a carteira precisa. Escolha outro mint.';

  @override
  String get cashuErrorUnsupportedOnWeb =>
      'A carteira Cashu ainda não está disponível na versão web.';

  @override
  String get cashuErrorAmountZero => 'Insira um valor maior que zero.';

  @override
  String cashuErrorAmountTooLarge(int sats) {
    return 'Você só tem $sats sats.';
  }

  @override
  String get cashuErrorReceiveFailed =>
      'Não foi possível resgatar esse token. Ele pode ser de outro mint ou já ter sido gasto.';

  @override
  String get cashuErrorSendFailed =>
      'Não foi possível criar o token. Talvez você não tenha fundos suficientes.';

  @override
  String get cashuErrorNoIdentity =>
      'Crie ou importe uma conta antes de usar a carteira.';

  @override
  String get cashuErrorGeneric =>
      'Algo deu errado com a carteira. Tente novamente.';

  @override
  String get cashuLastTokenPending =>
      'Você exportou um token. Ele vale dinheiro até alguém resgatá-lo — guarde-o até ter certeza de que chegou.';

  @override
  String get cashuShowLastToken => 'Mostrar de novo';

  @override
  String get cashuLastTokenDone => 'Já enviei';

  @override
  String get cashuTokenTooLargeForQr =>
      'Este token é grande demais para um código QR. Copie-o em vez disso.';

  @override
  String get cashuErrorNoMnemonic =>
      'Esta conta foi importada de uma chave privada, então não há palavras secretas das quais derivar a carteira. A carteira Cashu precisa de uma conta criada a partir de palavras secretas.';

  @override
  String get cashuErrorTokenUnverified =>
      'Não foi possível verificar este token: ele não traz nenhuma prova da assinatura do mint, por isso não foi aceito.';

  @override
  String get cashuErrorUnsupportedUnit =>
      'Esta carteira só guarda sats, e este token está em outra unidade (como millisats ou dólares). Ele continua intacto: você pode resgatá-lo em uma carteira que aceite essa unidade.';

  @override
  String cashuErrorUnsupportedUnitNamed(String unit) {
    return 'Esta carteira só guarda sats, e este token está em $unit. Ele continua intacto: você pode resgatá-lo em uma carteira que aceite essa unidade.';
  }

  @override
  String get cashuUnitMsat => 'millisats';

  @override
  String get cashuUnitUsd => 'dólares (USD)';

  @override
  String get cashuUnitEur => 'euros (EUR)';

  @override
  String get cashuErrorSendUnresolved =>
      'O envio falhou e a carteira não conseguiu confirmar que os fundos voltaram. Sincronize com o mint antes de tentar novamente.';

  @override
  String get cashuSendEcashOption => 'Ecash';

  @override
  String get cashuSendLightningOption => 'Lightning';

  @override
  String get cashuInvoiceDialogTitle => 'Pagar uma fatura Lightning';

  @override
  String get cashuInvoiceFieldLabel => 'Fatura Lightning';

  @override
  String get cashuPasteInvoiceHint => 'Cole uma fatura Lightning';

  @override
  String get cashuInvoiceScanHint => 'Cole ou escaneie uma fatura Lightning';

  @override
  String get cashuMeltConfirmTitle => 'Confirmar pagamento';

  @override
  String get cashuMeltAmount => 'Valor';

  @override
  String get cashuMeltFees => 'Taxas, até';

  @override
  String get cashuMeltTotal => 'Total, até';

  @override
  String get cashuMeltFeesNote =>
      'As taxas que o mint não usar voltam para a sua carteira.';

  @override
  String get cashuMeltQuoteRefreshed =>
      'O preço mudou. Confira o novo total antes de pagar.';

  @override
  String get cashuPayButton => 'Pagar';

  @override
  String cashuMeltPaidTitle(String sats) {
    return '$sats sats pagos';
  }

  @override
  String cashuMeltPaidFee(String fee) {
    return 'Taxa: $fee sats';
  }

  @override
  String get cashuMeltPendingTitle => 'Pagamento em andamento';

  @override
  String get cashuMeltPendingBody =>
      'O resultado ainda não foi confirmado. Esses sats ficam retidos; toque em “Sincronizar com o mint” mais tarde para resolver.';

  @override
  String get cashuMeltFailedTitle => 'Falha no pagamento';

  @override
  String get cashuErrorInvalidInvoice =>
      'Isso não é uma fatura Lightning que esta carteira possa pagar.';

  @override
  String get cashuErrorInvoiceNoAmount =>
      'Esta fatura não tem valor. Peça uma que indique quanto pagar.';

  @override
  String get cashuErrorInvoiceExpired => 'Esta fatura expirou. Peça uma nova.';

  @override
  String get cashuErrorMeltUnsupported =>
      'Este mint não pode pagar faturas Lightning.';

  @override
  String get cashuErrorMeltAmountOutOfRange =>
      'Este mint não paga faturas desse valor.';

  @override
  String get cashuErrorMeltQuoteFailed =>
      'O mint não conseguiu cotar este pagamento. Tente novamente mais tarde.';

  @override
  String get cashuErrorMeltQuoteExpired =>
      'A cotação do pagamento expirou. Nada foi pago; comece de novo.';

  @override
  String get cashuErrorMeltFeeChanged =>
      'As taxas subiram desde que você confirmou. Nada foi pago; comece de novo.';

  @override
  String get cashuErrorMeltInFlight =>
      'Ainda há um pagamento Lightning desta carteira em andamento. Aguarde até terminar e tente de novo.';

  @override
  String get cashuErrorMeltInsufficientFunds =>
      'Você não tem saldo suficiente na carteira para pagar esta fatura e suas taxas.';

  @override
  String get cashuErrorMeltFailed =>
      'O pagamento não foi concluído. Nada foi pago; os sats voltaram ao seu saldo.';

  @override
  String get lockEscrowTitle => 'Bloquear a custódia';

  @override
  String get lockEscrowExplanation =>
      'Bloqueie seu ecash em uma custódia 2 de 3 no mint deste nó. Nem você nem o comprador podem movê-lo sozinhos — e, se o nó desaparecer, você mesmo pode recuperá-lo quando o prazo de bloqueio passar.';

  @override
  String get lockEscrowAmount => 'Custódia';

  @override
  String get lockEscrowFee => 'Taxa do Mostro';

  @override
  String get lockEscrowTotal => 'Total';

  @override
  String get lockEscrowBalance => 'Seu saldo';

  @override
  String get lockEscrowConfirm => 'Bloquear custódia';

  @override
  String get lockEscrowFundWallet => 'Adicionar fundos à carteira';

  @override
  String get lockEscrowSubmitted => 'Custódia bloqueada e enviada';

  @override
  String get lockEscrowInsufficientFunds =>
      'Sua carteira não tem o suficiente para a custódia e a taxa.';

  @override
  String get lockEscrowNotTheSeller => 'Só o vendedor financia a custódia.';

  @override
  String get lockEscrowInvalidToken =>
      'Não foi possível montar a custódia corretamente. Nada foi enviado.';

  @override
  String get lockEscrowFailed =>
      'O mint não conseguiu bloquear a custódia. Seus fundos não foram movidos.';

  @override
  String lockEscrowMint(String mint) {
    return 'Mint: $mint';
  }

  @override
  String lockEscrowLocktime(int days) {
    return 'Recuperável por você após $days dias';
  }

  @override
  String get lockEscrowRequestMissing =>
      'Esta operação ainda não tem pedido de custódia. Aguarde a aceitação do comprador chegar e tente novamente.';

  @override
  String get lockEscrowWrongTradeKey =>
      'Este dispositivo não tem a chave com que esta ordem foi aceita. Restaure sua conta no dispositivo em que você iniciou a operação.';

  @override
  String get lockEscrowLocktimeNotReached =>
      'A custódia ainda está bloqueada. Você mesmo pode recuperá-la quando o prazo de bloqueio passar.';

  @override
  String get lockEscrowClockInvalid =>
      'O relógio do seu dispositivo está errado, então não é possível calcular os prazos da custódia corretamente. Corrija a data e tente novamente.';

  @override
  String get lockEscrowRetry => 'Tentar enviar de novo';

  @override
  String get lockEscrowPendingSubmission =>
      'Sua custódia está bloqueada, mas o nó não a confirmou. Tentar de novo é seguro — ela não será bloqueada uma segunda vez.';

  @override
  String get lockEscrowMintNotSupported =>
      'Este nó permite que cada ordem escolha seu mint, e esta versão do app só consegue bloquear uma custódia em um nó com um único mint.';

  @override
  String get lockEscrowNotRecorded =>
      'A custódia chegou ao nó, mas este dispositivo não conseguiu salvar uma cópia dela. A operação pode continuar, mas este dispositivo não poderá recuperar a custódia.';

  @override
  String get lockEscrowRejectedToken =>
      'O nó não aceitou esta custódia. Ela foi deixada de lado — volta para você quando o bloqueio expirar — e a próxima tentativa bloqueia uma nova.';

  @override
  String get lockEscrowRejectedMint =>
      'O nó usa outro mint. Esta custódia foi deixada de lado — volta para você quando o bloqueio expirar. Verifique o mint do nó antes de tentar novamente.';

  @override
  String get lockEscrowMintUnavailableAtNode =>
      'O nó não conseguiu acessar o mint para verificar sua custódia. Tente novamente: a mesma custódia é reenviada, nada é bloqueado duas vezes.';

  @override
  String get lockEscrowRejectedGeneric =>
      'O nó recusou a custódia. Ela continua registrada neste dispositivo; tente novamente em instantes.';

  @override
  String get lockEscrowNoAnswer =>
      'O nó ainda não respondeu. Sua custódia está registrada; tentar de novo reenvia a mesma.';

  @override
  String get lockEscrowOrderMovedOn =>
      'O nó diz que esta ordem não está mais aguardando a custódia. Sua custódia continua registrada neste dispositivo; o status da operação será atualizado quando o nó informar.';

  @override
  String get tradeHeadlineWaitingPaymentSellerCashu =>
      'Bloqueie a custódia para iniciar a operação';

  @override
  String get tradeWaitingPaymentSellerInstructionCashu =>
      'Bloqueie seu ecash na custódia, no mint do nó. Isso inicia a operação, e ele volta para você se o nó desaparecer.';

  @override
  String get tradeBodyWaitingPaymentBuyerCashu =>
      'O vendedor está bloqueando os sats na custódia. Assim que estiverem bloqueados, é a sua vez de pagar.';

  @override
  String get shareChatKeyAction =>
      'Compartilhar a chave do chat com o mediador';

  @override
  String get shareChatKeyTitle =>
      'Compartilhar a chave do chat com o mediador?';

  @override
  String get shareChatKeyBody =>
      'Se você confirmar, o mediador desta disputa poderá ler todo o chat entre você e sua contraparte nesta ordem, e somente esse chat: não os chats das suas operações anteriores ou posteriores. Isso não pode ser desfeito. Compartilhar é opcional, mas ajuda o mediador a resolver a disputa mais rápido.';

  @override
  String get shareChatKeyConfirm => 'Compartilhar';

  @override
  String get chatKeySharedIndicator =>
      'Chave do chat compartilhada com o mediador';

  @override
  String get shareChatKeyUnavailable =>
      'A chave do chat desta operação não está disponível neste dispositivo.';

  @override
  String get moreReactions => 'Mais reações';

  @override
  String messageReactionLabel(String emoji) {
    return 'Reação: $emoji';
  }

  @override
  String get reactionSendFailed =>
      'Não foi possível enviar a reação. Tente novamente.';

  @override
  String get messageMenuHint => 'Abrir o menu da mensagem';

  @override
  String get cashuAnyMint => 'Qualquer mint';

  @override
  String get settingsMintLabel => 'Mint';

  @override
  String get settingsMintCopied => 'URL do mint copiada';

  @override
  String get pwaInstallTitle => 'Instalar o Mostro';

  @override
  String get pwaInstallBody =>
      'Abra-o pela tela inicial, em tela cheia, como qualquer outro app.';

  @override
  String get pwaInstallAction => 'Instalar';

  @override
  String get pwaInstallNotNow => 'Agora não';

  @override
  String get pwaInstallSettingTitle => 'Instalar app';

  @override
  String get pwaInstallStepsTitle => 'Adicione o Mostro à sua tela inicial';

  @override
  String get pwaInstallStepShare =>
      'Toque no botão Compartilhar na barra de ferramentas do navegador.';

  @override
  String get pwaInstallStepAdd => 'Escolha “Adicionar à Tela de Início”.';

  @override
  String get pwaInstallStepsDone => 'Entendi';

  @override
  String get myReputationTitle => 'Sua reputação';

  @override
  String reputationRatingsCount(int count) {
    final intl.NumberFormat countNumberFormat = intl
        .NumberFormat.decimalPattern(localeName);
    final String countString = countNumberFormat.format(count);

    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$countString avaliações',
      one: '1 avaliação',
      zero: 'sem avaliações',
    );
    return '$_temp0';
  }

  @override
  String reputationSince(String date) {
    return 'desde $date';
  }

  @override
  String get myReputationNoReviews =>
      'Nenhuma avaliação ainda. Sua reputação começa com sua primeira operação avaliada.';

  @override
  String get myReputationPrivacyMode =>
      'O modo privacidade total não mantém reputação. Escolha o modo reputação abaixo para construir uma.';

  @override
  String get myReputationLoading => 'Consultando seu nó…';

  @override
  String get myReputationUnavailable => 'Seu nó ainda não respondeu.';

  @override
  String myReputationOnNode(String node) {
    return 'Em $node';
  }

  @override
  String get orderLinkTitle => 'Link da ordem';

  @override
  String get orderLinkLooking => 'Procurando a ordem…';

  @override
  String orderLinkSwitching(String nodeName) {
    return 'Mudando para $nodeName…';
  }

  @override
  String get orderLinkInvalidTitle => 'Este link não pode ser aberto';

  @override
  String get orderLinkInvalidBody =>
      'Não é um link para uma ordem Mostro, ou falta parte dele.';

  @override
  String get orderLinkNotFoundBody =>
      'Nenhum relay respondeu com esta ordem. Verifique sua conexão e tente novamente.';

  @override
  String get orderLinkUnavailableTitle => 'Ordem não está mais disponível';

  @override
  String get orderLinkUnavailableBody =>
      'Alguém já a aceitou, ou ela foi cancelada ou expirou.';

  @override
  String get orderLinkFailedTitle => 'Não foi possível abrir a ordem';

  @override
  String get orderLinkOtherNodeTitle => 'Ordem em outro nó';

  @override
  String orderLinkOtherNodeBody(String nodeName) {
    return 'Esta ordem foi publicada em $nodeName. Para vê-la e aceitá-la, mude para esse nó.';
  }

  @override
  String get orderLinkUnknownNodeWarning =>
      'Este nó não está na sua lista. Mude para ele só se confiar em quem enviou o link: o nó em que você opera liquida suas operações e resolve as disputas delas.';

  @override
  String get reputationNodeDoesNotExport =>
      'Este Mostro não exporta reputação.';

  @override
  String get reputationNodeDoesNotImport =>
      'Este Mostro não importa reputação.';

  @override
  String get reputationIdentityRequired =>
      'A reputação só pode ser movida de uma conta que mantém sua reputação. Desative o modo privacidade total e tente novamente.';

  @override
  String get reputationNotEligible =>
      'Sua conta ainda não pode exportar a reputação: ela precisa de pelo menos 10 operações concluídas e 5 avaliações recebidas.';

  @override
  String get reputationBoundToOtherIdentity =>
      'Sua reputação lá já está vinculada a outra identidade. Autorize a mudança a partir da identidade à qual ela está vinculada.';

  @override
  String get reputationInvalidRebind =>
      'A autorização para mover sua reputação é inválida ou expirou. Crie uma nova.';

  @override
  String get reputationExpiredAttestation =>
      'Esta reputação expirou. Solicite-a novamente à fonte.';

  @override
  String get reputationUntrustedIssuer =>
      'Este Mostro não aceita reputação dessa fonte.';

  @override
  String get reputationIdentityMismatch =>
      'Esta reputação foi emitida para uma identidade diferente da que você está usando.';

  @override
  String get reputationAlreadyImported =>
      'Esta reputação já foi importada neste Mostro.';

  @override
  String get reputationInvalidAttestation =>
      'Esta não é uma reputação válida. Solicite-a novamente à fonte.';

  @override
  String get reputationImportTitle => 'Importar reputação';

  @override
  String get reputationImportIntro =>
      'Traga para este Mostro a reputação que você conquistou no lnp2pBot ou em outro Mostro. Importar vincula as duas contas: a fonte e este Mostro ficam sabendo que elas pertencem à mesma pessoa.';

  @override
  String get reputationOpenLnp2pbot => 'Obter no lnp2pBot';

  @override
  String get reputationPasteHint => 'Cole a reputação que você recebeu';

  @override
  String get reputationCheck => 'Verificar';

  @override
  String get reputationImported => 'Sua reputação foi importada.';

  @override
  String get reputationImportConfirm => 'Importar para este Mostro';

  @override
  String get reputationFiguresNote =>
      'A reputação importada é somada à que você tem aqui; suas contrapartes as veem combinadas.';

  @override
  String get reputationExportFailed =>
      'Este Mostro não conseguiu exportar sua reputação. Tente novamente mais tarde.';

  @override
  String get reputationExportUnexpectedIssuer =>
      'Este Mostro assinou a resposta com uma chave diferente da que anunciou. Troque para outro Mostro e volte para atualizar as informações dele, depois tente novamente.';

  @override
  String get reputationOpenLnp2pbotFailed =>
      'Não foi possível abrir o Telegram. Abra você mesmo o lnp2pBot no Telegram e cole aqui o que ele enviar.';

  @override
  String get reputationIssuedByLnp2pbot => 'Emitida pelo lnp2pBot';

  @override
  String reputationIssuedByMostro(String name) {
    return 'Emitida pelo Mostro $name';
  }

  @override
  String get reputationIssuedByUnknownKey =>
      'Emitida por uma chave que este app não conhece:';

  @override
  String get reputationIdentityHint =>
      'Antes de confirmar no lnp2pBot, verifique se ele mostra esta mesma chave pública:';

  @override
  String get reputationUnavailable =>
      'Não foi possível verificar se a reputação pode ser importada. Tente novamente.';

  @override
  String get reputationIdentityChanged =>
      'Sua identidade mudou. Confira a chave pública mostrada aqui antes de tentar novamente.';

  @override
  String get reputationSettingTitle => 'Reputação';

  @override
  String get reputationImportCardBody =>
      'Traga para este Mostro a reputação que você conquistou no lnp2pBot ou em outro Mostro.';

  @override
  String get reputationExportTitle => 'Exportar minha reputação';

  @override
  String get reputationExportCardBody =>
      'Obtenha uma cópia assinada da reputação que você conquistou neste Mostro, para importá-la em outro.';

  @override
  String get reputationExportConfirmTitle => 'Exportar para esta identidade?';

  @override
  String reputationExportConfirmBody(String npub) {
    return 'Sua reputação neste Mostro será exportada para esta identidade:\n\n$npub\n\nDepois de exportada, ela fica vinculada a essa identidade: exportá-la para outra identidade mais tarde exige uma autorização assinada com esta.';
  }

  @override
  String get reputationExportConfirmButton => 'Exportar';

  @override
  String get reputationExported =>
      'Sua reputação está pronta. Mude para o Mostro onde você a quer e importe-a; ela é válida por 7 dias.';

  @override
  String get reputationRebindTitle => 'Mudar para uma nova identidade';

  @override
  String get reputationRebindBody =>
      'Assine uma autorização para a nova identidade com a identidade à qual sua reputação está vinculada agora: para este Mostro, ou para o lnp2pBot se a obteve lá.';

  @override
  String get reputationNewIdentityHint => 'Nova identidade (npub ou hex)';

  @override
  String get reputationRebindSignNode => 'Assinar para este Mostro';

  @override
  String get reputationRebindSignBot => 'Assinar para o lnp2pBot';

  @override
  String get reputationRebindSign => 'Assinar autorização';

  @override
  String get reputationRebindSignedForNode =>
      'A partir da nova identidade, cole-a no campo de autorização do cartão de exportação e exporte.';

  @override
  String get reputationRebindSignedForBot =>
      'O lnp2pBot só aceita isto depois que a nova identidade pediu a ele sua reputação: se ainda não o fez, abra o lnp2pBot a partir da nova identidade com \"Obter no lnp2pBot\" na tela de importação, e não abra depois nenhum outro link para o bot. Em seguida, cole isto nesse chat e confirme. Vale por uma hora.';

  @override
  String get reputationInvalidIdentity =>
      'Essa não é uma chave npub ou hex válida.';

  @override
  String get reputationRebindInputHint =>
      'Autorização da sua identidade anterior (opcional)';

  @override
  String get reputationRebindConfirmTitle => 'Autorizar esta identidade?';

  @override
  String reputationRebindConfirmBody(String npub) {
    return 'Quem tiver esta identidade poderá exportar sua reputação deste Mostro, e sua identidade atual não poderá mais:\n\n$npub\n\nAssine apenas para uma identidade que seja sua.';
  }

  @override
  String reputationRebindConfirmBodyBot(String npub) {
    return 'Quem tiver esta identidade poderá exportar sua reputação do lnp2pBot, e sua identidade atual não poderá mais:\n\n$npub\n\nAssine apenas para uma identidade que seja sua.';
  }

  @override
  String get payoutPaidToLabel => 'Pago para';

  @override
  String get payoutSendingToLabel => 'Enviando para';

  @override
  String get payoutNotPaidLabel => 'Não pago para';

  @override
  String get payoutChosenByLabel => 'Escolhido por';

  @override
  String get payoutAmountLabel => 'Valor';

  @override
  String get payoutHashLabel => 'Hash do pagamento';

  @override
  String get payoutTriedBeforeLabel => 'Tentativa anterior';

  @override
  String payoutTriedBeforeValue(String destination, String outcome) {
    return '$destination · $outcome';
  }

  @override
  String get payoutNwcWallet => 'Sua carteira NWC';

  @override
  String payoutNwcWalletNamed(String name) {
    return '$name (NWC)';
  }

  @override
  String payoutInvoice(String invoice) {
    return 'Fatura $invoice';
  }

  @override
  String get payoutSourceDefaultAddress => 'Seu endereço padrão';

  @override
  String get payoutSourceNwcWallet => 'Sua carteira NWC';

  @override
  String get payoutSourceEntered => 'Você, para esta operação';

  @override
  String get payoutOutcomeSubmitted => 'Aguardando';

  @override
  String get payoutOutcomeRetrying => 'Falhou, tentando de novo';

  @override
  String get payoutOutcomeFailed => 'Falhou';

  @override
  String payoutOutcomeFailedAttempts(int count) {
    final intl.NumberFormat countNumberFormat = intl
        .NumberFormat.decimalPattern(localeName);
    final String countString = countNumberFormat.format(count);

    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Falhou após $countString tentativas',
      one: 'Falhou após 1 tentativa',
      zero: 'Falhou após $countString tentativas',
    );
    return '$_temp0';
  }

  @override
  String get payoutOutcomeRejected => 'Recusado pelo nó';

  @override
  String get payoutOutcomePaid => 'Pago';

  @override
  String get payoutHashCopied => 'Hash do pagamento copiado';

  @override
  String get takeOrderPayoutLabel => 'Seus sats vão para';

  @override
  String get takeOrderPayoutInvoice => 'Uma fatura que você adicionar';

  @override
  String get takeOrderPayoutChangeHint => 'Alterar para onde vão seus sats';

  @override
  String takeOrderPayoutNoteDefault(String address) {
    return 'Seus sats serão enviados para $address, seu endereço Lightning padrão.';
  }

  @override
  String takeOrderPayoutNoteAddress(String address) {
    return 'Seus sats serão enviados para $address, somente nesta operação.';
  }

  @override
  String get takeOrderPayoutNoteInvoice =>
      'Depois de aceitar a ordem, você vai adicionar a fatura para a qual seus sats serão pagos.';

  @override
  String get takeOrderPayoutSheetTitle => 'Para onde vão seus sats';

  @override
  String get takeOrderPayoutSheetDefault => 'Meu endereço Lightning padrão';

  @override
  String get takeOrderPayoutSheetOther => 'Outro endereço Lightning';

  @override
  String get takeOrderPayoutSheetInvoice =>
      'Uma fatura que adiciono depois de aceitar';

  @override
  String get takeOrderPayoutSheetApply => 'Usar nesta operação';

  @override
  String invoicePayoutFailed(String destination) {
    return 'O pagamento para $destination falhou.';
  }

  @override
  String invoicePayoutFailedAttempts(String destination, int count) {
    final intl.NumberFormat countNumberFormat = intl
        .NumberFormat.decimalPattern(localeName);
    final String countString = countNumberFormat.format(count);

    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other:
          'O pagamento para $destination falhou após $countString tentativas.',
      one: 'O pagamento para $destination falhou após 1 tentativa.',
      zero:
          'O pagamento para $destination falhou após $countString tentativas.',
    );
    return '$_temp0';
  }

  @override
  String get invoicePayoutFailedNwc =>
      'Sua carteira NWC está gerando uma nova fatura para esses sats.';

  @override
  String invoicePayoutFailedNwcNamed(String name) {
    return '$name está gerando uma nova fatura para esses sats.';
  }

  @override
  String get invoicePayoutFailedManual =>
      'Adicione uma nova fatura para receber seus sats.';

  @override
  String get tradeCardPayoutFailedTitle =>
      'O Mostro não conseguiu enviar seus sats';

  @override
  String get tradeCardPayoutFailedMessage =>
      'O Mostro não conseguiu enviar seus sats para o endereço ou a fatura que você informou. Abra a operação para ver qual falhou e adicione uma nova fatura, se ainda for necessário.';

  @override
  String get tradeCardOrderPublishedTitle => 'Ordem publicada';

  @override
  String get tradeCardOrderPublishedMessage =>
      'Sua ordem já está no livro de ordens e outros usuários podem aceitá-la.';

  @override
  String get payoutInvoiceLabel => 'Fatura';

  @override
  String get payoutInvoiceCopied => 'Fatura copiada';

  @override
  String get payoutWillGoToLabel => 'Os sats irão para';

  @override
  String get payoutMaybePaidToLabel => 'Talvez pago para';

  @override
  String get payoutOutcomeReplaced => 'Substituído por um posterior';

  @override
  String get payoutOutcomeMaybePaid => 'Pago para este ou outro listado aqui';

  @override
  String otherNodeCardLine(String nodeName) {
    return 'Operação no nó: $nodeName';
  }

  @override
  String get otherNodeCardDialogTitle => 'Operação em outro nó';

  @override
  String otherNodeCardSwitchPrompt(String nodeName) {
    return 'Quer mudar para o nó $nodeName?';
  }

  @override
  String get stablecoinsGroupHeader => 'Stablecoins';

  @override
  String get bitcoinNetworksGroupHeader => 'Bitcoin em outras redes';

  @override
  String marketPriceNotQuotedByNode(String code) {
    return 'Este nó não cota $code a preço de mercado. Defina um valor fixo em sats.';
  }
}

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:mostro/features/chat/providers/chat_providers.dart';
import 'package:mostro/features/disputes/providers/disputes_providers.dart';
import 'package:mostro/shared/utils/platform_int64.dart';
import 'package:mostro/src/rust/api/disputes.dart' as disputes_api;
import 'package:mostro/src/rust/api/messages.dart' as messages_api;
import 'package:mostro/src/rust/api/types.dart' as rust_types;

/// A message of the dispute channel as the dispute chat shows it. Every
/// message there is ours or the solver's: the peer never shares that key.
DisputeMessage disputeMessageFromRust(rust_types.ChatMessage message) =>
    DisputeMessage(
      id: message.id,
      content: message.content,
      isMine: message.isMine,
      isAdmin: !message.isMine,
      createdAt: platformInt64ToInt(message.createdAt),
      nostrEventId: message.id,
      attachment: message.attachment,
      senderPubkey: message.senderPubkey,
    );

/// The conversation with the solver of one trade's dispute (#143).
///
/// Rust keeps the peer and solver conversations of an order in one store;
/// only the dispute channel's messages ([rust_types.MessageType.admin]) are
/// taken here, as the peer room takes only its own (PR #254 review).
class DisputeChatNotifier extends StateNotifier<List<DisputeMessage>> {
  DisputeChatNotifier(Future<List<rust_types.ChatMessage>> Function() load)
    : super(const []) {
    unawaited(_load(load));
  }

  final _seen = <String>{};

  /// Adds [message] — live, from history or one we just sent — once.
  void add(rust_types.ChatMessage message) {
    if (!mounted) return;
    if (message.messageType != rust_types.MessageType.admin) return;
    if (!_seen.add(message.id)) return;
    state = [...state, disputeMessageFromRust(message)];
  }

  // History and the live stream can overlap: both go through [add], whose
  // id check keeps each message once whichever lands first.
  Future<void> _load(
    Future<List<rust_types.ChatMessage>> Function() load,
  ) async {
    try {
      final history = await load();
      history.forEach(add);
    } catch (e) {
      debugPrint('[disputes] chat history failed: $e');
    }
  }
}

final disputeChatProvider = StateNotifierProvider.autoDispose
    .family<DisputeChatNotifier, List<DisputeMessage>, String>((ref, tradeId) {
      final notifier = DisputeChatNotifier(
        () => messages_api.getMessages(tradeId: tradeId),
      );
      ref.listen(
        incomingMessageProvider(tradeId),
        (_, next) => next.whenData(notifier.add),
      );
      return notifier;
    });

/// The Rust calls behind the dispute chat's text, chat key share and refresh,
/// in one place a test can replace (the files go through
/// `AttachmentGateway.sendToSolver`).
class DisputeChatGateway {
  const DisputeChatGateway();

  /// Sends [text] to the solver and returns it as stored. Fails with the
  /// markers of `submit_evidence`.
  Future<rust_types.ChatMessage> sendText({
    required String tradeId,
    required String text,
  }) => disputes_api.submitEvidence(tradeId: tradeId, text: text);

  /// Sends the solver the peer chat key (#415): built and sent in Rust, so
  /// the key reaches Dart only inside the returned message.
  Future<rust_types.ChatMessage> shareChatKey(String tradeId) =>
      disputes_api.shareChatKeyWithSolver(tradeId: tradeId);

  Future<rust_types.Dispute?> getDispute(String tradeId) =>
      disputes_api.getDispute(tradeId: tradeId);

  /// Whether [solverPubkey] is the Serbero of [tradeId]'s node or a person
  /// (#637).
  Future<rust_types.SolverRole> solverRole(
    String tradeId,
    String solverPubkey,
  ) => disputes_api.solverRole(tradeId: tradeId, solverPubkey: solverPubkey);
}

final disputeChatGatewayProvider = Provider<DisputeChatGateway>(
  (ref) => const DisputeChatGateway(),
);

/// One solver of one trade's dispute: only that dispute's node can vouch
/// that the solver is its Serbero.
typedef SolverOfDispute = ({String tradeId, String solverPubkey});

/// Who one solver is, as Rust decides it (#637). Read each time a dispute
/// chat opens: the node's announcement can arrive after the history did.
/// A person until answered — never "Serbero" on a guess.
final solverRoleProvider = FutureProvider.autoDispose
    .family<rust_types.SolverRole, SolverOfDispute>(
      (ref, solver) => ref
          .watch(disputeChatGatewayProvider)
          .solverRole(solver.tradeId, solver.solverPubkey),
    );

/// How many times [disputeUpdatesProvider] subscribes again after the
/// bridge stream fails, before it gives up.
const int kDisputeUpdateResubscribes = 3;

/// Live updates of one trade's dispute from the bridge: the solver taking
/// it, its resolution (#143).
///
/// A failed stream is subscribed again, a bounded number of times, and each
/// new subscription starts with the record as it stands — whatever changed
/// while none was listening (PR #596 review). The screen also refreshes on
/// open, so giving up leaves it as current as its last update.
final disputeUpdatesProvider = StreamProvider.autoDispose
    .family<rust_types.Dispute, String>((ref, tradeId) async* {
      for (var attempt = 0; attempt <= kDisputeUpdateResubscribes; attempt++) {
        try {
          final stream = await disputes_api.onDisputeUpdated(tradeId: tradeId);
          if (attempt > 0) {
            final current = await disputes_api.getDispute(tradeId: tradeId);
            if (current != null) yield current;
          }
          while (true) {
            yield await stream.next();
          }
        } catch (e) {
          debugPrint('[disputes] update stream failed ($attempt): $e');
        }
      }
    });

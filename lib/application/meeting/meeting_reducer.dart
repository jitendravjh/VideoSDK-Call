import 'package:synq/data/models/meeting_state.dart';

/// Pure helpers for meeting participant bookkeeping and the glare-free offer
/// rule. Kept separate from `MeetingController` so the mesh logic is unit
/// testable without any real signalling or peer connections.
class MeetingReducer {
  const MeetingReducer._();

  /// Deterministic, glare-free offerer rule. For any unordered pair exactly one
  /// side returns true (the lexicographically smaller id offers), so two peers
  /// never offer each other simultaneously.
  static bool shouldOffer(String selfId, String peerId) =>
      selfId.compareTo(peerId) < 0;

  /// Adds [participant], or replaces the existing entry with the same id.
  static List<MeetingParticipant> upsert(
    List<MeetingParticipant> current,
    MeetingParticipant participant,
  ) {
    final index = current.indexWhere((p) => p.userId == participant.userId);
    if (index == -1) return [...current, participant];
    final next = [...current];
    next[index] = participant;
    return next;
  }

  static List<MeetingParticipant> remove(
    List<MeetingParticipant> current,
    String userId,
  ) => current.where((p) => p.userId != userId).toList();

  /// Applies [change] to the participant with [userId], leaving others as-is.
  static List<MeetingParticipant> update(
    List<MeetingParticipant> current,
    String userId,
    MeetingParticipant Function(MeetingParticipant participant) change,
  ) => [
    for (final participant in current)
      if (participant.userId == userId) change(participant) else participant,
  ];
}

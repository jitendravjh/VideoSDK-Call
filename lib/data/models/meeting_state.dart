import 'package:freezed_annotation/freezed_annotation.dart';

part 'meeting_state.freezed.dart';

/// Lifecycle of a group meeting (mesh), mirroring `CallState` but for N peers.
///
/// `connecting` covers hosting or joining before the server acknowledges;
/// `active` carries the live participant list. The room code is the host's
/// user code.
@freezed
sealed class MeetingState with _$MeetingState {
  const MeetingState._();

  const factory MeetingState.idle() = MeetingIdle;

  const factory MeetingState.connecting({
    required String roomCode,
    required bool isHost,
  }) = MeetingConnecting;

  const factory MeetingState.active({
    required String roomCode,
    required bool isHost,
    required List<MeetingParticipant> participants,
  }) = MeetingActive;

  const factory MeetingState.ended({required String reason}) = MeetingEnded;

  String? get roomCode => switch (this) {
    MeetingConnecting(:final roomCode) => roomCode,
    MeetingActive(:final roomCode) => roomCode,
    _ => null,
  };

  bool get isHost => switch (this) {
    MeetingConnecting(:final isHost) => isHost,
    MeetingActive(:final isHost) => isHost,
    _ => false,
  };

  List<MeetingParticipant> get participants => switch (this) {
    MeetingActive(:final participants) => participants,
    _ => const [],
  };
}

/// One remote participant in the meeting. Media flags are driven by the peer's
/// data-channel media-state and the remote-track callback.
@freezed
abstract class MeetingParticipant with _$MeetingParticipant {
  const factory MeetingParticipant({
    required String userId,
    required String displayName,
    @Default(false) bool connected,
    @Default(false) bool hasVideo,
    @Default(true) bool micOn,
  }) = _MeetingParticipant;
}

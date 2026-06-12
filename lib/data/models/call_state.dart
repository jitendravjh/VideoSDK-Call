import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:meet_videosdk/data/models/user.dart';

part 'call_state.freezed.dart';

/// The lifecycle of a 1:1 call, owned by the `CallController`.
///
/// Flow: idle -> outgoing/incoming -> connecting -> connected ->
/// ended | failed.
@freezed
sealed class CallState with _$CallState {
  const CallState._();

  const factory CallState.idle() = Idle;

  const factory CallState.outgoing({required User peer}) = Outgoing;

  const factory CallState.incoming({
    required User peer,
    required String offerSdp,
  }) = Incoming;

  const factory CallState.connecting({required User peer}) = Connecting;

  const factory CallState.connected({required User peer}) = Connected;

  const factory CallState.ended({required String reason}) = Ended;

  const factory CallState.failed({required String error}) = Failed;

  User? get peer => switch (this) {
        Outgoing(:final peer) => peer,
        Incoming(:final peer) => peer,
        Connecting(:final peer) => peer,
        Connected(:final peer) => peer,
        _ => null,
      };

  bool get isActive => switch (this) {
        Idle() || Ended() || Failed() => false,
        _ => true,
      };
}

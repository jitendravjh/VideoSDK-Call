import 'package:freezed_annotation/freezed_annotation.dart';

part 'ice_candidate_payload.freezed.dart';
part 'ice_candidate_payload.g.dart';

@freezed
abstract class IceCandidatePayload with _$IceCandidatePayload {
  const factory IceCandidatePayload({
    required String candidate,
    String? sdpMid,
    int? sdpMLineIndex,
  }) = _IceCandidatePayload;

  factory IceCandidatePayload.fromJson(Map<String, dynamic> json) =>
      _$IceCandidatePayloadFromJson(json);
}

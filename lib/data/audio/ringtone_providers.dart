import 'package:meet_videosdk/data/audio/ringtone_service.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'ringtone_providers.g.dart';

@Riverpod(keepAlive: true)
RingtoneService ringtoneService(Ref ref) {
  final service = RingtoneService();
  ref.onDispose(service.dispose);
  return service;
}

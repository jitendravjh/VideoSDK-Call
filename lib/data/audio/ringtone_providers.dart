import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:synq/data/audio/ringtone_service.dart';

part 'ringtone_providers.g.dart';

@Riverpod(keepAlive: true)
RingtoneService ringtoneService(Ref ref) {
  final service = RingtoneService();
  ref.onDispose(service.dispose);
  return service;
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:meet_videosdk/data/session/session_store.dart';
import 'package:meet_videosdk/presentation/common/app_router.dart';
import 'package:meet_videosdk/presentation/common/app_theme.dart';
import 'package:meet_videosdk/presentation/common/call_sound_scope.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final prefs = await SharedPreferences.getInstance();
  runApp(
    ProviderScope(
      overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
      child: const VideoSdkApp(),
    ),
  );
}

class VideoSdkApp extends ConsumerWidget {
  const VideoSdkApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(routerProvider);
    return MaterialApp.router(
      title: 'VideoSDK Call',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      routerConfig: router,
      builder: (context, child) =>
          CallSoundScope(child: child ?? const SizedBox.shrink()),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:meet_videosdk/application/call/call_controller.dart';
import 'package:meet_videosdk/data/models/call_state.dart';
import 'package:meet_videosdk/presentation/call/call_screen.dart';
import 'package:meet_videosdk/presentation/common/app_router.dart';
import 'package:meet_videosdk/presentation/common/app_theme.dart';

void main() {
  runApp(const ProviderScope(child: VideoSdkApp()));
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
      builder: (context, child) => _CallOverlay(child: child),
    );
  }
}

/// Presents the full-screen [CallScreen] above the active route whenever a call
/// is in progress, so an incoming call interrupts any screen and a placed call
/// covers the lobby. When the call returns to idle the overlay disappears.
class _CallOverlay extends ConsumerWidget {
  const _CallOverlay({required this.child});

  final Widget? child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final inCall = ref.watch(callControllerProvider) is! Idle;
    return Stack(
      children: [
        ?child,
        if (inCall) const Positioned.fill(child: CallScreen()),
      ],
    );
  }
}

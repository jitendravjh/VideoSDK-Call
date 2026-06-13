import 'package:flutter/foundation.dart';
import 'package:go_router/go_router.dart';
import 'package:meet_videosdk/application/call/call_controller.dart';
import 'package:meet_videosdk/application/lobby/session_controller.dart';
import 'package:meet_videosdk/data/models/call_state.dart';
import 'package:meet_videosdk/data/models/user.dart';
import 'package:meet_videosdk/presentation/call/call_screen.dart';
import 'package:meet_videosdk/presentation/history/call_history_screen.dart';
import 'package:meet_videosdk/presentation/lobby/lobby_screen.dart';
import 'package:meet_videosdk/presentation/lobby/sign_in_screen.dart';
import 'package:meet_videosdk/presentation/prejoin/prejoin_screen.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'app_router.g.dart';

class AppRoutes {
  const AppRoutes._();

  static const String signIn = '/';
  static const String lobby = '/lobby';
  static const String prejoin = '/prejoin';
  static const String call = '/call';
  static const String history = '/history';
}

@Riverpod(keepAlive: true)
GoRouter router(Ref ref) {
  final refresh = ValueNotifier(0);
  ref
    ..listen(sessionControllerProvider, (_, _) => refresh.value++)
    ..listen(callControllerProvider, (_, _) => refresh.value++)
    ..onDispose(refresh.dispose);

  return GoRouter(
    initialLocation: AppRoutes.signIn,
    refreshListenable: refresh,
    redirect: (context, state) {
      final signedIn = ref.read(sessionControllerProvider) != null;
      final location = state.matchedLocation;
      if (!signedIn) {
        return location == AppRoutes.signIn ? null : AppRoutes.signIn;
      }

      // A call (incoming, outgoing, or active) takes over the screen; an
      // incoming call interrupts whatever route is showing.
      final inCall = ref.read(callControllerProvider) is! Idle;
      if (inCall) {
        return location == AppRoutes.call ? null : AppRoutes.call;
      }
      if (location == AppRoutes.call || location == AppRoutes.signIn) {
        return AppRoutes.lobby;
      }
      return null;
    },
    routes: [
      GoRoute(
        path: AppRoutes.signIn,
        builder: (context, state) => const SignInScreen(),
      ),
      GoRoute(
        path: AppRoutes.lobby,
        builder: (context, state) => const LobbyScreen(),
      ),
      GoRoute(
        path: AppRoutes.prejoin,
        builder: (context, state) => PrejoinScreen(peer: state.extra! as User),
      ),
      GoRoute(
        path: AppRoutes.call,
        builder: (context, state) => const CallScreen(),
      ),
      GoRoute(
        path: AppRoutes.history,
        builder: (context, state) => const CallHistoryScreen(),
      ),
    ],
  );
}

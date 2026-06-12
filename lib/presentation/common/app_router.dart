import 'package:flutter/foundation.dart';
import 'package:go_router/go_router.dart';
import 'package:meet_videosdk/application/lobby/session_controller.dart';
import 'package:meet_videosdk/presentation/lobby/lobby_screen.dart';
import 'package:meet_videosdk/presentation/lobby/sign_in_screen.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'app_router.g.dart';

class AppRoutes {
  const AppRoutes._();

  static const String signIn = '/';
  static const String lobby = '/lobby';
}

@Riverpod(keepAlive: true)
GoRouter router(Ref ref) {
  final refresh = ValueNotifier(0);
  ref
    ..listen(sessionControllerProvider, (_, _) => refresh.value++)
    ..onDispose(refresh.dispose);

  return GoRouter(
    initialLocation: AppRoutes.signIn,
    refreshListenable: refresh,
    redirect: (context, state) {
      final signedIn = ref.read(sessionControllerProvider) != null;
      final atSignIn = state.matchedLocation == AppRoutes.signIn;
      if (!signedIn) {
        return atSignIn ? null : AppRoutes.signIn;
      }
      if (atSignIn) {
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
    ],
  );
}

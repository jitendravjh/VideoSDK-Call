import 'package:meet_videosdk/data/models/call_state.dart';

/// What the ringtone should be doing for a given [CallState]. The phone rings
/// only while an incoming call is pending; every other phase is silent (the
/// caller's outgoing state included, since there is no device ringback tone).
enum RingAction { incoming, stop }

RingAction ringActionFor(CallState state) =>
    state is Incoming ? RingAction.incoming : RingAction.stop;

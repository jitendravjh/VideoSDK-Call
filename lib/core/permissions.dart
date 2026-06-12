import 'package:flutter/foundation.dart';
import 'package:permission_handler/permission_handler.dart';

enum MediaPermissionResult { granted, denied, permanentlyDenied }

/// Thin wrapper over `permission_handler` for the mic (and optionally camera)
/// permissions a call needs. Collapses the per-permission statuses into a
/// single result the UI can act on, including the permanently-denied case that
/// requires sending the user to app settings.
///
/// On desktop and web, `permission_handler` does not drive the camera/mic
/// prompt; the OS or browser prompts when `getUserMedia` runs (backed by the
/// macOS entitlements and Info.plist usage strings). On those platforms this
/// reports `granted` so the flow proceeds to `getUserMedia`, where a denial
/// surfaces as a media error instead.
class MediaPermissions {
  const MediaPermissions();

  bool get isManaged =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);

  Future<MediaPermissionResult> request({required bool camera}) async {
    if (!isManaged) {
      return MediaPermissionResult.granted;
    }

    final permissions = <Permission>[
      Permission.microphone,
      if (camera) Permission.camera,
    ];

    final statuses = await permissions.request();
    final values = statuses.values;

    if (values.any((s) => s.isPermanentlyDenied || s.isRestricted)) {
      return MediaPermissionResult.permanentlyDenied;
    }
    if (values.any((s) => !s.isGranted && !s.isLimited)) {
      return MediaPermissionResult.denied;
    }
    return MediaPermissionResult.granted;
  }

  Future<void> openSettings() => openAppSettings();
}

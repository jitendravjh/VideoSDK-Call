import 'package:permission_handler/permission_handler.dart';

enum MediaPermissionResult { granted, denied, permanentlyDenied }

/// Thin wrapper over `permission_handler` for the mic (and optionally camera)
/// permissions a call needs. Collapses the per-permission statuses into a
/// single result the UI can act on, including the permanently-denied case that
/// requires sending the user to app settings.
class MediaPermissions {
  const MediaPermissions();

  Future<MediaPermissionResult> request({required bool camera}) async {
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

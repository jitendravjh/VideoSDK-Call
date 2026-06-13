import 'package:flutter/foundation.dart';
import 'package:permission_handler/permission_handler.dart';

enum MediaPermissionResult { granted, denied, permanentlyDenied }

/// Thin wrapper over `permission_handler` for the mic (and optionally camera)
/// permissions a call needs. Collapses the per-permission statuses into a
/// single result the UI can act on, including the permanently-denied case that
/// requires sending the user to app settings.
///
/// Only Android needs an explicit runtime request before `getUserMedia`. On
/// iOS, macOS, and web the OS or browser prompts when `getUserMedia` runs
/// (backed by the Info.plist usage strings and macOS entitlements), so this
/// reports `granted` there and lets a denial surface as a media error instead.
class MediaPermissions {
  const MediaPermissions();

  bool get isManaged =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

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

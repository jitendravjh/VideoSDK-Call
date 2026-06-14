import 'package:flutter/material.dart';

/// The "Back to home" action shown on the call/meeting terminal screens. A
/// filled button sized to its content (the app theme stretches filled buttons
/// full-width, so the size is overridden here) and centred by its parent.
class BackHomeButton extends StatelessWidget {
  const BackHomeButton({required this.onPressed, super.key});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return FilledButton.icon(
      onPressed: onPressed,
      style: FilledButton.styleFrom(
        minimumSize: const Size(0, 48),
        padding: const EdgeInsets.symmetric(horizontal: 28),
      ),
      icon: const Icon(Icons.home_outlined),
      label: const Text('Back to home'),
    );
  }
}

import 'package:flutter/material.dart';

class UserAvatar extends StatelessWidget {
  const UserAvatar({required this.name, this.radius = 20, super.key});

  final String name;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final initial = name.isNotEmpty ? name[0].toUpperCase() : '?';
    return CircleAvatar(
      radius: radius,
      backgroundColor: theme.colorScheme.primaryContainer,
      foregroundColor: theme.colorScheme.onPrimaryContainer,
      child: Text(
        initial,
        style: TextStyle(fontSize: radius * 0.8, fontWeight: FontWeight.w600),
      ),
    );
  }
}

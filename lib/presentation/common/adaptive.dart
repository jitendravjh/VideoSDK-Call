import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:meet_videosdk/presentation/common/liquid_glass.dart';

/// True on iOS, where the app renders Cupertino chrome; everything else
/// (Android, macOS, web) uses Material 3.
bool get isCupertino => !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;

/// A page scaffold + navigation bar that is Cupertino on iOS and Material
/// elsewhere. Pass [title] (or [titleWidget]) and an optional [trailing] action.
class AdaptiveScaffold extends StatelessWidget {
  const AdaptiveScaffold({
    required this.body,
    this.title,
    this.titleWidget,
    this.trailing,
    this.automaticallyImplyLeading = true,
    this.backgroundColor,
    super.key,
  });

  final Widget body;
  final String? title;
  final Widget? titleWidget;
  final Widget? trailing;
  final bool automaticallyImplyLeading;
  final Color? backgroundColor;

  @override
  Widget build(BuildContext context) {
    final hasNav = title != null || titleWidget != null;
    if (isCupertino) {
      return CupertinoPageScaffold(
        backgroundColor: backgroundColor,
        navigationBar: hasNav
            ? CupertinoNavigationBar(
                middle: titleWidget ?? Text(title!),
                trailing: trailing,
                automaticallyImplyLeading: automaticallyImplyLeading,
                backgroundColor: backgroundColor,
              )
            : null,
        child: SafeArea(child: body),
      );
    }
    return Scaffold(
      backgroundColor: backgroundColor,
      appBar: hasNav
          ? AppBar(
              title: titleWidget ?? Text(title!),
              automaticallyImplyLeading: automaticallyImplyLeading,
              actions: trailing == null ? null : [trailing!],
            )
          : null,
      body: SafeArea(child: body),
    );
  }
}

/// A full-width primary button: `CupertinoButton.filled` on iOS, `FilledButton`
/// elsewhere.
class AdaptiveButton extends StatelessWidget {
  const AdaptiveButton({
    required this.onPressed,
    required this.label,
    this.icon,
    this.tint,
    super.key,
  });

  final VoidCallback? onPressed;
  final String label;
  final IconData? icon;
  final Color? tint;

  @override
  Widget build(BuildContext context) {
    if (isCupertino) {
      // A tinted Liquid Glass capsule: prominent enough for a primary action
      // while keeping the translucent, blurred glass material.
      final tintColor = tint ?? Theme.of(context).colorScheme.primary;
      return SizedBox(
        width: double.infinity,
        child: CupertinoButton(
          onPressed: onPressed,
          padding: EdgeInsets.zero,
          child: LiquidGlass(
            color: tintColor,
            opacity: 0.85,
            borderRadius: BorderRadius.circular(16),
            padding: const EdgeInsets.symmetric(vertical: 15),
            child: _content(Colors.white),
          ),
        ),
      );
    }
    final style = tint == null
        ? null
        : FilledButton.styleFrom(backgroundColor: tint);
    if (icon != null) {
      return FilledButton.icon(
        onPressed: onPressed,
        style: style,
        icon: Icon(icon),
        label: Text(label),
      );
    }
    return FilledButton(onPressed: onPressed, style: style, child: Text(label));
  }

  Widget _content(Color color) {
    final style = TextStyle(
      color: color,
      fontWeight: FontWeight.w600,
      fontSize: 17,
    );
    if (icon == null) {
      return Text(label, style: style, textAlign: TextAlign.center);
    }
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 20, color: color),
        const SizedBox(width: 8),
        Text(label, style: style),
      ],
    );
  }
}

/// A borderless text button, Cupertino on iOS.
class AdaptiveTextButton extends StatelessWidget {
  const AdaptiveTextButton({
    required this.onPressed,
    required this.label,
    this.isDestructive = false,
    super.key,
  });

  final VoidCallback? onPressed;
  final String label;
  final bool isDestructive;

  @override
  Widget build(BuildContext context) {
    if (isCupertino) {
      return CupertinoButton(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        onPressed: onPressed,
        child: Text(
          label,
          style: TextStyle(
            color: isDestructive ? CupertinoColors.destructiveRed : null,
          ),
        ),
      );
    }
    return TextButton(
      onPressed: onPressed,
      style: isDestructive
          ? TextButton.styleFrom(
              foregroundColor: Theme.of(context).colorScheme.error,
            )
          : null,
      child: Text(label),
    );
  }
}

/// A text field that is `CupertinoTextField` on iOS and Material `TextField`
/// elsewhere.
class AdaptiveTextField extends StatelessWidget {
  const AdaptiveTextField({
    required this.controller,
    this.hintText,
    this.prefixIcon,
    this.autofocus = false,
    this.textCapitalization = TextCapitalization.none,
    this.textInputAction,
    this.onSubmitted,
    super.key,
  });

  final TextEditingController controller;
  final String? hintText;
  final IconData? prefixIcon;
  final bool autofocus;
  final TextCapitalization textCapitalization;
  final TextInputAction? textInputAction;
  final ValueChanged<String>? onSubmitted;

  @override
  Widget build(BuildContext context) {
    if (isCupertino) {
      return CupertinoTextField(
        controller: controller,
        placeholder: hintText,
        autofocus: autofocus,
        textCapitalization: textCapitalization,
        textInputAction: textInputAction,
        onSubmitted: onSubmitted,
        padding: const EdgeInsets.all(14),
        prefix: prefixIcon == null
            ? null
            : Padding(
                padding: const EdgeInsets.only(left: 12),
                child: Icon(prefixIcon, color: CupertinoColors.inactiveGray),
              ),
      );
    }
    return TextField(
      controller: controller,
      autofocus: autofocus,
      textCapitalization: textCapitalization,
      textInputAction: textInputAction,
      onSubmitted: onSubmitted,
      decoration: InputDecoration(
        hintText: hintText,
        prefixIcon: prefixIcon == null ? null : Icon(prefixIcon),
      ),
    );
  }
}

/// An icon button suited to a navigation bar.
class AdaptiveNavButton extends StatelessWidget {
  const AdaptiveNavButton({
    required this.icon,
    required this.onPressed,
    this.tooltip,
    super.key,
  });

  final IconData icon;
  final VoidCallback onPressed;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    if (isCupertino) {
      return CupertinoButton(
        padding: EdgeInsets.zero,
        onPressed: onPressed,
        child: Icon(icon),
      );
    }
    return IconButton(
      tooltip: tooltip,
      icon: Icon(icon),
      onPressed: onPressed,
    );
  }
}

/// A platform spinner (Cupertino activity indicator on iOS).
class AdaptiveSpinner extends StatelessWidget {
  const AdaptiveSpinner({this.size = 16, this.color, super.key});

  final double size;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CircularProgressIndicator.adaptive(
        strokeWidth: 2,
        valueColor: color == null ? null : AlwaysStoppedAnimation(color),
      ),
    );
  }
}

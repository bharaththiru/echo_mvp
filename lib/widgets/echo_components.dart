import 'package:flutter/material.dart';

import '../theme/echo_theme.dart';
import '../utils/responsive.dart';

class EchoCard extends StatelessWidget {
  const EchoCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(20),
    this.margin,
    this.onTap,
    this.color,
    this.borderColor,
    this.radius,
    this.overlayColor,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry? margin;
  final VoidCallback? onTap;
  final Color? color;
  final Color? borderColor;
  final double? radius;
  final Color? overlayColor;

  @override
  Widget build(BuildContext context) {
    final tokens = context.echo;
    final resolvedRadius = radius ?? EchoRadii.card;
    final resolvedColor = color ?? tokens.surface1;
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(resolvedRadius),
    );
    final content = Padding(padding: padding, child: child);

    final material = Material(
      color: resolvedColor,
      shape: shape,
      elevation: 1,
      shadowColor: tokens.shadow,
      clipBehavior: Clip.antiAlias,
      child: onTap == null
          ? content
          : InkWell(
              onTap: onTap,
              overlayColor: overlayColor == null
                  ? null
                  : WidgetStateProperty.all(overlayColor),
              child: content,
            ),
    );

    if (margin == null) {
      return material;
    }
    return Container(margin: margin, child: material);
  }
}

class EchoGradientCard extends StatelessWidget {
  const EchoGradientCard({
    super.key,
    required this.child,
    required this.gradient,
    this.glow = false,
    this.padding = const EdgeInsets.all(20),
    this.margin,
    this.onTap,
    this.borderColor,
    this.radius,
    this.overlayColor,
  });

  final Widget child;
  final Gradient gradient;
  final bool glow;
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry? margin;
  final VoidCallback? onTap;
  final Color? borderColor;
  final double? radius;
  final Color? overlayColor;

  static const List<BoxShadow> _glowShadow = [
    BoxShadow(
      color: Color(0x14000000),
      blurRadius: 18,
      offset: Offset(0, 8),
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final resolvedRadius = radius ?? EchoRadii.card;
    final content = Padding(padding: padding, child: child);

    final ink = Ink(
      decoration: BoxDecoration(
        gradient: gradient,
        borderRadius: BorderRadius.circular(resolvedRadius),
      ),
      child: content,
    );

    final material = Material(
      color: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(resolvedRadius),
      ),
      clipBehavior: Clip.antiAlias,
      child: onTap == null
          ? ink
          : InkWell(
              onTap: onTap,
              overlayColor: overlayColor == null
                  ? null
                  : WidgetStateProperty.all(overlayColor),
              child: ink,
            ),
    );

    final decorated = glow
        ? DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(resolvedRadius),
              boxShadow: _glowShadow,
            ),
            child: material,
          )
        : material;

    if (margin == null) {
      return decorated;
    }
    return Container(margin: margin, child: decorated);
  }
}

class EchoHeaderShell extends StatelessWidget {
  const EchoHeaderShell({super.key, required this.child, this.padding});

  final Widget child;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: padding ?? EdgeInsets.zero,
      child: child,
    );
  }
}

class EchoPrimaryButton extends StatelessWidget {
  const EchoPrimaryButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.isLoading = false,
    this.semanticLabel,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool isLoading;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final onButtonFill = theme.colorScheme.onPrimary;
    final loadingForeground = onButtonFill.withValues(alpha: 0.55);
    final height = EchoLayout.buttonHeight(context);
    return Semantics(
      button: true,
      label: semanticLabel ?? label,
      child: SizedBox(
        width: double.infinity,
        height: height,
        child: ElevatedButton(
          onPressed: isLoading ? null : onPressed,
          child: isLoading
              ? SizedBox(
                  height: 18,
                  width: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor:
                        AlwaysStoppedAnimation<Color>(loadingForeground),
                  ),
                )
              : Text(label),
        ),
      ),
    );
  }
}

class EchoSecondaryButton extends StatelessWidget {
  const EchoSecondaryButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final height = EchoLayout.secondaryButtonHeight(context);
    final child = icon == null
        ? Text(label)
        : Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 18),
              const SizedBox(width: 8),
              Text(label),
            ],
          );
    return SizedBox(
      width: double.infinity,
      height: height,
      child: OutlinedButton(onPressed: onPressed, child: child),
    );
  }
}

class EchoInput extends StatelessWidget {
  const EchoInput({
    super.key,
    required this.controller,
    this.hintText,
    this.labelText,
    this.prefixIcon,
    this.suffixIcon,
    this.keyboardType,
    this.textInputAction,
    this.obscureText = false,
    this.onChanged,
    this.onSubmitted,
    this.maxLength,
    this.autofillHints,
    this.textCapitalization = TextCapitalization.none,
    this.enabled = true,
  });

  final TextEditingController controller;
  final String? hintText;
  final String? labelText;
  final IconData? prefixIcon;
  final Widget? suffixIcon;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final bool obscureText;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final int? maxLength;
  final Iterable<String>? autofillHints;
  final TextCapitalization textCapitalization;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final tokens = context.echo;
    return TextField(
      controller: controller,
      keyboardType: keyboardType,
      textInputAction: textInputAction,
      obscureText: obscureText,
      onChanged: onChanged,
      onSubmitted: onSubmitted,
      maxLength: maxLength,
      autofillHints: autofillHints,
      textCapitalization: textCapitalization,
      enabled: enabled,
      style: Theme.of(context)
          .textTheme
          .bodyLarge
          ?.copyWith(color: tokens.textPrimary),
      decoration: InputDecoration(
        hintText: hintText,
        labelText: labelText,
        prefixIcon: prefixIcon == null
            ? null
            : Icon(prefixIcon, color: tokens.textSecondary),
        suffixIcon: suffixIcon,
      ),
    );
  }
}

class EchoSectionTitle extends StatelessWidget {
  const EchoSectionTitle(this.label, {super.key});

  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = context.echo;
    return Text(
      label,
      style: theme.textTheme.titleMedium?.copyWith(
        color: tokens.textSecondary,
        fontWeight: FontWeight.w600,
      ),
    );
  }
}

class EchoDivider extends StatelessWidget {
  const EchoDivider({super.key, this.height = 1});

  final double height;

  @override
  Widget build(BuildContext context) {
    return SizedBox(height: height);
  }
}

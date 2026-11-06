import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

/// Responsive shadcn button: text may wrap at large accessibility text sizes.
class StudioButton extends StatelessWidget {
  final VoidCallback? onPressed;
  final Widget child;
  final Widget? icon;
  final bool outline, ghost;
  final Color? color;
  const StudioButton({
    super.key,
    required this.onPressed,
    required this.child,
    this.icon,
    this.outline = false,
    this.ghost = false,
    this.color,
  });
  @override
  Widget build(BuildContext context) {
    final content = Row(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (icon != null) ...[icon!, const SizedBox(width: 8)],
        Flexible(child: child),
      ],
    );
    if (ghost) {
      return ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 40),
        child: ShadButton.ghost(
          onPressed: onPressed,
          enabled: onPressed != null,
          height: 0,
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          child: Flexible(child: content),
        ),
      );
    }
    if (outline) {
      return ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 40),
        child: ShadButton.outline(
          onPressed: onPressed,
          enabled: onPressed != null,
          height: 0,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          child: Flexible(child: content),
        ),
      );
    }
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 44),
      child: ShadButton(
        onPressed: onPressed,
        enabled: onPressed != null,
        backgroundColor: color,
        height: 0,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Flexible(child: content),
      ),
    );
  }
}

class StudioChoice extends StatelessWidget {
  final Widget label;
  final bool selected;
  final ValueChanged<bool>? onSelected;
  const StudioChoice({
    super.key,
    required this.label,
    required this.selected,
    this.onSelected,
  });
  @override
  Widget build(BuildContext context) {
    final c = ShadTheme.of(context).colorScheme;
    return Semantics(
      selected: selected,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 40),
        child: ShadButton.outline(
          onPressed: onSelected == null ? null : () => onSelected!(!selected),
          enabled: onSelected != null,
          backgroundColor: selected ? c.secondary : c.card,
          foregroundColor: selected ? c.primary : c.foreground,
          decoration: ShadDecoration(
            border: ShadBorder.all(
              color: selected ? c.primary : c.border,
              radius: BorderRadius.circular(8),
            ),
          ),
          height: 0,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Flexible(child: label),
        ),
      ),
    );
  }
}

class StudioToggle extends StatelessWidget {
  final Widget title;
  final Widget? subtitle;
  final bool value;
  final ValueChanged<bool>? onChanged;
  const StudioToggle({
    super.key,
    required this.title,
    this.subtitle,
    required this.value,
    required this.onChanged,
  });
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 12),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              DefaultTextStyle.merge(
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
                child: title,
              ),
              if (subtitle != null) ...[
                const SizedBox(height: 4),
                DefaultTextStyle.merge(
                  style: TextStyle(
                    fontSize: 12,
                    height: 1.5,
                    color: ShadTheme.of(context).colorScheme.mutedForeground,
                  ),
                  child: subtitle!,
                ),
              ],
            ],
          ),
        ),
        const SizedBox(width: 14),
        SizedBox(
          width: 48,
          height: 48,
          child: Center(
            child: ShadSwitch(
              value: value,
              enabled: onChanged != null,
              onChanged: onChanged,
            ),
          ),
        ),
      ],
    ),
  );
}

class StudioPanel extends StatelessWidget {
  final Widget child;
  final Color? color;
  final EdgeInsetsGeometry margin;
  const StudioPanel({
    super.key,
    required this.child,
    this.color,
    this.margin = const EdgeInsets.only(bottom: 12),
  });
  @override
  Widget build(BuildContext context) => Padding(
    padding: margin,
    child: ShadCard(
      width: double.infinity,
      padding: EdgeInsets.zero,
      backgroundColor: color,
      shadows: const [],
      child: child,
    ),
  );
}

class StudioNavigation extends StatelessWidget {
  final int index;
  final ValueChanged<int> onChanged;
  final List<String> labels;
  const StudioNavigation({
    super.key,
    required this.index,
    required this.onChanged,
    required this.labels,
  });
  @override
  Widget build(BuildContext context) {
    final c = ShadTheme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: c.card,
        border: Border(top: BorderSide(color: c.border)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
          child: Row(
            children: [
              for (var i = 0; i < labels.length; i++)
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 3),
                    child: Semantics(
                      selected: index == i,
                      child: ShadButton.ghost(
                        height: 60,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 4,
                          vertical: 6,
                        ),
                        backgroundColor: index == i ? c.secondary : c.card,
                        foregroundColor: index == i
                            ? c.primary
                            : c.mutedForeground,
                        onPressed: () => onChanged(i),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              [
                                LucideIcons.film,
                                LucideIcons.slidersHorizontal,
                                LucideIcons.images,
                              ][i],
                              size: 20,
                            ),
                            const SizedBox(height: 4),
                            Text(
                              labels[i],
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

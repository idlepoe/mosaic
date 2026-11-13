import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'ui/studio_components.dart';

class SettingsGroup extends StatelessWidget {
  final String title, description;
  final bool enabled;
  final String disabledReason;
  final List<Widget> children;
  final bool expanded;
  const SettingsGroup({
    super.key,
    required this.title,
    required this.description,
    required this.children,
    this.enabled = true,
    this.disabledReason = '',
    this.expanded = true,
  });
  @override
  Widget build(BuildContext context) {
    final colors = ShadTheme.of(context).colorScheme;
    return StudioPanel(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: ShadAccordion<String>.multiple(
          initialValue: expanded ? const ['section'] : const [],
          maintainState: true,
          children: [
            ShadAccordionItem(
              value: 'section',
              separator: const SizedBox.shrink(),
              underlineTitleOnHover: false,
              padding: const EdgeInsets.symmetric(vertical: 16),
              title: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: enabled ? colors.secondary : colors.muted,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(
                      enabled
                          ? LucideIcons.slidersHorizontal
                          : LucideIcons.lockKeyhole,
                      size: 16,
                      color: enabled ? colors.primary : colors.mutedForeground,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          enabled ? description : disabledReason,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w400,
                            height: 1.5,
                            color: colors.mutedForeground,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              child: Padding(
                // Focus rings paint outside control bounds; keep them inside
                // the accordion's animated clipping region.
                padding: const EdgeInsets.fromLTRB(8, 8, 8, 16),
                child: Semantics(
                  enabled: enabled,
                  child: ExcludeFocus(
                    excluding: !enabled,
                    child: AbsorbPointer(
                      absorbing: !enabled,
                      child: Opacity(
                        opacity: enabled ? 1 : .4,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: children,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

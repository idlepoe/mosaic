import 'package:flutter/material.dart';

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
  Widget build(BuildContext context) => Card(
    elevation: 0,
    margin: const EdgeInsets.only(bottom: 14),
    clipBehavior: Clip.antiAlias,
    child: ExpansionTile(
      key: PageStorageKey(title),
      initiallyExpanded: expanded,
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
      subtitle: Text(
        enabled ? description : disabledReason,
        style: TextStyle(
          color: enabled ? null : Theme.of(context).colorScheme.outline,
        ),
      ),
      leading: Icon(enabled ? Icons.tune : Icons.block_outlined),
      childrenPadding: const EdgeInsets.fromLTRB(16, 6, 16, 18),
      children: [
        Semantics(
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
      ],
    ),
  );
}

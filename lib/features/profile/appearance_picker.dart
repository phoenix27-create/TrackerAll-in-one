import 'package:flutter/material.dart';

import '../../core/theme.dart';

/// System / Light / Dark picker with mini previews of each mode.
/// Saved on the device and applied instantly.
class AppearancePicker extends StatelessWidget {
  const AppearancePicker({super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: ThemeController.instance,
      builder: (context, _) {
        final mode = ThemeController.instance.mode;
        return AppCard(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              for (final (m, label, icon) in const [
                (ThemeMode.system, 'System', Icons.brightness_auto_rounded),
                (ThemeMode.light, 'Light', Icons.light_mode_rounded),
                (ThemeMode.dark, 'Dark', Icons.dark_mode_rounded),
              ]) ...[
                Expanded(
                  child: _Option(
                    mode: m,
                    label: label,
                    icon: icon,
                    selected: mode == m,
                    onTap: () => ThemeController.instance.setMode(m),
                  ),
                ),
                if (m != ThemeMode.dark) const SizedBox(width: 10),
              ],
            ],
          ),
        );
      },
    );
  }
}

class _Option extends StatelessWidget {
  const _Option({
    required this.mode,
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });
  final ThemeMode mode;
  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      label: '$label theme',
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: selected ? AppColors.purple : AppColors.border,
              width: selected ? 2 : 1,
            ),
          ),
          child: Column(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(11),
                child: SizedBox(
                  height: 64,
                  child: switch (mode) {
                    ThemeMode.light => const _Mini(AppPalette.light),
                    ThemeMode.dark => const _Mini(AppPalette.dark),
                    ThemeMode.system => const Row(
                      children: [
                        Expanded(child: _Mini(AppPalette.light, half: true)),
                        Expanded(child: _Mini(AppPalette.dark, half: true)),
                      ],
                    ),
                  },
                ),
              ),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    icon,
                    size: 15,
                    color: selected ? AppColors.purple : AppColors.muted,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                      color: selected ? AppColors.purple : AppColors.text,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A tiny drawing of the app in palette [p]: page, a card, two bars.
class _Mini extends StatelessWidget {
  const _Mini(this.p, {this.half = false});
  final AppPalette p;
  final bool half;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: p.bg,
      padding: const EdgeInsets.all(7),
      child: Container(
        padding: const EdgeInsets.all(6),
        decoration: BoxDecoration(
          color: p.card,
          borderRadius: BorderRadius.circular(6),
          border: p.isDark ? Border.all(color: p.border) : null,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              height: 5,
              width: half ? 16 : 30,
              decoration: BoxDecoration(
                color: p.text.withValues(alpha: 0.8),
                borderRadius: BorderRadius.circular(3),
              ),
            ),
            const SizedBox(height: 5),
            Container(
              height: 5,
              decoration: BoxDecoration(
                color: p.orange,
                borderRadius: BorderRadius.circular(3),
              ),
            ),
            const SizedBox(height: 4),
            FractionallySizedBox(
              widthFactor: 0.6,
              child: Container(
                height: 5,
                decoration: BoxDecoration(
                  color: p.purple,
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

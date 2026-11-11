import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/theme.dart';

class RadialNavItem {
  const RadialNavItem({
    required this.icon,
    required this.label,
    required this.onTap,
    this.selected = false,
    this.color,
  });
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool selected;

  /// Solid colour for action bubbles (e.g. orange "Add expense").
  final Color? color;
}

/// Icon colour on light bubbles.
Color get _ink => AppColors.isDark ? AppColors.text : AppColors.navy;

/// Selected page bubble / closed main button (white icon on it).
Color get _accent => AppColors.isDark ? AppColors.purple : AppColors.navy;

/// Open main button background.
Color get _openBg => AppColors.isDark ? AppColors.raised : Colors.white;
Color get _bubble =>
    AppColors.isDark ? AppColors.raised : const Color(0xFFF1F8F4);

/// Small round menu button at the bottom centre. Tapping it blurs the screen
/// with an ocean tint and springs the buttons out in two half-circle arcs:
///   inner arc  -> quick actions (add expense / add salary)
///   outer arc  -> pages (Home, Expenses, Analytics, Salary)
/// Place it in a full-screen Stack above the page.
class RadialNavMenu extends StatefulWidget {
  const RadialNavMenu({
    super.key,
    required this.items,
    required this.actions,
    this.bottomGap = 0,
  });

  final List<RadialNavItem> items;
  final List<RadialNavItem> actions;

  /// Extra space under the button (e.g. above a hosting badge on the web).
  final double bottomGap;

  @override
  State<RadialNavMenu> createState() => _RadialNavMenuState();
}

class _RadialNavMenuState extends State<RadialNavMenu>
    with SingleTickerProviderStateMixin {
  late final _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 560),
    reverseDuration: const Duration(milliseconds: 380),
  );

  static const _main = 52.0;
  static const _size = 50.0;
  static const _outerR = 170.0;
  static const _innerR = 86.0;
  static const _margin = 20.0;

  bool get _open =>
      _c.status == AnimationStatus.forward ||
      _c.status == AnimationStatus.completed;

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  void _toggle() {
    HapticFeedback.mediumImpact();
    _open ? _c.reverse() : _c.forward();
    setState(() {});
  }

  void _close() {
    if (!_open) return;
    _c.reverse();
    setState(() {});
  }

  Future<void> _pick(RadialNavItem item) async {
    HapticFeedback.selectionClick();
    _close();
    // Let the blur fade a little before opening a sheet / switching page.
    await Future.delayed(const Duration(milliseconds: 160));
    item.onTap();
  }

  /// Angle 0 = straight up, -90° = left, +90° = right (button at bottom centre).
  Offset _offset(double degrees, double r) {
    final a = degrees * math.pi / 180;
    return Offset(r * math.sin(a), -r * math.cos(a));
  }

  @override
  Widget build(BuildContext context) {
    final safeBottom = MediaQuery.paddingOf(context).bottom;
    return PopScope(
      canPop: !_open,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _close();
      },
      child: Material(
        type: MaterialType.transparency,
        child: LayoutBuilder(
          builder: (context, box) {
            final center = Offset(
              box.maxWidth / 2,
              box.maxHeight -
                  _margin -
                  widget.bottomGap -
                  safeBottom -
                  _main / 2,
            );
            return AnimatedBuilder(
              animation: _c,
              builder: (context, _) {
                final t = Curves.easeOut.transform(_c.value);
                final bubbles = <Widget>[];

                void place(
                  RadialNavItem item,
                  double deg,
                  double r,
                  int order,
                ) {
                  // Staggered spring-out, reversed on close.
                  final start = (order * 0.07).clamp(0.0, 0.4);
                  final v = Interval(
                    start,
                    (start + 0.6).clamp(0.0, 1.0),
                    curve: Curves.easeOutBack,
                  ).transform(_c.value);
                  final p = center + _offset(deg, r) * v;
                  bubbles.add(
                    Positioned(
                      left: p.dx - 45,
                      top: p.dy - _size / 2,
                      width: 90,
                      child: IgnorePointer(
                        ignoring: _c.value < 0.6,
                        child: Opacity(
                          opacity: v.clamp(0.0, 1.0),
                          child: Transform.rotate(
                            angle: (1 - v) * math.pi,
                            child: Transform.scale(
                              scale: 0.4 + 0.6 * v.clamp(0.0, 1.2),
                              child: _Bubble(
                                item: item,
                                onTap: () => _pick(item),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  );
                }

                final n = widget.items.length;
                for (var i = 0; i < n; i++) {
                  place(
                    widget.items[i],
                    n == 1 ? 0 : -64 + 128.0 * i / (n - 1),
                    _outerR,
                    i + 2,
                  );
                }
                final m = widget.actions.length;
                for (var i = 0; i < m; i++) {
                  place(
                    widget.actions[i],
                    m == 1 ? 0 : -32 + 64.0 * i / (m - 1),
                    _innerR,
                    i,
                  );
                }

                return Stack(
                  children: [
                    // ------------------------------------ ocean blur layer --
                    if (_c.value > 0)
                      Positioned.fill(
                        child: GestureDetector(
                          onTap: _close,
                          child: ClipRect(
                            child: BackdropFilter(
                              filter: ui.ImageFilter.blur(
                                sigmaX: 10 * t,
                                sigmaY: 10 * t,
                              ),
                              child: DecoratedBox(
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(
                                    begin: Alignment.topLeft,
                                    end: Alignment.bottomRight,
                                    colors: [
                                      const Color(0xFF8FD8DE)
                                          .withValues(alpha: 0.35 * t),
                                      const Color(0xFF2A9DA8)
                                          .withValues(alpha: 0.45 * t),
                                      const Color(0xFF0B5F6B)
                                          .withValues(alpha: 0.65 * t),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ...bubbles,
                    // ------------------------------------------ main button --
                    Positioned(
                      left: center.dx - _main / 2,
                      top: center.dy - _main / 2,
                      child: _MainButton(
                        progress: _c,
                        open: _open,
                        onTap: _toggle,
                      ),
                    ),
                  ],
                );
              },
            );
          },
        ),
      ),
    );
  }
}

class _Bubble extends StatelessWidget {
  const _Bubble({required this.item, required this.onTap});
  final RadialNavItem item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final solid = item.color;
    // Selected page: navy in light mode, an inverted light bubble in dark
    // mode (so it never looks like the purple 'Add salary' action).
    final selBg = AppColors.isDark ? AppColors.text : AppColors.navy;
    final selFg = AppColors.isDark ? AppColors.bg : Colors.white;
    final bg = solid ?? (item.selected ? selBg : _bubble);
    final fg = solid != null ? Colors.white : (item.selected ? selFg : _ink);
    // The label is tappable too, not just the round bubble.
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Semantics(
            button: true,
            selected: item.selected,
            label: item.label,
            child: Material(
              color: bg,
              shape: const CircleBorder(),
              elevation: 6,
              shadowColor: Colors.black38,
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: onTap,
                child: SizedBox(
                  width: _RadialNavMenuState._size,
                  height: _RadialNavMenuState._size,
                  child: Icon(item.icon, color: fg, size: 22),
                ),
              ),
            ),
          ),
          const SizedBox(height: 5),
          Text(
            item.label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 11.5,
              fontWeight: FontWeight.w600,
              shadows: [Shadow(color: Colors.black45, blurRadius: 6)],
            ),
          ),
        ],
      ),
    );
  }
}

class _MainButton extends StatelessWidget {
  const _MainButton({
    required this.progress,
    required this.open,
    required this.onTap,
  });
  final Animation<double> progress;
  final bool open;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: open ? 'Close menu' : 'Open menu',
      child: Material(
        color: Color.lerp(_accent, _openBg, progress.value),
        shape: const CircleBorder(),
        elevation: 8,
        shadowColor: _accent.withValues(alpha: 0.5),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: SizedBox(
            width: _RadialNavMenuState._main,
            height: _RadialNavMenuState._main,
            child: Center(
              child: AnimatedIcon(
                icon: AnimatedIcons.menu_close,
                progress: progress,
                color: Color.lerp(Colors.white, _ink, progress.value),
                size: 24,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

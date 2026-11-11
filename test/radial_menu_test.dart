import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:life_tracker/features/expense/radial_menu.dart';

void main() {
  testWidgets('radial menu opens, picks, closes and survives rapid taps', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(400, 780);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    var page = 0, adds = 0;
    late StateSetter set;
    await tester.pumpWidget(
      MaterialApp(
        home: StatefulBuilder(
          builder: (context, s) {
            set = s;
            return Stack(
              children: [
                Scaffold(body: Text('page $page')),
                Positioned.fill(
                  child: RadialNavMenu(
                    actions: [
                      RadialNavItem(
                        icon: Icons.add,
                        label: 'Add expense',
                        onTap: () => adds++,
                      ),
                    ],
                    items: [
                      for (var i = 0; i < 4; i++)
                        RadialNavItem(
                          icon: Icons.circle,
                          label: 'P$i',
                          selected: page == i,
                          onTap: () => set(() => page = i),
                        ),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );

    final menu = find.bySemanticsLabel('Open menu');
    expect(menu, findsOneWidget);
    expect(find.text('P2'), findsOneWidget); // built but hidden

    // Open and pick a page.
    await tester.tap(menu);
    await tester.pumpAndSettle();
    await tester.tap(find.text('P2'));
    await tester.pumpAndSettle();
    expect(find.text('page 2'), findsOneWidget);

    // Open and use an action.
    await tester.tap(find.bySemanticsLabel('Open menu'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add expense'));
    await tester.pumpAndSettle();
    expect(adds, 1);

    // Tap the blurred background to close.
    await tester.tap(find.bySemanticsLabel('Open menu'));
    await tester.pumpAndSettle();
    await tester.tapAt(const Offset(40, 40));
    await tester.pumpAndSettle();
    expect(find.bySemanticsLabel('Open menu'), findsOneWidget);

    // Rapid toggling mid-animation.
    for (var i = 0; i < 12; i++) {
      await tester.tapAt(tester.getCenter(find.byType(AnimatedIcon)));
      await tester.pump(const Duration(milliseconds: 60));
    }
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}

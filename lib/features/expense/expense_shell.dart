import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme.dart';
import 'expense_controller.dart';
import 'expense_repository.dart';
import 'forms.dart';
import 'radial_menu.dart';
import 'models.dart';
import 'tabs/analytics_tab.dart';
import 'tabs/calendar_tab.dart';
import 'tabs/income_tab.dart';
import 'tabs/overview_tab.dart';
import 'widgets.dart';

/// Expense tracker: 4 tabs + centre "+" button (like the reference design).
class ExpenseShell extends StatelessWidget {
  const ExpenseShell({
    super.key,
    required this.uid,
    this.partnerView = false,
    this.ownerName,
  });
  final String uid;

  /// true = managing the partner's tracker (same features as your own).
  final bool partnerView;
  final String? ownerName;

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => ExpenseController(
        ExpenseRepository(uid),
        partnerView: partnerView,
        ownerName: ownerName,
      ),
      child: const _ExpenseScaffold(),
    );
  }
}

class _ExpenseScaffold extends StatefulWidget {
  const _ExpenseScaffold();
  @override
  State<_ExpenseScaffold> createState() => _ExpenseScaffoldState();
}

class _ExpenseScaffoldState extends State<_ExpenseScaffold> {
  int _tab = 0;
  bool _alertShown = false;
  DateTime? _calendarDay;

  static const _titles = [
    'Expense Tracker',
    'Expenses',
    'Analytics',
    'Salary & Goal',
  ];

  @override
  Widget build(BuildContext context) {
    final ctrl = context.watch<ExpenseController>();

    // Show the emergency alert once when opening the tracker in danger.
    if (!_alertShown &&
        !ctrl.loading &&
        ctrl.summary.status == BudgetStatus.danger) {
      _alertShown = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          showEmergencyDialog(
            context,
            ctrl.summary,
            ownerName: ctrl.partnerView
                ? (ctrl.ownerName ?? 'Your partner')
                : null,
          );
        }
      });
    }

    final pages = [
      OverviewTab(onOpenTab: (i) => setState(() => _tab = i)),
      CalendarTab(onDayChanged: (d) => _calendarDay = d),
      const AnalyticsTab(),
      const IncomeTab(),
    ];

    void go(int i) {
      if (i != _tab) setState(() => _tab = i);
    }

    return Stack(
      children: [
        Scaffold(
          appBar: AppBar(
            title: ctrl.partnerView
                ? Column(
                    children: [
                      Text(
                        "${ctrl.ownerName ?? 'Partner'}'s ${_titles[_tab] == 'Expense Tracker' ? 'Expenses' : _titles[_tab]}",
                      ),
                      const Text(
                        "💑 Partner's tracker",
                        style: TextStyle(
                          fontSize: 11,
                          color: Color(0xFFE91E63),
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  )
                : Text(_titles[_tab]),
          ),
          body: ctrl.error != null
              ? _ErrorView(error: ctrl.error!)
              : _AnimatedPages(index: _tab, pages: pages),
        ),
        // Corner menu button -> ocean-blur radial menu.
        Positioned.fill(
          child: RadialNavMenu(
            actions: [
              RadialNavItem(
                icon: Icons.add_rounded,
                label: 'Add expense',
                color: AppColors.orange,
                onTap: () => showExpenseSheet(
                  context,
                  ctrl,
                  date: _tab == 1 ? _calendarDay : null,
                ),
              ),
              RadialNavItem(
                icon: Icons.add_card_rounded,
                label: 'Add salary',
                color: AppColors.purple,
                onTap: () => showSalarySheet(context, ctrl),
              ),
            ],
            items: [
              RadialNavItem(
                icon: Icons.home_rounded,
                label: 'Home',
                selected: _tab == 0,
                onTap: () => go(0),
              ),
              RadialNavItem(
                icon: Icons.calendar_month_rounded,
                label: 'Expenses',
                selected: _tab == 1,
                onTap: () => go(1),
              ),
              RadialNavItem(
                icon: Icons.pie_chart_rounded,
                label: 'Analytics',
                selected: _tab == 2,
                onTap: () => go(2),
              ),
              RadialNavItem(
                icon: Icons.savings_rounded,
                label: 'Salary',
                selected: _tab == 3,
                onTap: () => go(3),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Keeps every tab alive (like IndexedStack) but fades + slides between them.
class _AnimatedPages extends StatelessWidget {
  const _AnimatedPages({required this.index, required this.pages});
  final int index;
  final List<Widget> pages;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        for (var i = 0; i < pages.length; i++)
          Positioned.fill(
            child: IgnorePointer(
              ignoring: i != index,
              child: ExcludeSemantics(
                excluding: i != index,
                child: AnimatedOpacity(
                  opacity: i == index ? 1 : 0,
                  duration: const Duration(milliseconds: 260),
                  curve: Curves.easeOut,
                  child: AnimatedSlide(
                    offset: i == index
                        ? Offset.zero
                        : Offset(i < index ? -0.06 : 0.06, 0),
                    duration: const Duration(milliseconds: 320),
                    curve: Curves.easeOutCubic,
                    child: TickerMode(enabled: i == index, child: pages[i]),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.error});
  final Object error;
  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Text(
        'Could not load your data.\n$error',
        textAlign: TextAlign.center,
        style: TextStyle(color: AppColors.muted),
      ),
    ),
  );
}

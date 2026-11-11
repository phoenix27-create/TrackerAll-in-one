import 'package:intl/intl.dart';

final _money = NumberFormat('#,##0');
final _compact = NumberFormat.compact();

/// 125000 -> "125,000 MMK"
String mmk(num value) => '${_money.format(value.round())} MMK';

/// 125000 -> "125,000"
String money(num value) => _money.format(value.round());

/// 1250000 -> "1.3M"
String compact(num value) => _compact.format(value);

String monthLabel(DateTime m) => DateFormat('MMMM yyyy').format(m);
String shortMonth(DateTime m) => DateFormat('MMM').format(m);
String dayLabel(DateTime d) => DateFormat('EEE, dd MMM yyyy').format(d);
String shortDay(DateTime d) => DateFormat('dd MMM').format(d);

DateTime monthStart(DateTime d) => DateTime(d.year, d.month);
DateTime nextMonth(DateTime d) => DateTime(d.year, d.month + 1);
DateTime prevMonth(DateTime d) => DateTime(d.year, d.month - 1);

/// Firestore doc id for a month: "2026-11".
String monthKey(DateTime d) => DateFormat('yyyy-MM').format(d);

bool sameDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

int daysInMonth(DateTime m) => DateTime(m.year, m.month + 1, 0).day;

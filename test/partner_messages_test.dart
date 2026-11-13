import 'package:flutter_test/flutter_test.dart';
import 'package:life_tracker/services/partner_service.dart';

void main() {
  PartnerActivity a(Map<String, dynamic> m) =>
      PartnerActivity.fromMap({'fromName': 'Mya Mya', ...m});

  test('income added', () {
    expect(a({'type': 'salary', 'amount': 500000}).title, contains('Mya added'));
    expect(a({'type': 'salary', 'amount': 500000}).title, contains('income'));
    expect(
      a({'type': 'salary', 'amount': 1, 'onYourTracker': true}).title,
      contains('to your tracker'),
    );
  });

  test('saving goal set', () {
    final x = a({'type': 'keep', 'keep': 100000, 'month': 'November 2026'});
    expect(x.title, contains('saving goal'));
    expect(x.body, 'For November 2026.');
  });

  test('spending above income vs below goal', () {
    final over = a({
      'type': 'alert',
      'remaining': -20000,
      'keep': 50000,
      'income': 300000,
      'spent': 320000,
    });
    expect(over.overIncome, isTrue);
    expect(over.title, contains('more than their income'));
    expect(over.body, contains('over'));

    // The case from the screenshot: 210,000 spent of 220,000, goal 44,000.
    final below = a({
      'type': 'alert',
      'remaining': 10000,
      'keep': 44000,
      'income': 220000,
      'spent': 210000,
    });
    expect(below.overIncome, isFalse);
    expect(below.title, contains('only'));
    expect(below.title, contains('10,000'));
    expect(below.body, contains('210,000'));
    expect(below.body, contains('220,000'));
    expect(below.body, contains('saving goal'));
  });

  test('expense message unchanged', () {
    expect(a({'type': 'expense', 'amount': 5000}).title, contains('Mya spent'));
  });
}

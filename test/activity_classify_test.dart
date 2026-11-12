import 'package:flutter_test/flutter_test.dart';
import 'package:life_tracker/services/activity_detector.dart';

void main() {
  test('classifies speeds into still / walking / running / driving', () {
    String c(List<double> s, {bool driving = false}) =>
        ActivityDetector.classify(driving: driving, speeds: s);
    expect(c([]), 'still');
    expect(c([0.1, 0.3, 0.2]), 'still');
    expect(c([1.3, 1.5, 1.4]), 'walking'); // ~5 km/h
    expect(c([3.5, 4.0, 3.8]), 'running'); // ~14 km/h (run / bike)
    expect(c([9.0, 10.0, 11.0]), 'driving');
    expect(c([0.2], driving: true), 'driving'); // stopped at a light
  });

  test('one GPS jump does not change the activity (median)', () {
    expect(ActivityDetector.classify(driving: false, speeds: [0.2, 0.3, 8.0]), 'still');
  });

  test('detector reports walking from a walk', () {
    final d = ActivityDetector();
    final t0 = DateTime(2026, 11, 12, 9);
    for (var i = 0; i < 5; i++) {
      d.onLocation(
        lat: 16.8 + i * 0.00012, // ~13 m per 10 s ≈ 1.3 m/s
        lng: 96.15,
        speed: 1.3,
        accuracy: 8,
        at: t0.add(Duration(seconds: i * 10)),
      );
    }
    expect(d.activity, 'walking');
  });
}

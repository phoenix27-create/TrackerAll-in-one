import 'package:flutter_test/flutter_test.dart';
import 'package:life_tracker/services/activity_detector.dart';

void main() {
  final t0 = DateTime(2026, 11, 11, 8);
  DateTime t(int s) => t0.add(Duration(seconds: s));
  List<String> ids(List<ActivityEvent> e) =>
      e.map((x) => x.toString()).toList();

  group('driving', () {
    test(
      'starts after two fast fixes, ignores a short stop, stops after 4 min',
      () {
        final d = ActivityDetector();
        expect(
          d.onLocation(
            lat: 16.80,
            lng: 96.15,
            speed: 8,
            accuracy: 10,
            at: t(0),
          ),
          isEmpty,
        );
        expect(
          ids(
            d.onLocation(
              lat: 16.801,
              lng: 96.15,
              speed: 9,
              accuracy: 10,
              at: t(15),
            ),
          ),
          ['driving_start'],
        );
        // Red light for 90 s: still driving.
        expect(
          d.onLocation(
            lat: 16.802,
            lng: 96.15,
            speed: 0.3,
            accuracy: 10,
            at: t(105),
          ),
          isEmpty,
        );
        expect(d.driving, isTrue);
        expect(
          d.onLocation(
            lat: 16.803,
            lng: 96.15,
            speed: 7,
            accuracy: 10,
            at: t(120),
          ),
          isEmpty,
        );
        // Parked for 4+ minutes.
        expect(
          d.onLocation(
            lat: 16.803,
            lng: 96.15,
            speed: 0,
            accuracy: 10,
            at: t(200),
          ),
          isEmpty,
        );
        expect(
          ids(
            d.onLocation(
              lat: 16.803,
              lng: 96.15,
              speed: 0,
              accuracy: 10,
              at: t(370),
            ),
          ),
          ['driving_stop'],
        );
      },
    );

    test('walking never counts as driving', () {
      final d = ActivityDetector();
      for (var i = 0; i < 10; i++) {
        expect(
          d.onLocation(
            lat: 16.8 + i * 0.0001,
            lng: 96.15,
            speed: 1.4,
            accuracy: 8,
            at: t(i * 10),
          ),
          isEmpty,
        );
      }
    });

    test('uses computed speed when the device reports none (web)', () {
      final d = ActivityDetector();
      // ~111 m per 10 s ≈ 11 m/s
      d.onLocation(lat: 16.800, lng: 96.15, speed: 0, accuracy: 10, at: t(0));
      d.onLocation(lat: 16.801, lng: 96.15, speed: 0, accuracy: 10, at: t(10));
      expect(
        ids(
          d.onLocation(
            lat: 16.802,
            lng: 96.15,
            speed: 0,
            accuracy: 10,
            at: t(20),
          ),
        ),
        ['driving_start'],
      );
    });
  });

  group('places', () {
    const home = SavedPlace(id: 'home', lat: 16.80, lng: 96.15, radius: 150);

    test('first fix is silent, then leave / arrive with a buffer', () {
      final d = ActivityDetector()..setPlaces([home]);
      expect(
        d.onLocation(lat: 16.80, lng: 96.15, speed: 0, accuracy: 10, at: t(0)),
        isEmpty,
      );
      // 180 m away: inside the 60 m buffer -> nothing yet.
      expect(
        d.onLocation(
          lat: 16.8016,
          lng: 96.15,
          speed: 0,
          accuracy: 10,
          at: t(30),
        ),
        isEmpty,
      );
      // ~330 m away -> left.
      expect(
        ids(
          d.onLocation(
            lat: 16.803,
            lng: 96.15,
            speed: 0,
            accuracy: 10,
            at: t(60),
          ),
        ),
        ['left_place(home)'],
      );
      // back home after the cooldown
      expect(
        ids(
          d.onLocation(
            lat: 16.8001,
            lng: 96.15,
            speed: 0,
            accuracy: 10,
            at: t(400),
          ),
        ),
        ['arrived_place(home)'],
      );
    });

    test('ignores inaccurate fixes', () {
      final d = ActivityDetector()..setPlaces([home]);
      d.onLocation(lat: 16.80, lng: 96.15, speed: 0, accuracy: 10, at: t(0));
      expect(
        d.onLocation(
          lat: 16.81,
          lng: 96.15,
          speed: 0,
          accuracy: 500,
          at: t(60),
        ),
        isEmpty,
      );
    });

    test('reads places from the profile map', () {
      final p = SavedPlace.fromProfile({
        'places': {
          'home': {'lat': 16.8, 'lng': 96.1, 'radius': 120},
          'work': {'lat': 16.7, 'lng': 96.2},
          'bad': 'x',
        },
      });
      expect(p.map((e) => e.id), ['home', 'work']);
      expect(p.first.radius, 120);
    });
  });

  group('battery', () {
    test('charging, full, low once per discharge', () {
      final d = ActivityDetector();
      expect(
        d.onBattery(level: 40, mode: BatteryMode.discharging, at: t(0)),
        isEmpty,
      );
      expect(
        ids(d.onBattery(level: 40, mode: BatteryMode.charging, at: t(10))),
        ['charging[40%]'],
      );
      expect(
        ids(d.onBattery(level: 100, mode: BatteryMode.full, at: t(3600))),
        ['battery_full[100%]'],
      );
      expect(
        d.onBattery(level: 99, mode: BatteryMode.discharging, at: t(3700)),
        isEmpty,
      );
      expect(
        ids(d.onBattery(level: 15, mode: BatteryMode.discharging, at: t(9000))),
        ['battery_low[15%]'],
      );
      expect(
        d.onBattery(level: 12, mode: BatteryMode.discharging, at: t(9600)),
        isEmpty,
      );
    });

    test('first reading never notifies', () {
      final d = ActivityDetector();
      expect(
        d.onBattery(level: 50, mode: BatteryMode.charging, at: t(0)),
        isEmpty,
      );
    });
  });
}

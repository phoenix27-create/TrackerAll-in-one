# LifeTrack – personal life trackers (Flutter + Firebase)

Phase 1 ships the **Expense Tracker**. Fitness, Partner Location, Habit, Sleep and
Water trackers are shown as "Coming soon" cards on the main menu.

Firebase project: **trackerapp-6bac1** (free **Spark** plan – no Cloud Functions needed).

## Features (phase 1)

| Area | What it does |
|---|---|
| Auth | Google sign-in, or email + password. Email users get a **verification link** by email (Firebase, free) and must tap it before using the app. The app detects it automatically. Includes forgot password. |
| Main menu | Card grid of trackers (Expense is live, others are "Coming soon"). Profile button (and tap on avatar) opens **My Profile**. |
| Profile | Edit name, phone, occupation, birthday, gender, avatar colour (or Google photo). Change password (email users), toggle reminders, log out. Saved to `users/{uid}`. |
| Partner | Every single user gets a 6-character **partner code** on the main menu. The partner taps **Connect with partner**, enters the code, and both accounts are linked (one partner only). Once linked, the main menu shows both names instead of the code, an **Open partner's expenses** button, and the latest partner activity. Each partner can fully manage the other's tracker: add, edit and delete expenses and salaries, set the keep amount, and get the same 80% and emergency alerts. Expenses added by the partner show "by Name". The other person is notified of every new expense and of a broken keep amount. **Disconnect needs both people:** one person sends a request, and the other must tap Confirm (or Stay connected). Security rules enforce this. |
| Location permission | Every user must allow location. The system prompt appears on first use. If it is refused, a full-screen "Allow your location" page keeps asking, and opens phone Settings when the prompt can no longer be shown. It checks again each time the app comes back. |
| Partner GPS | The **Partner Location** tracker shows the partner live on an OpenStreetMap map (free, no API key): an avatar pin, accuracy circle, "Live now / Last seen", distance from you, speed, and Partner / Me / Both buttons. While linked, each phone uploads its position to `users/{uid}/live/location` at most every 20 s, or sooner after moving 30 m. Android keeps sharing in the background with an ongoing "Sharing your location" notification; iOS uses the background-location mode. Only the owner and the linked partner can read it. |
| Location alerts | Your partner's phone detects: started / stopped driving (over ~22 km/h, stops after 4 min still), left / arrived at **Home** or **Work** (saved in the 🔔 sheet on the map, 150 m radius with a 60 m buffer), and phone charging / fully charged / battery ≤ 15 %. Each event goes to your inbox and shows as a notification. In the 🔔 sheet you choose which alert types you want. The map also shows Driving, At Home and battery chips. Logic is in `lib/services/activity_detector.dart` (unit-tested). |
| Directions | **Get directions to <partner>** draws the fastest route on the map, by car, bike or walking. It asks the free OpenStreetMap routing server (routing.openstreetmap.de, no key) for up to 3 alternatives and keeps the quickest. It shows the travel time, distance and arrival time, and re-routes automatically when either person moves more than 150 m. **Start navigation** opens Google Maps for turn-by-turn voice guidance with live traffic. The in-app time does not include traffic. The free routing server is for light use; for a large public release, host your own OSRM or use a keyed service. |
| Reminders | If nothing is logged today, a "No expense cost for today?"-style notification at 9 AM, 12 PM, 3 PM, 6 PM and 9 PM, each with a different message. Scheduled on the device 7 days ahead, and today's are cancelled once an expense is added. Android / iOS only. |
| Salary | Add as many salaries / incomes per month as you need (10,000 + 20,000 + 30,000 = 60,000 MMK total). |
| Expenses | Pick a date on the calendar, enter an amount, pick a category and a payment method (Cash, KBZPay, CB Pay, Yoma Pay, WavePay, AYA Pay, UAB Pay, OnePay, MyTel Pay, MPU, Visa/Master, Bank Transfer, Other). Add a note, edit or delete. |
| Keep amount | Auto suggestion = 20% of salary (adjustable 5–70%) **or** your own amount. |
| Alerts | When salary − expense drops **below the keep amount**: device notification + red emergency dialog + red balance card. Warning at 80% of the spendable budget. |
| Dashboard | Remaining balance, safe-to-spend, daily allowance, category pie chart, daily bar chart with ideal limit line, payment-method breakdown, 12-month salary vs expense chart, yearly totals, monthly history. |

## Project layout

```
lib/
  main.dart                     AuthGate: login -> verify email -> home
  firebase_options.dart         generated for trackerapp-6bac1
  core/                         theme (purple/orange cards), number & date format
  services/                     auth (Google + email link), local notifications
  features/auth/                login, register, verify email screens
  features/home/                main menu with tracker cards
  features/expense/             models, repository, controller, forms, widgets
  features/expense/tabs/        overview, calendar, analytics, salary & goal
firestore.rules                 each user can only read/write their own data
```

Firestore data (collections are created automatically on first save):

```
users/{uid}                      name, email, photoUrl, provider, currency
users/{uid}/salaries/{id}        amount, source, date, payment
users/{uid}/expenses/{id}        amount, category, payment, date, note
users/{uid}/months/{yyyy-MM}     keepAmount (null = auto), keepPercent
users/{uid}/inbox/{id}           partner activity (expense / alert / connect / disconnect)
users/{uid}/live/location        lat, lng, accuracy, speed, heading, updatedAt (partner GPS)
partnerCodes/{CODE}              { uid } – code lookup, get-only
```
`users/{uid}` also holds `partnerCode` (while single) or `partnerId` + `partnerSince` (when linked).

## Already done

- Android app `com.lifetrack.life_tracker` and iOS app `com.lifetrack.lifeTracker`
  registered in trackerapp-6bac1; `firebase_options.dart` and
  `android/app/google-services.json` generated.
- Debug SHA-1 / SHA-256 added to the Android app (for Google sign-in).
- `firestore.rules` deployed.
- Email/Password and Google sign-in enabled; `google-services.json` refreshed
  with the Google OAuth clients.
- iOS `Info.plist` has the Google sign-in URL scheme and `GIDClientID`.

## Still to do

1. **iOS (on a Mac):** run `flutterfire configure` once more there so it writes
   `ios/Runner/GoogleService-Info.plist`, and set `platform :ios, '15.0'` in `ios/Podfile`.
2. **Release builds:** add your release keystore SHA-1 / SHA-256 in Firebase
   (and the Play Console "App signing" SHA when you publish).

Optional: Authentication → Templates → Email address verification lets you change
the sender name and the email text (e.g. to "LifeTrack").

## Run

Phone / emulator:
```bash
flutter run
```

Web on localhost (for testing). Fast option, a release build served on http://localhost:8080:
```bash
flutter build web
```
```bash
node tool/serve_web.js
```
Rebuild after every code change. For hot reload while coding, use Chrome instead:
```bash
flutter run -d chrome --web-port 8080
```
On web, Google sign-in uses a popup, and budget alerts show only in the app
(phone notifications are mobile-only). `localhost` is already an authorized domain in Firebase.

## Tests
```bash
flutter test
```

Security-rules tests (partner linking, who can read what). These need Java and use the Firestore emulator:
```bash
cd rules_test && npm install && npm test
```

## Partner notifications – how they work without Blaze
Adding an expense writes a small item to the partner's `users/{partnerId}/inbox`.
The partner's app listens to that inbox and shows a phone notification. This
happens instantly while the app is open or in the background. If the app was
fully closed, the notifications appear the next time it is opened. Instant
delivery to a fully closed app needs a server (FCM through Cloud Functions,
which needs Blaze, or a free external host).

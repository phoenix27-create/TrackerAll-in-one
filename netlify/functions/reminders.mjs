// Scheduled every 30 minutes by Netlify.
// Sends the "Did you log your expenses?" reminder at 09:00, 12:00, 15:00,
// 18:00 and 21:00 in each user's own time zone, only on days with no expense
// logged yet, and only to users who did not switch reminders off.

import { db, missingConfig, sendToUser } from '../lib/push.mjs';
import { Timestamp } from 'firebase-admin/firestore';

export const config = { schedule: '*/30 * * * *' };

const SLOTS = [9, 12, 15, 18, 21];

// Same messages as lib/services/reminder_service.dart.
const MESSAGES = [
  ['No expense cost for today? 🤔', 'Tap to log what you spent today and keep your budget on track.'],
  ['Spent anything yet today? 💸', 'Even a small tea shop bill counts. Add it now in 5 seconds.'],
  ['Your wallet misses you 👛', 'Nothing logged today. Did you pay with Cash, KBZPay or WavePay?'],
  ['Quick check-in ⏰', "Log today's expenses so your savings goal stays safe."],
  ['Lunch, taxi, top-up? 🍜🚕', "Don't forget to record today's spending."],
  ['Keep your streak going 🔥', "Add today's expenses and see how much you can still spend."],
  ['Budget buddy here 🤝', 'Your expense tracker is empty for today. Want to fill it in?'],
  ['Little costs add up 📈', "Record today's spending before you forget the details."],
  ['Did today cost nothing? 😮', 'If you spent money, add it now. If not, great job saving!'],
  ['Evening money check 🌙', 'Take a minute to log what you spent today.'],
  ['Protect your keep amount 🛡️', 'Logging every expense helps you avoid the emergency alert.'],
  ['Hey, quick reminder! ✍️', "Open LifeTrack and add today's expenses."],
  ['Know where your money went 🔍', 'Nothing recorded today yet. Add your expenses now.'],
  ['Small habit, big savings 💰', "Log today's spending – it only takes a moment."],
  ['Mingalarbar! 🙏', 'How much did you spend today? Add it to your tracker.'],
];

/** The slot due for a user [tzOffset] minutes east of UTC, or null. */
export function dueSlot(nowMs, tzOffset) {
  const local = new Date(nowMs + tzOffset * 60000);
  const h = local.getUTCHours();
  if (local.getUTCMinutes() >= 30 || !SLOTS.includes(h)) return null;
  const y = local.getUTCFullYear();
  const m = local.getUTCMonth();
  const d = local.getUTCDate();
  const dayStart = Date.UTC(y, m, d) - tzOffset * 60000;
  return {
    key: `${y}-${m + 1}-${d}-${h}`,
    dayStart,
    dayEnd: dayStart + 24 * 3600 * 1000,
    message: MESSAGES[(d * SLOTS.length + SLOTS.indexOf(h)) % MESSAGES.length],
  };
}

export default async () => {
  if (missingConfig().length) {
    console.warn('reminders: not configured', missingConfig());
    return;
  }
  const now = Date.now();
  const subs = await db().collectionGroup('push').get();

  // One time zone per user (their newest device).
  const users = new Map();
  for (const d of subs.docs) {
    const uid = d.ref.parent.parent?.id;
    if (!uid) continue;
    const tz = Number(d.get('tzOffset')) || 0;
    const at = d.get('updatedAt')?.toMillis?.() ?? 0;
    const prev = users.get(uid);
    if (!prev || at > prev.at) users.set(uid, { tz, at });
  }

  let sent = 0;
  for (const [uid, { tz }] of users) {
    const slot = dueSlot(now, tz);
    if (!slot) continue;
    try {
      const userRef = db().collection('users').doc(uid);
      const profile = await userRef.get();
      if (!profile.exists || profile.get('expenseReminders') === false) continue;
      if (profile.get('reminderSentSlot') === slot.key) continue; // already sent

      const logged = await userRef
        .collection('expenses')
        .where('date', '>=', Timestamp.fromMillis(slot.dayStart))
        .where('date', '<', Timestamp.fromMillis(slot.dayEnd))
        .limit(1)
        .get();
      if (!logged.empty) continue;

      const [title, body] = slot.message;
      sent += await sendToUser(uid, { title, body, tag: 'expense-reminder' });
      await userRef.update({ reminderSentSlot: slot.key });
    } catch (e) {
      console.warn('reminder failed for a user', e.message);
    }
  }
  console.log(`reminders: ${users.size} users checked, ${sent} sent`);
};

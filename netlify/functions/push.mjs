// POST /.netlify/functions/push
// Authorization: Bearer <Firebase ID token>
// { to, type, title, body, inboxId? }
//
// Sends a push notification to [to]. Allowed only to yourself or to your
// linked partner. The receiver's alert switches (driving / places /
// battery) are respected.

import { auth, db, json, missingConfig, sendToUser } from '../lib/push.mjs';

const PREF_FOR = {
  driving_start: 'driving',
  driving_stop: 'driving',
  left_place: 'places',
  arrived_place: 'places',
  charging: 'battery',
  battery_full: 'battery',
  battery_low: 'battery',
};

const clip = (v, n) => (typeof v === 'string' ? v.slice(0, n) : '');

export default async (req) => {
  if (req.method !== 'POST') return json(405, { error: 'POST only' });
  const missing = missingConfig();
  if (missing.length) return json(503, { error: 'not configured', missing });

  let caller;
  try {
    const token = (req.headers.get('authorization') || '').replace(/^Bearer\s+/i, '');
    caller = (await auth().verifyIdToken(token)).uid;
  } catch {
    return json(401, { error: 'sign in required' });
  }

  let input;
  try {
    input = await req.json();
  } catch {
    return json(400, { error: 'bad json' });
  }
  const to = clip(input.to, 128);
  const type = clip(input.type, 40);
  const title = clip(input.title, 120);
  const body = clip(input.body, 300);
  const inboxId = clip(input.inboxId, 128);
  if (!to || !title) return json(400, { error: 'to and title are required' });

  const profile = await db().collection('users').doc(to).get();
  if (!profile.exists) return json(404, { error: 'no such user' });
  if (to !== caller && profile.get('partnerId') !== caller) {
    return json(403, { error: 'only your partner can be notified' });
  }
  const pref = PREF_FOR[type];
  if (pref && (profile.get('locationAlerts') || {})[pref] === false) {
    return json(200, { sent: 0, muted: true });
  }

  const sent = await sendToUser(to, { title, body, tag: type || 'lifetrack' });
  if (sent > 0 && inboxId) {
    // Lets the receiver's open app know it doesn't need to show it again.
    await db()
      .doc(`users/${to}/inbox/${inboxId}`)
      .update({ pushed: true })
      .catch(() => {});
  }
  return json(200, { sent });
};

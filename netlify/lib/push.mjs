// Shared helpers for the LifeTrack push functions.
//
// Web Push is sent straight to the browser's push service (Apple / Google /
// Mozilla) with our own VAPID keys, so no Firebase Cloud Functions (Blaze)
// are needed. Firestore is read with the Admin SDK (free on Spark).
//
// Netlify environment variables (Site settings → Environment variables,
// scope "Functions"):
//   FIREBASE_CLIENT_EMAIL  – from the service-account JSON ("client_email")
//   FIREBASE_PRIVATE_KEY   – from the service-account JSON ("private_key")
//   VAPID_PRIVATE_KEY      – private half of the VAPID key pair

import { cert, getApps, initializeApp } from 'firebase-admin/app';
import { getAuth } from 'firebase-admin/auth';
import { getFirestore } from 'firebase-admin/firestore';
import webpush from 'web-push';

export const PROJECT_ID = 'trackerapp-6bac1';

// Public half of the VAPID key pair (same value as in lib/services/push_service.dart).
export const VAPID_PUBLIC_KEY =
  'BPk1a2hD1lm_Mdt_KQQTvDyS9ISDBOsQcvl9NYJbeC5OzhxO_-qz8uPYa1s7HTgmnvQKLXHg-vOj4PqqgXX1fOU';

let ready = false;

export function missingConfig() {
  return ['FIREBASE_CLIENT_EMAIL', 'FIREBASE_PRIVATE_KEY', 'VAPID_PRIVATE_KEY'].filter(
    (k) => !process.env[k],
  );
}

function setup() {
  if (ready) return;
  if (!getApps().length) {
    initializeApp({
      credential: cert({
        projectId: PROJECT_ID,
        clientEmail: process.env.FIREBASE_CLIENT_EMAIL,
        // Pasted keys often keep "\n" as two characters.
        privateKey: (process.env.FIREBASE_PRIVATE_KEY || '').replace(/\\n/g, '\n'),
      }),
    });
  }
  webpush.setVapidDetails(
    'https://lifetrack-01.netlify.app',
    VAPID_PUBLIC_KEY,
    process.env.VAPID_PRIVATE_KEY,
  );
  ready = true;
}

export function db() {
  setup();
  return getFirestore();
}

export function auth() {
  setup();
  return getAuth();
}

/**
 * Sends one notification to every device [uid] registered.
 * Removes subscriptions the push service says are gone.
 * Returns how many devices accepted it.
 */
export async function sendToUser(uid, { title, body, tag, url = '/' }) {
  setup();
  const subs = await db().collection('users').doc(uid).collection('push').get();
  const payload = JSON.stringify({ title, body, tag, url });
  let sent = 0;
  await Promise.all(
    subs.docs.map(async (d) => {
      const s = d.data();
      try {
        await webpush.sendNotification(
          { endpoint: s.endpoint, keys: { p256dh: s.p256dh, auth: s.auth } },
          payload,
          { TTL: 24 * 3600, urgency: 'high' },
        );
        sent++;
      } catch (e) {
        if (e.statusCode === 404 || e.statusCode === 410) {
          await d.ref.delete().catch(() => {});
        } else {
          console.warn('push failed', e.statusCode, e.body || e.message);
        }
      }
    }),
  );
  return sent;
}

export const json = (status, data) =>
  new Response(JSON.stringify(data), {
    status,
    headers: { 'content-type': 'application/json' },
  });

import { initializeTestEnvironment, assertSucceeds, assertFails } from '@firebase/rules-unit-testing';
import { doc, getDoc, setDoc, updateDoc, deleteDoc, deleteField, addDoc, collection, getDocs, runTransaction, writeBatch, serverTimestamp, Timestamp } from 'firebase/firestore';
import fs from 'fs';

const env = await initializeTestEnvironment({
  projectId: 'demo-lifetrack',
  firestore: { rules: fs.readFileSync(process.argv[2], 'utf8'), host: '127.0.0.1', port: 8085 },
});
const db = (uid) => env.authenticatedContext(uid, { email_verified: true, firebase: { sign_in_provider: 'password' } }).firestore();
let pass = 0, fail = 0;
async function t(name, p) { try { await p; pass++; console.log('ok  ', name); } catch (e) { fail++; console.log('FAIL', name, e.message); } }

await env.withSecurityRulesDisabled(async (c) => {
  const f = c.firestore();
  await setDoc(doc(f, 'users/A'), { name: 'Alice', partnerCode: 'AAAAAA' });
  await setDoc(doc(f, 'partnerCodes/AAAAAA'), { uid: 'A' });
  await setDoc(doc(f, 'users/B'), { name: 'Bob', partnerCode: 'BBBBBB' });
  await setDoc(doc(f, 'partnerCodes/BBBBBB'), { uid: 'B' });
  await setDoc(doc(f, 'users/C'), { name: 'Carol', partnerCode: 'CCCCCC' });
  await setDoc(doc(f, 'partnerCodes/CCCCCC'), { uid: 'C' });
  await setDoc(doc(f, 'users/A/expenses/e1'), { amount: 100, category: 'food', payment: 'cash', date: Timestamp.now() });
});

const A = db('A'), B = db('B'), C = db('C');
await t('B cannot read A before linking', assertFails(getDoc(doc(B, 'users/A'))));
await t('B cannot read A expenses before linking', assertFails(getDocs(collection(B, 'users/A/expenses'))));
await t('codes cannot be listed', assertFails(getDocs(collection(B, 'partnerCodes'))));
await t('code get works', assertSucceeds(getDoc(doc(B, 'partnerCodes/AAAAAA'))));
await t('B cannot link A without linking self', assertFails(updateDoc(doc(B, 'users/A'), { partnerId: 'B' })));
await t('B cannot set other fields on A', assertFails(runTransaction(B, async (tx) => {
  tx.update(doc(B, 'users/A'), { partnerId: 'B', name: 'hacked' });
  tx.set(doc(B, 'users/B'), { partnerId: 'A' }, { merge: true });
})));

// Real connect (same as the app)
await t('B connects with A code', assertSucceeds(runTransaction(B, async (tx) => {
  await tx.get(doc(B, 'users/B'));
  await tx.get(doc(B, 'partnerCodes/AAAAAA'));
  tx.update(doc(B, 'users/A'), { partnerId: 'B', partnerSince: serverTimestamp(), partnerCode: deleteField() });
  tx.set(doc(B, 'users/B'), { partnerId: 'A', partnerSince: serverTimestamp(), partnerCode: deleteField() }, { merge: true });
  tx.delete(doc(B, 'partnerCodes/AAAAAA'));
  tx.delete(doc(B, 'partnerCodes/BBBBBB'));
})));
await t('B reads A profile', assertSucceeds(getDoc(doc(B, 'users/A'))));
await t('B reads A expenses', assertSucceeds(getDocs(collection(B, 'users/A/expenses'))));
await t('A reads B expenses', assertSucceeds(getDocs(collection(A, 'users/B/expenses'))));
await t('B edits A expense (partner = full access)', assertSucceeds(updateDoc(doc(B, 'users/A/expenses/e1'), { amount: 150 })));
await t('B adds A expense', assertSucceeds(addDoc(collection(B, 'users/A/expenses'), { amount: 5, category: 'food', payment: 'cash', date: Timestamp.now(), addedBy: 'B', addedByName: 'Bob' })));
await t('B sets A keep amount', assertSucceeds(setDoc(doc(B, 'users/A/months/2026-11'), { keepAmount: 1000 }, { merge: true })));
await t('B adds A salary', assertSucceeds(addDoc(collection(B, 'users/A/salaries'), { amount: 500, source: 'x', date: Timestamp.now() })));
await t('B deletes A expense', assertSucceeds(deleteDoc(doc(B, 'users/A/expenses/e1'))));
await t('B cannot edit A profile name', assertFails(updateDoc(doc(B, 'users/A'), { name: 'hacked' })));
await t('B sends inbox to A', assertSucceeds(addDoc(collection(B, 'users/A/inbox'), { type: 'expense', from: 'B', notified: false, amount: 5 })));
await t('B sends driving alert to A', assertSucceeds(addDoc(collection(B, 'users/A/inbox'), { type: 'driving_start', from: 'B', notified: false })));
await t('B sends battery alert to A', assertSucceeds(addDoc(collection(B, 'users/A/inbox'), { type: 'battery_low', from: 'B', battery: 12, notified: false })));
await t('unknown inbox type is rejected', assertFails(addDoc(collection(B, 'users/A/inbox'), { type: 'spam', from: 'B', notified: false })));
await t('B sends alert to A', assertSucceeds(addDoc(collection(B, 'users/A/inbox'), { type: 'alert', from: 'B', notified: false })));
await t('C cannot send inbox to A', assertFails(addDoc(collection(C, 'users/A/inbox'), { type: 'expense', from: 'C', notified: false })));
await t('C cannot read A expenses', assertFails(getDocs(collection(C, 'users/A/expenses'))));
await t('C cannot add A expense', assertFails(addDoc(collection(C, 'users/A/expenses'), { amount: 5, category: 'food', payment: 'cash', date: Timestamp.now() })));
// C tries to steal A (A already linked)
await t('C cannot link with linked A', assertFails(runTransaction(C, async (tx) => {
  tx.update(doc(C, 'users/A'), { partnerId: 'C' });
  tx.set(doc(C, 'users/C'), { partnerId: 'A' }, { merge: true });
})));
await t('C cannot self-set partnerId', assertFails(setDoc(doc(C, 'users/C'), { partnerId: 'A' }, { merge: true })));

// Disconnect needs both people
await t('A cannot clear own link alone', assertFails(updateDoc(doc(A, 'users/A'), { partnerId: null, partnerSince: null })));
await t('A cannot unlink B alone', assertFails((async () => {
  const b = writeBatch(A);
  b.update(doc(A, 'users/B'), { partnerId: null, partnerSince: null });
  b.update(doc(A, 'users/A'), { partnerId: null, partnerSince: null });
  await b.commit();
})()));
await t('A cannot delete own profile while linked', assertFails(deleteDoc(doc(A, 'users/A'))));
await t('A requests disconnect', assertSucceeds(updateDoc(doc(A, 'users/A'), { disconnectRequestedAt: serverTimestamp() })));
await t('A still cannot unlink alone after own request', assertFails(updateDoc(doc(A, 'users/A'), { partnerId: null, partnerSince: null })));
await t('B declines (stay connected)', assertSucceeds(updateDoc(doc(B, 'users/A'), { disconnectRequestedAt: null })));
await t('B cannot confirm without a request', assertFails((async () => {
  const b = writeBatch(B);
  b.update(doc(B, 'users/A'), { partnerId: null, partnerSince: null, disconnectRequestedAt: null });
  b.update(doc(B, 'users/B'), { partnerId: null, partnerSince: null, disconnectRequestedAt: null });
  await b.commit();
})()));
await updateDoc(doc(A, 'users/A'), { disconnectRequestedAt: serverTimestamp() });
await t('B confirms disconnect', assertSucceeds((async () => {
  const b = writeBatch(B);
  b.update(doc(B, 'users/A'), { partnerId: null, partnerSince: null, disconnectRequestedAt: null });
  b.update(doc(B, 'users/B'), { partnerId: null, partnerSince: null, disconnectRequestedAt: null });
  await b.commit();
})()));
await t('B cannot read A after disconnect', assertFails(getDocs(collection(B, 'users/A/expenses'))));
await t('B cannot write A after disconnect', assertFails(addDoc(collection(B, 'users/A/expenses'), { amount: 5, category: 'food', payment: 'cash', date: Timestamp.now() })));
await t('A creates new code', assertSucceeds(setDoc(doc(A, 'partnerCodes/NEWAAA'), { uid: 'A' })));
await t('C cannot take over existing code', assertFails(setDoc(doc(C, 'partnerCodes/NEWAAA'), { uid: 'C' })));

console.log(`\n${pass} passed, ${fail} failed`);
await env.cleanup();
process.exit(fail ? 1 : 0);

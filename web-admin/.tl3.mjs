import { readFileSync } from 'node:fs';
import { initializeApp } from 'firebase/app';
import { getAuth, signInWithEmailAndPassword } from 'firebase/auth';
import { getFirestore, collection, query, limit, getDocs } from 'firebase/firestore';
const env = Object.fromEntries(readFileSync('.env.local','utf8').split('\n').filter(l=>l.startsWith('VITE_'))
  .map(l=>{const i=l.indexOf('=');return [l.slice(0,i).trim(), l.slice(i+1).trim()];}));
const app = initializeApp({ apiKey: env.VITE_FIREBASE_API_KEY, authDomain: env.VITE_FIREBASE_AUTH_DOMAIN,
  projectId: env.VITE_FIREBASE_PROJECT_ID, storageBucket: env.VITE_FIREBASE_STORAGE_BUCKET,
  messagingSenderId: env.VITE_FIREBASE_MESSAGING_SENDER_ID, appId: env.VITE_FIREBASE_APP_ID });
const db = getFirestore(app);
await signInWithEmailAndPassword(getAuth(app), 'rm.riasatali@gmail.com', 'riasat@1234');

const users = await getDocs(collection(db, 'users'));
for (const u of users.docs) {
  const contacts = await getDocs(query(collection(db,'users',u.id,'contacts'), limit(400)));
  let withTl = 0, withNotes = 0, tlTotal = 0;
  const samples = [];
  for (const c of contacts.docs) {
    const [tl, nt] = await Promise.all([
      getDocs(query(collection(db,'users',u.id,'contacts',c.id,'timeline'), limit(20))),
      getDocs(query(collection(db,'users',u.id,'contacts',c.id,'notes'), limit(5))),
    ]);
    if (tl.size) { withTl++; tlTotal += tl.size; if (samples.length < 2) samples.push({ c, tl }); }
    if (nt.size) withNotes++;
  }
  console.log('user ' + u.id + ' — ' + contacts.size + ' contacts scanned');
  console.log('   contacts with timeline entries: ' + withTl + ' (' + tlTotal + ' entries)');
  console.log('   contacts with notes           : ' + withNotes);
  for (const s of samples) {
    console.log('   sample: /users/' + u.id + '/contacts/' + s.c.id + '  (' + s.c.data().fullName + ')');
    s.tl.docs.slice(0,3).forEach(d => {
      const x = d.data();
      console.log('      ' + JSON.stringify({label:x.label, title:x.title, subtitle:x.subtitle,
        date: x.date?.seconds ? new Date(x.date.seconds*1000).toDateString() : null}));
    });
  }
}
process.exit(0);

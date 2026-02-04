/* eslint-disable no-console */
const fs = require('fs');
const path = require('path');

let admin;
try {
  admin = require('firebase-admin');
} catch (err) {
  console.error(
    'Missing dependency: firebase-admin. Install with: npm install firebase-admin',
  );
  process.exit(1);
}

const seedPath = path.join(__dirname, 'hashtag_seed.json');
const raw = fs.readFileSync(seedPath, 'utf8');
const seeds = JSON.parse(raw);

if (!Array.isArray(seeds)) {
  throw new Error('hashtag_seed.json must be an array.');
}

admin.initializeApp({
  credential: admin.credential.applicationDefault(),
});

const db = admin.firestore();

const slugify = (value) =>
  value
    .toLowerCase()
    .replace(/^#+/, '')
    .replace(/[^a-z0-9]+/g, '');

const normalizeSeed = (seed) => {
  if (!seed || typeof seed !== 'object') {
    throw new Error('Each seed must be an object.');
  }
  const name = typeof seed.name === 'string' ? seed.name.trim() : '';
  if (!name) {
    throw new Error('Each seed must include a non-empty name.');
  }
  const id =
    typeof seed.id === 'string' && seed.id.trim()
      ? seed.id.trim()
      : slugify(name);
  if (!id) {
    throw new Error(`Unable to derive id from name: ${name}`);
  }
  const description =
    typeof seed.description === 'string' ? seed.description.trim() : '';
  const isActive =
    typeof seed.is_active === 'boolean' ? seed.is_active : true;

  return { id, name, description, isActive };
};

const commitBatch = async (batch, count) => {
  if (count === 0) {
    return;
  }
  await batch.commit();
};

const run = async () => {
  const MAX_BATCH = 400;
  let batch = db.batch();
  let pending = 0;
  let total = 0;

  for (const seed of seeds) {
    const normalized = normalizeSeed(seed);
    const docRef = db.collection('hashtags').doc(normalized.id);
    const payload = {
      name: normalized.name,
      is_active: normalized.isActive,
    };
    if (normalized.description) {
      payload.description = normalized.description;
    }

    batch.set(docRef, payload, { merge: true });
    pending += 1;
    total += 1;

    if (pending >= MAX_BATCH) {
      await commitBatch(batch, pending);
      batch = db.batch();
      pending = 0;
    }
  }

  await commitBatch(batch, pending);
  console.log(`Upserted ${total} hashtag docs.`);
};

run().catch((err) => {
  console.error(err);
  process.exit(1);
});

import crypto from 'node:crypto';
import { cert, getApps, initializeApp } from 'firebase-admin/app';
import { getFirestore } from 'firebase-admin/firestore';
import { createMcpHandler } from 'mcp-handler';
import { z } from 'zod';

const ranchId = requiredEnv('VIMO_RANCH_ID');
const actorUid = requiredEnv('VIMO_ACTOR_UID');
const pluginApiKey = requiredEnv('VIMO_PLUGIN_API_KEY');

if (getApps().length === 0) {
  initializeApp({
    credential: cert({
      projectId: requiredEnv('FIREBASE_PROJECT_ID'),
      clientEmail: requiredEnv('FIREBASE_CLIENT_EMAIL'),
      privateKey: requiredEnv('FIREBASE_PRIVATE_KEY').replace(/\\n/g, '\n'),
    }),
  });
}

const db = getFirestore();
const readableCollections = [
  'animals',
  'milk_records',
  'food_records',
  'stock_records',
  'expense_records',
  'doctor_records',
  'purchase_records',
  'sale_records',
  'death_records',
  'calving_records',
  'ranch_messages',
  'ranch_tasks',
  'notifications',
] as const;

type ReadableCollection = (typeof readableCollections)[number];

function requiredEnv(name: string) {
  const value = process.env[name]?.trim();
  if (!value) throw new Error(`Missing environment variable: ${name}`);
  return value;
}

function secureEquals(a: string, b: string) {
  const left = Buffer.from(a);
  const right = Buffer.from(b);
  return left.length === right.length && crypto.timingSafeEqual(left, right);
}

async function assertActiveMember() {
  const member = await db.doc(`ranches/${ranchId}/members/${actorUid}`).get();
  if (!member.exists) throw new Error('Configured VIMO actor is not a ranch member.');
  const data = member.data() ?? {};
  if (data.active === false || data.status !== 'active') {
    throw new Error('Configured VIMO actor is not an active ranch member.');
  }
  return String(data.role ?? 'None');
}

function jsonSafe(value: unknown): unknown {
  if (value == null) return value;
  if (Array.isArray(value)) return value.map(jsonSafe);
  if (typeof value === 'object') {
    const timestamp = value as { toDate?: () => Date };
    if (typeof timestamp.toDate === 'function') return timestamp.toDate().toISOString();
    return Object.fromEntries(
      Object.entries(value as Record<string, unknown>).map(([key, child]) => [key, jsonSafe(child)]),
    );
  }
  return value;
}

function text(payload: unknown) {
  return {
    content: [{ type: 'text' as const, text: JSON.stringify(jsonSafe(payload), null, 2) }],
  };
}

async function readCollection(collection: ReadableCollection, limit: number) {
  await assertActiveMember();
  const snapshot = await db
    .collection(`ranches/${ranchId}/${collection}`)
    .limit(Math.min(Math.max(limit, 1), 200))
    .get();
  return snapshot.docs.map((doc) => ({ id: doc.id, ...doc.data() }));
}

const mcpHandler = createMcpHandler(
  (server) => {
    server.tool('get_ranch_summary', 'Get VIMO ranch collection counts and member role.', {}, async () => {
      const role = await assertActiveMember();
      const names: ReadableCollection[] = [
        'animals',
        'milk_records',
        'stock_records',
        'expense_records',
        'doctor_records',
        'sale_records',
      ];
      const counts = await Promise.all(
        names.map(async (name) => [
          name,
          (await db.collection(`ranches/${ranchId}/${name}`).count().get()).data().count,
        ] as const),
      );
      return text({ ranchId, role, counts: Object.fromEntries(counts) });
    });

    server.tool(
      'list_animals',
      'List cow and calf records from the configured VIMO ranch.',
      { limit: z.number().int().min(1).max(200).default(100) },
      async ({ limit }) => text(await readCollection('animals', limit)),
    );

    server.tool(
      'get_ranch_records',
      'Read one approved ranch collection such as milk, stock, expenses, doctor, purchases, sales, deaths, calving, messages, tasks or notifications.',
      {
        collection: z.enum(readableCollections),
        limit: z.number().int().min(1).max(200).default(100),
      },
      async ({ collection, limit }) => text(await readCollection(collection, limit)),
    );
  },
  {},
  { basePath: '/api' },
);

async function authorize(request: Request) {
  const auth = request.headers.get('authorization') ?? '';
  const supplied = auth.startsWith('Bearer ') ? auth.slice(7) : '';
  if (!supplied || !secureEquals(supplied, pluginApiKey)) {
    return new Response(JSON.stringify({ error: 'Unauthorized' }), {
      status: 401,
      headers: { 'content-type': 'application/json' },
    });
  }
  return null;
}

async function handle(request: Request) {
  const denied = await authorize(request);
  if (denied) return denied;
  return mcpHandler(request);
}

export { handle as GET, handle as POST, handle as DELETE };

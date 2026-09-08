import crypto from 'node:crypto';
import { cert, getApps, initializeApp } from 'firebase-admin/app';
import { getFirestore, type Firestore } from 'firebase-admin/firestore';
import { createMcpHandler } from 'mcp-handler';
import { z } from 'zod';

const liveEnvNames = [
  'VIMO_RANCH_ID',
  'VIMO_ACTOR_UID',
  'VIMO_PLUGIN_API_KEY',
  'FIREBASE_PROJECT_ID',
  'FIREBASE_CLIENT_EMAIL',
  'FIREBASE_PRIVATE_KEY',
] as const;

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

type LiveContext = {
  ranchId: string;
  actorUid: string;
  pluginApiKey: string;
  db: Firestore;
};

function env(name: (typeof liveEnvNames)[number]) {
  return process.env[name]?.trim() ?? '';
}

function setupStatus() {
  const missing = liveEnvNames.filter((name) => !env(name));
  return {
    service: 'vimo-ranch-mcp',
    version: '0.2.0',
    mode: 'read-only',
    liveDataConfigured: missing.length === 0,
    missingEnvironmentVariables: missing,
  };
}

function getLiveContext(): LiveContext {
  const status = setupStatus();
  if (!status.liveDataConfigured) {
    throw new Error(
      `Live ranch data is locked until private deployment configuration is completed. Missing: ${status.missingEnvironmentVariables.join(', ')}`,
    );
  }

  const projectId = env('FIREBASE_PROJECT_ID');
  const clientEmail = env('FIREBASE_CLIENT_EMAIL');
  const privateKey = env('FIREBASE_PRIVATE_KEY').replace(/\\n/g, '\n');

  if (getApps().length === 0) {
    initializeApp({ credential: cert({ projectId, clientEmail, privateKey }) });
  }

  return {
    ranchId: env('VIMO_RANCH_ID'),
    actorUid: env('VIMO_ACTOR_UID'),
    pluginApiKey: env('VIMO_PLUGIN_API_KEY'),
    db: getFirestore(),
  };
}

function secureEquals(a: string, b: string) {
  const left = Buffer.from(a);
  const right = Buffer.from(b);
  return left.length === right.length && crypto.timingSafeEqual(left, right);
}

async function assertActiveMember(context: LiveContext) {
  const member = await context.db.doc(`ranches/${context.ranchId}/members/${context.actorUid}`).get();
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
  const context = getLiveContext();
  await assertActiveMember(context);
  const snapshot = await context.db
    .collection(`ranches/${context.ranchId}/${collection}`)
    .limit(Math.min(Math.max(limit, 1), 200))
    .get();
  return snapshot.docs.map((doc) => ({ id: doc.id, ...doc.data() }));
}

const mcpHandler = createMcpHandler(
  (server) => {
    server.tool('get_setup_status', 'Check whether the private VIMO live-data connection is configured.', {}, async () => {
      return text(setupStatus());
    });

    server.tool('get_ranch_summary', 'Get VIMO ranch collection counts and member role.', {}, async () => {
      const context = getLiveContext();
      const role = await assertActiveMember(context);
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
          (await context.db.collection(`ranches/${context.ranchId}/${name}`).count().get()).data().count,
        ] as const),
      );
      return text({ ranchId: context.ranchId, role, counts: Object.fromEntries(counts) });
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
  const status = setupStatus();
  if (!status.liveDataConfigured) return null;

  const expected = env('VIMO_PLUGIN_API_KEY');
  const auth = request.headers.get('authorization') ?? '';
  const supplied = auth.startsWith('Bearer ') ? auth.slice(7) : '';
  if (!supplied || !secureEquals(supplied, expected)) {
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

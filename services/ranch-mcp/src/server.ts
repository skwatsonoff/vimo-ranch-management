import crypto from 'node:crypto';
import express from 'express';
import { applicationDefault, getApps, initializeApp } from 'firebase-admin/app';
import { getFirestore } from 'firebase-admin/firestore';
import { McpServer, createMcpHandler } from '@modelcontextprotocol/server';
import { toNodeHandler } from '@modelcontextprotocol/node';
import * as z from 'zod/v4';

const port = Number(process.env.PORT ?? 8080);
const ranchId = requiredEnv('VIMO_RANCH_ID');
const actorUid = requiredEnv('VIMO_ACTOR_UID');
const pluginApiKey = requiredEnv('VIMO_PLUGIN_API_KEY');

if (getApps().length === 0) {
  initializeApp({ credential: applicationDefault() });
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
  'notifications'
] as const;

type ReadableCollection = (typeof readableCollections)[number];

function requiredEnv(name: string): string {
  const value = process.env[name]?.trim();
  if (!value) throw new Error(`Missing required environment variable: ${name}`);
  return value;
}

function secureEquals(a: string, b: string): boolean {
  const left = Buffer.from(a);
  const right = Buffer.from(b);
  return left.length === right.length && crypto.timingSafeEqual(left, right);
}

async function assertActiveMember(): Promise<string> {
  const member = await db.doc(`ranches/${ranchId}/members/${actorUid}`).get();
  if (!member.exists) throw new Error('Configured VIMO actor is not a ranch member.');
  const data = member.data() ?? {};
  if (data.active === false || data.status !== 'active') {
    throw new Error('Configured VIMO actor is not an active ranch member.');
  }
  return String(data.role ?? 'None');
}

function jsonSafe(value: unknown): unknown {
  if (value === null || value === undefined) return value;
  if (Array.isArray(value)) return value.map(jsonSafe);
  if (typeof value === 'object') {
    const maybeTimestamp = value as { toDate?: () => Date };
    if (typeof maybeTimestamp.toDate === 'function') {
      return maybeTimestamp.toDate().toISOString();
    }
    const out: Record<string, unknown> = {};
    for (const [key, child] of Object.entries(value as Record<string, unknown>)) {
      out[key] = jsonSafe(child);
    }
    return out;
  }
  return value;
}

function textResult(payload: unknown) {
  return {
    content: [{ type: 'text' as const, text: JSON.stringify(jsonSafe(payload), null, 2) }]
  };
}

async function readCollection(name: ReadableCollection, limit: number) {
  await assertActiveMember();
  const snapshot = await db
    .collection(`ranches/${ranchId}/${name}`)
    .limit(Math.min(Math.max(limit, 1), 200))
    .get();

  return snapshot.docs.map((doc) => ({ id: doc.id, ...doc.data() }));
}

function buildServer() {
  const server = new McpServer(
    { name: 'vimo-ranch', version: '0.1.0' },
    {
      capabilities: { tools: {} },
      instructions:
        'Read VIMO ranch data only. Respect ranch membership and never invent missing values. Writes are intentionally disabled in this first version.'
    }
  );

  server.registerTool(
    'get_ranch_summary',
    {
      description: 'Get a high-level VIMO ranch summary with collection counts and the configured member role.',
      inputSchema: z.object({})
    },
    async () => {
      const role = await assertActiveMember();
      const collections: ReadableCollection[] = [
        'animals',
        'milk_records',
        'stock_records',
        'expense_records',
        'doctor_records',
        'sale_records'
      ];

      const entries = await Promise.all(
        collections.map(async (name) => {
          const snap = await db.collection(`ranches/${ranchId}/${name}`).count().get();
          return [name, snap.data().count] as const;
        })
      );

      return textResult({ ranchId, role, counts: Object.fromEntries(entries) });
    }
  );

  server.registerTool(
    'list_animals',
    {
      description: 'List cow/calf animal documents from the configured VIMO ranch.',
      inputSchema: z.object({ limit: z.number().int().min(1).max(200).default(100) })
    },
    async ({ limit }) => textResult(await readCollection('animals', limit))
  );

  server.registerTool(
    'get_ranch_records',
    {
      description:
        'Read records from one approved VIMO ranch collection. Use this for milk, feed, stock, expenses, doctor, purchases, sales, deaths, calving, tasks, messages or notifications.',
      inputSchema: z.object({
        collection: z.enum(readableCollections),
        limit: z.number().int().min(1).max(200).default(100)
      })
    },
    async ({ collection, limit }) => textResult(await readCollection(collection, limit))
  );

  return server;
}

const mcpHandler = createMcpHandler(buildServer);
const app = express();

app.get('/health', (_req, res) => {
  res.status(200).json({ ok: true, service: 'vimo-ranch-mcp' });
});

app.all('/mcp', (req, res, next) => {
  const auth = req.header('authorization') ?? '';
  const prefix = 'Bearer ';
  const supplied = auth.startsWith(prefix) ? auth.slice(prefix.length) : '';
  if (!supplied || !secureEquals(supplied, pluginApiKey)) {
    res.status(401).json({ error: 'Unauthorized' });
    return;
  }
  next();
});

app.all('/mcp', toNodeHandler(mcpHandler));

app.listen(port, '0.0.0.0', () => {
  console.log(`VIMO Ranch MCP listening on port ${port}`);
});

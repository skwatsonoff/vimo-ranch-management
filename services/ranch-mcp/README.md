# VIMO Ranch MCP

Private, read-only MCP service for the VIMO Ranch Manager plugin.

## Current state

Version `0.2.0` is designed for a zero-cost Vercel Hobby deployment.

- The MCP endpoint can stay online before Firebase secrets are configured.
- `get_setup_status` works in setup mode.
- Live ranch-data tools stay locked until all private deployment variables exist.
- No create/update/delete tools are exposed.

## Tools

- `get_setup_status`
- `get_ranch_summary`
- `list_animals`
- `get_ranch_records`

The generic record tool is restricted to approved VIMO collections.

## Required variables for live ranch data

- `VIMO_RANCH_ID` — Ranch ID this private MCP instance may access.
- `VIMO_ACTOR_UID` — Firebase UID whose active ranch membership is checked before each read.
- `VIMO_PLUGIN_API_KEY` — strong random bearer token for the MCP client.
- `FIREBASE_PROJECT_ID`
- `FIREBASE_CLIENT_EMAIL`
- `FIREBASE_PRIVATE_KEY`

Never commit these values to GitHub. The Firebase private key must remain a Vercel environment variable/secret.

The configured actor must exist at `ranches/{VIMO_RANCH_ID}/members/{VIMO_ACTOR_UID}` with `status == active` and `active != false`.

## Local development

From `services/ranch-mcp`:

```bash
npm install
npm run dev
```

Health endpoint:

```text
GET /health
```

MCP endpoint:

```text
GET/POST/DELETE /mcp
```

When live data is configured, requests must include:

```text
Authorization: Bearer <VIMO_PLUGIN_API_KEY>
```

## Free Vercel deployment

Create a Vercel Hobby project with the project root set to:

```text
services/ranch-mcp
```

Deploy without the Firebase variables first if needed. The service remains in setup mode and exposes no ranch records.

After the private variables are configured and the deployment is verified, replace `https://YOUR_VIMO_MCP_HOST/mcp` in `plugins/ranch-manager/.mcp.json` with the final HTTPS endpoint.

## Security notes

- Version `0.2.0` is intentionally read-only.
- Firestore Admin SDK bypasses client Firestore rules, so the MCP service performs its own active-member check before reading.
- Live data is not enabled unless every required private variable is present.
- Once live data is enabled, the MCP endpoint requires the configured bearer token.
- Do not broaden collection access without reviewing the Ranch app data model and privacy impact.
- Add write actions only after implementing server-side role checks that mirror `firestore.rules` and confirmation behavior for destructive or financially meaningful actions.

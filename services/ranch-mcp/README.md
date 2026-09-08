# VIMO Ranch MCP

Private read-only MCP service for the VIMO Ranch Manager plugin.

## What it exposes

- `get_ranch_summary`
- `list_animals`
- `get_ranch_records`

The generic record tool is restricted to approved VIMO collections. No create/update/delete tool is exposed in v0.1.0.

## Required environment variables

- `VIMO_RANCH_ID` — the Ranch ID this private MCP instance may access.
- `VIMO_ACTOR_UID` — Firebase UID of the ranch member whose membership is checked before every data read.
- `VIMO_PLUGIN_API_KEY` — strong random bearer token used by the MCP client.
- `GOOGLE_APPLICATION_CREDENTIALS` when running outside Google Cloud, or Application Default Credentials when deployed on Google Cloud.
- `PORT` — optional; defaults to `8080`.

The configured actor must exist at `ranches/{VIMO_RANCH_ID}/members/{VIMO_ACTOR_UID}` with `status == active` and `active != false`.

## Local development

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
POST/GET /mcp
Authorization: Bearer <VIMO_PLUGIN_API_KEY>
```

## Deployment

Deploy this container to a trusted HTTPS host such as Google Cloud Run. Prefer a dedicated Google Cloud service account with the minimum Firestore access required for this service. Do not commit service-account JSON or API keys to GitHub.

After deployment, replace `https://YOUR_VIMO_MCP_HOST/mcp` in `plugins/ranch-manager/.mcp.json` with the real HTTPS MCP endpoint.

For a private Codex plugin, provide `VIMO_PLUGIN_API_KEY` as the MCP bearer-token environment variable. For a public or multi-user ChatGPT app, replace the static private-token design with a proper user authorization/OAuth flow before distribution.

## Security notes

- v0.1.0 is intentionally read-only.
- Firestore Admin SDK bypasses client Firestore rules, so this service performs its own ranch membership check before reading.
- Do not expose this endpoint without authentication.
- Do not broaden collection access without reviewing the Ranch app data model and privacy impact.
- Add write actions only after implementing server-side role checks that mirror `firestore.rules` and after defining confirmation behavior for destructive or financially meaningful actions.

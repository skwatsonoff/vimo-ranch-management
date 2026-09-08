export function GET() {
  return Response.json({
    ok: true,
    service: 'vimo-ranch-mcp',
    version: '0.2.0',
    mode: 'read-only',
  });
}

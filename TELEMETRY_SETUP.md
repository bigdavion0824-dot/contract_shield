# Contract Shield Telemetry Setup

This repo includes a minimal no-dependency telemetry receiver at `telemetry_receiver/server.py`.

## What it does

- Accepts `POST /ingest` with JSON payloads from the app
- Stores each payload as one JSON line in `telemetry_receiver/telemetry.jsonl`
- Exposes `GET /health`
- Exposes `GET /recent?n=20` for quick inspection
- Supports optional Bearer token auth

## Run locally

```bash
cd /Users/parish/Desktop/contract_shield/flutter_application_1
python3 telemetry_receiver/server.py
```

Default address:

- `http://0.0.0.0:8787`
- ingest endpoint: `http://localhost:8787/ingest`

## Optional auth

```bash
cd /Users/parish/Desktop/contract_shield/flutter_application_1
export TELEMETRY_AUTH_TOKEN="replace-with-long-random-token"
python3 telemetry_receiver/server.py
```

If auth is enabled, the app endpoint should include the token in an HTTPS reverse proxy or custom receiver setup. The current Flutter relay supports endpoint-only configuration, so if you want header-based auth from the app, add that before public deployment.

## Test the receiver

```bash
curl -X POST http://localhost:8787/ingest \
  -H "Content-Type: application/json" \
  -d '{"type":"event","name":"test_event","appVersion":"1.0.0-beta.1"}'
```

View recent entries:

```bash
curl http://localhost:8787/recent?n=5
```

## Connect the app

Build with a telemetry endpoint:

```bash
flutter build appbundle --release \
  --dart-define=TELEMETRY_ENDPOINT=https://your-domain.example.com/ingest
```

```bash
flutter build ios --release --no-codesign \
  --dart-define=TELEMETRY_ENDPOINT=https://your-domain.example.com/ingest
```

## Production recommendation

Do not expose this bare Python server directly to the public internet.

Use one of these options:

1. Put it behind Nginx/Caddy with HTTPS.
2. Deploy it on a small VM behind a reverse proxy.
3. Replace it with Sentry, Firebase, or your own backend endpoint later.

## Minimum fields sent by the app

Event payloads include fields like:

- `type`
- `ts`
- `name`
- `params`
- `appVersion`
- `buildLabel`
- `platform`

Error payloads include fields like:

- `type`
- `ts`
- `scope`
- `error`
- `stack`
- `appVersion`
- `buildLabel`
- `platform`

# Mattermost Client Setup (Desktop + iPhone)

Use this after Mattermost is deployed in-cluster.

## Server URL

- Primary URL: `https://mattermost.jamilshaikh.in`
- Display name suggestion: `Homelab Mattermost`

If you later expose Mattermost over TLS/public DNS, replace the URL in clients with that HTTPS endpoint.

## Desktop App (Linux/macOS/Windows)

1. Open Mattermost desktop app.
2. Enter `Server URL` as `https://mattermost.jamilshaikh.in`.
3. Enter `Server display name` as `Homelab Mattermost`.
4. Click **Connect** and sign in.
5. Join channels used by OpenClaw (`devops`, `alerts`, `business`).

## iPhone App (iOS)

1. Open Mattermost iOS app.
2. Add server URL: `https://mattermost.jamilshaikh.in`.
3. Sign in with your Mattermost account.
4. Join `devops`, `alerts`, and `business` channels.
5. In app settings, enable push notifications for mentions and direct messages.

## If App Gets Stuck On "Validating..."

- Confirm the URL is exactly `https://mattermost.jamilshaikh.in` (not `http://`).
- If your laptop browser shows a certificate warning on that URL, the app will usually stay stuck at validation.
- Confirm DNS has propagated for `mattermost.jamilshaikh.in`, then retry.

## If iPhone Still Cannot Connect

iOS networks often enforce stricter rules for private DNS and certificate trust. If the app fails:

- Confirm iPhone can resolve and reach `mattermost.jamilshaikh.in`.
- Ensure the same URL is set as Mattermost `siteUrl` in GitOps to avoid redirect/callback mismatch.

## OpenClaw Channel Mapping

OpenClaw delivery currently targets:

- `cluster-health-check` -> `#devops`
- `critical-alert-check` -> `#alerts`
- `talos-health-check` -> `#devops`
- `argocd-sync-check` -> `#devops`
- `prospect-hunter` -> `#business`

Keep these channels present in Mattermost so cron deliveries stay consistent.

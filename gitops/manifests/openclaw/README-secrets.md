# openclaw — Secret Setup (one-time, run before ArgoCD syncs the Deployment)

These secrets are NOT in git. Run once after a cluster rebuild.

## 1. openclaw-tokens (API keys)

```bash
kubectl create secret generic openclaw-tokens -n openclaw \
  --from-literal=ANTHROPIC_API_KEY='sk-ant-...' \
  --from-literal=GEMINI_API_KEY='AIza...'
```

## 2. openclaw-config (gateway config with Slack + Telegram tokens)

Edit `openclaw-config.json` locally, fill in all `REPLACE_WITH_*` values, then:

```bash
kubectl create secret generic openclaw-config -n openclaw \
  --from-file=openclaw.json=gitops/manifests/openclaw/openclaw-config.json
```

Token sources:
- `SLACK_APP_TOKEN` (`xapp-...`) → Slack App settings → Socket Mode → App-Level Token
- `SLACK_BOT_TOKEN` (`xoxb-...`) → Slack App settings → OAuth & Permissions → Bot Token
- `TELEGRAM_BOT_TOKEN` → @BotFather → /token
- Gateway token → generate any random string: `openssl rand -hex 32`

## 3. openclaw-talosconfig (already created by make deploy, recreate if lost)

```bash
kubectl create secret generic openclaw-talosconfig -n openclaw \
  --from-file=talosconfig=talos-homelab-cluster/rendered/talosconfig
```

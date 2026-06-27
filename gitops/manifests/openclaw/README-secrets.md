# openclaw — Secret Setup (one-time, run before ArgoCD syncs the Deployment)

These secrets are NOT in git. Run once after a cluster rebuild.

## 1. openclaw-tokens (API keys)

```bash
kubectl create secret generic openclaw-tokens -n openclaw \
  --from-literal=ANTHROPIC_API_KEY='sk-ant-...' \
  --from-literal=GEMINI_API_KEY='AIza...'
```

## 2. openclaw-config (gateway config with Mattermost token)

Edit `openclaw-config.json` locally, fill in all `REPLACE_WITH_*` values, then:

```bash
kubectl create secret generic openclaw-config -n openclaw \
  --from-file=openclaw.json=gitops/manifests/openclaw/openclaw-config.json
```

Token sources:
- `MATTERMOST_BOT_TOKEN` → Mattermost → Integrations → Bot Accounts → Access Token
- Gateway token → generate any random string: `openssl rand -hex 32`

## 3. openclaw-talosconfig (already created by make deploy, recreate if lost)

```bash
kubectl create secret generic openclaw-talosconfig -n openclaw \
  --from-file=talosconfig=talos-homelab-cluster/rendered/talosconfig
```

## 4. ghcr-pull-secret (GHCR image pull, private registry)

```bash
kubectl create secret docker-registry ghcr-pull-secret \
  -n openclaw \
  --docker-server=ghcr.io \
  --docker-username=jamilshaikh07 \
  --docker-password="$(gh auth token)"
```

Note: image stays private on GHCR. Recreate this secret if the gh token is rotated.

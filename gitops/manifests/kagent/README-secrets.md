# kagent — Secret Setup (one-time, run before/after ArgoCD syncs)

Not in git. The `kagent` namespace is created by the `kagent-crds`/`kagent`
Applications (CreateNamespace=true) — create this secret any time after that,
before agents will actually respond (LLM calls will fail without it).

## kagent-tokens (DeepSeek API key, reused from openclaw)

```bash
kubectl create secret generic kagent-tokens -n kagent \
  --from-literal=DEEPSEEK_API_KEY='sk-...'
```

To rotate:

```bash
kubectl create secret generic kagent-tokens -n kagent \
  --from-literal=DEEPSEEK_API_KEY='sk-...' \
  --dry-run=client -o yaml | kubectl apply -f -
kubectl rollout restart deployment/kagent-controller -n kagent
```

## Notes

- `gitops/apps/kagent.yaml` sets `providers.openAI.config.baseUrl` to
  DeepSeek's OpenAI-compatible endpoint — same provider mechanism as
  openclaw, different tool.
- After the `kagent`/`kagent-crds` apps first create the `kagent` namespace,
  the `ingress-routes` app (sync-wave 4, runs *before* kagent's wave 6/7)
  may need a manual hard-refresh in ArgoCD once the namespace exists —
  same one-time gotcha hit when Coder was added.

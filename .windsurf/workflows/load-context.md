---
description: Load repo context from agent context files (CLAUDE.md / GEMINI.md / CODEX.md / AGENTS.md) before doing any work
---

# Load Context

Use this whenever a new session starts in this repo, or when the user asks you to "load context", "read context", "understand the repo", or invokes `/load-context`.

## Steps

1. Detect which agent context files exist in the repo root. Check (case-insensitive) for:
   - `CLAUDE.md`
   - `GEMINI.md`
   - `CODEX.md`
   - `AGENTS.md`
   - `agent.md`
   - `context.md`
   - `memory.md`
   - `skills.md`
   - `.cursor/rules/*.md` and `.cursorrules`
   - `.github/copilot-instructions.md`

   Use `find_by_name` with the repo root as `SearchDirectory` and a glob like `*.md` at `MaxDepth: 2`, then filter to the names above. Do NOT recurse into `node_modules`, `.git`, `gitops/`, `terraform/`, `ansible/` for this discovery step.

2. Read every matched file in full with `read_file`. Issue the reads in parallel in a single tool batch.

3. Also read `README.md` if present (full file) and `Makefile` (just enough to enumerate top-level targets — usually first 200 lines is enough; otherwise scan for `^[a-zA-Z0-9_-]+:` lines).

4. Build an internal mental model covering:
   - **Project purpose** and the layers/components.
   - **Directory layout** and where the source of truth for each concern lives.
   - **Common commands** (Make targets, scripts).
   - **Network / topology / versions** (IPs, domains, software versions).
   - **Secrets handling** (sops, age, gitignored paths).
   - **Guardrails / operating principles** declared by the user (e.g. "never destroy", "drain before scale-down").
   - **Open work / next focus** items.

5. Reply to the user with a concise summary structured as:
   - `## What this repo is`
   - `## Layers / Architecture`
   - `## Key commands`
   - `## Network & versions`
   - `## Guardrails I will follow`
   - `## Notes / observations` (including anything notable about a public repo, e.g. exposed internal IPs, domains, usernames — but never echo secret material).

6. If any referenced file in the context docs (e.g. a path like `ansible/roles/talos-cluster/vars/main.yml`) is critical for the user's stated task, read it on demand — do NOT pre-read the whole tree.

## Rules

- Never invent context that is not in the files. If something is unclear, say so.
- Never print secret values, even if found. If a file looks like it contains credentials and is tracked in git, warn the user.
- Treat the user's stated guardrails (from `agent.md`, `CLAUDE.md`, etc.) as binding for the rest of the session.
- Prefer the most specific file when files conflict. Order of precedence: `CLAUDE.md` > `AGENTS.md` > `agent.md` > `context.md` > `memory.md` > `skills.md` > `README.md`.
- Do not run any shell commands as part of loading context. File reads only.

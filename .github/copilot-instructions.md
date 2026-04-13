# Copilot Workspace Instructions

## Session Bootstrap (Mandatory)
At the start of each new chat session in this repository, before substantial analysis or edits:

1. Read agent.md
2. Read context.md
3. Read memory.md
4. Read skills.md

Then:
- Summarize the current operating context in 3-6 concise bullets.
- Follow the reliability guardrails and workflows defined in these files.
- Prefer safe, reversible operations for infrastructure changes.

## Infrastructure Safety Rules
- Always run a plan before Terraform apply.
- Regenerate inventory after Terraform topology changes.
- For worker scale-down, drain first and verify node-local storage impact.
- Keep DHCP reservations aligned with planned Talos MAC/IP mappings.
- Do not use destructive git commands unless explicitly requested.

## Operational Preference
Treat this homelab as persistent, long-lived infrastructure.
Optimize for stability, predictability, and recoverability over speed.

# OPENCODE Multi-Agent Workflow — Contract-Engineered Edition

> This repository contains the **multi-agent orchestration system** of the OPENCODE fork, designed to turn complex engineering tasks into a deterministic, contract-driven, replayable pipeline with strong isolation guarantees.
>
> **⚠️ Scope** — The system serves **code workflows only**: reading code, editing code, running tests, assembling patches. Generic requests (documentation, customer support, PPT/Excel generation, open-ended chat) are rejected by `main` with an explanation to the user.

---

## Repository Layout

```
opencode_agents/
├── README.md            # This file
├── AGENTS/              # Agent definitions (7 sub-agents orchestrated by main)
│   ├── main.md          # Primary orchestrator
│   ├── archgate.md      # Architecture gate — read-only spec validator
│   ├── explore.md       # Read-only code reconnaissance
│   ├── implement.md     # Minimal-trauma code editing with enforced TDD
│   ├── verify.md        # Test runner + failure diagnosis (read-only)
│   ├── review.md        # Code-quality gate (read-only, 7-dimension audit)
│   └── patcher.md       # Final-mile assembly: cleanup, full-test, patch
│
└── SKILLS/              # On-demand playbooks loaded per task
    └── goal-driven-planning/   # File-based planning for long, multi-step code-repair tasks
```

## Architecture Overview

```
                         ┌──────────┐
                         │   USER   │
                         └────┬─────┘
                              │ user_intent
                              ▼
                       ┌──────────────┐
                       │   main 🎯    │  ← sole entry point, router, decision-maker
                       │  (primary)   │
                       └──┬──┬──┬──┬──┘
                          │  │  │  │
            ┌─────────────┘  │  │  └─────────────┐
            ▼                ▼  ▼                ▼
       ┌─────────┐    ┌──────────┐    ┌────────┐    ┌─────────┐
       │ explore │ →  │implement │ →  │ verify │ →  │ patcher │
       │ (read)  │    │ (write)  │    │ (test) │    │(deliver)│
       └─────────┘    └──────────┘    └────────┘    └─────────┘
            │              │               │              │
            └──────────────┴───────────────┴──────────────┘
                              │
                              ▼  output_variables (structured)
                       ┌─────────────────┐
                       │  .task_state/   │  ← persistent governance layer
                       │  task_plan.md   │
                       │  findings.md    │
                       │  progress.md    │
                       └─────────────────┘
                              │
                              ▼
                       ┌─────────────────┐
                       │   archgate      │  ← architecture gate (read-only)
                       └─────────────────┘
                              │
                              ▼
                       ┌─────────────────┐
                       │   review        │  ← code-quality gate (read-only)
                       └─────────────────┘
```

## Agents (`AGENTS/`)

| Agent | Mode | Role | Contract |
|-------|------|------|----------|
| **main** | primary | Orchestrator — sole entry, routes tasks, owns decisions | Schedules sub-agents, manages `.task_state/`, enforces gate transitions |
| **archgate** | subagent (read-only) | Architecture validator — checks spec vs. architecture rules (docs + ground-truth code) | 4-state verdict: `PASS` / `BLOCKING` / `BLOCKED` / `NEEDS_DESIGN` |
| **implement** | subagent (write) | Minimal-trauma code editor — enforced TDD (interface → test → impl) | Runs impact analysis pre-edit, lint/typecheck post-edit, never runs tests |
| **verify** | subagent (read-only) | Test runner + failure diagnosis | 3-state verdict: `PASS` / `FAIL` / `BLOCKED` with root-cause per test |
| **review** | subagent (read-only) | Code-quality audit — 7-dimension hard-constraint checklist | 2-state verdict: `PASS` / `BLOCKING` (any P0/P1 → forced BLOCKING) |
| **patcher** | subagent (write, limited) | Final-mile assembly — cleanup, full-test, produce clean `git apply` patch | 2-state verdict: `READY` / `BLOCKED`; never writes business logic |
| **explore** | subagent (read-only) | Code reconnaissance — locate symbols, call graphs, impact surfaces | Returns structured `output_variables` for downstream `implement` |

### Common Conventions

- **Structured `output_variables`** — Every sub-agent terminates with a machine-parseable `output_variables` block that feeds into the next step.
- **Contract-first inputs** — Each agent declares required input fields; missing fields → immediate rejection, not guesswork.
- **Gate transitions are explicit** — `main` enforces the state machine; no sub-agent may skip a gate.
- **Three-strike escalation** — Looped failures on the same WP escalate to the user (defined in `main.md` §纠错规则).

## Workflow Pipeline

```
user_intent
    │
    ▼
main: complexity self-check → light path OR planning path
    │
    ▼
[archgate] code_spec validation
    │─ BLOCKING → main re-spec
    │─ NEEDS_DESIGN → main writes constraints → re-submit
    │─ PASS ▼
[implement] TDD triplet: interface → unit test → implementation
    │
    ▼
[verify] targeted tests — PASS / FAIL / BLOCKED
    │─ FAIL → implement rework (with root-cause feedback)
    │─ PASS ▼
[review] 7-dimension audit — PASS / BLOCKING
    │─ BLOCKING → implement rework
    │─ PASS ▼
[integration test] cross-module behavior validation
    │
    ▼
[patcher] cleanup + full-test + git-apply-check → READY
    │
    ▼
delivery (patch + summary + unaddressed risks)
```

## Skills (`SKILLS/`)

Skills are **on-demand playbooks** loaded only when a task matches their trigger. They live alongside the agents but are not sub-agents — they provide procedures, templates, and constraints.

| Skill | Purpose |
|-------|---------|
| **goal-driven-planning** | File-based planning for long, multi-step code-repair tasks. Decouples ephemeral context (TodoWrite queue) from persistent state (`.task_state/*.md`). Hooks in 4 touchpoints (UserPromptSubmit / PreToolUse / PostToolUse / Stop) push goals back into context. |

> Additional skills (plugin-setup, project-onboarding, document-generation, browser automation) live in the upstream orchestration repository and are installed separately.

## Design Principles

1. **Contract over prose** — Every step has a typed input/output contract; sub-agents reject malformed inputs instead of guessing.
2. **Deterministic routing** — `main` is the sole router. Sub-agents never communicate with each other or with the user directly.
3. **Strong isolation** — Each Work Package is isolated in its own git worktree; cross-WP contamination is forbidden.
4. **Replayable** — `.task_state/` files (task_plan / findings / progress) hold the entire decision log; `/clear` or crash restarts from the same checkpoint.
5. **Self-healing fallback** — Global fallback + node-level fallback + shadow session; intermediate reasoning never pollutes `main`'s context.

## Conventions Enforced by Agents

| Convention | Where |
|------------|-------|
| TDD triplet (interface → test → impl) | `implement.md` §TDD 三阶段 |
| 3-strike escalation on looped failures | `main.md` §纠错规则 + `goal-driven-planning/SKILL.md` §5.3 |
| Read-only gates never edit code | `archgate.md`, `verify.md`, `review.md`, `explore.md` |
| `output_variables` is machine-parseable | Every agent's §输出 Schema |
| `.task_state/` never enters the patch | `patcher.md` §强制条款 |
| Architecture constraints live in code + docs | `archgate.md` (dual-source evidence) |

## Installation

The agents in `AGENTS/` are deployed by the **plugin-setup** skill (step 2 of the three-step pipeline) and validated per-project by **project-onboarding** (step 3). These skills live in the upstream orchestration repository — refer to its `AGENTS.md` for the full installation flow.

Alternatively, copy the agent files from `AGENTS/` directly into your project's `.opencode/agents/` directory.

## License

This workflow is distributed as part of the OPENCODE fork. See the upstream repository for licensing.

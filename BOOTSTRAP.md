# BOOTSTRAP — from zero to a working agentic environment

Read this once, end to end. It covers installing the kit, connecting Claude Code, your first session, the habits that make sessions durable, how the dev crews work, and what the team site is for.

## 1. Install

```bash
git clone https://github.com/convivy/agentic-starter-kit.git
cd agentic-starter-kit
./install.sh
```

The installer confirms two choices with you:

- **Install root** (default `~/agentic`) — everything lives under it. If you pick another path, export `AGENTIC_ROOT` in your shell profile.
- **Pinned model** (default `claude-sonnet-5`) — the model every session launches on unless you explicitly override it. Sonnet is the right default, capable for nearly all development work and far cheaper against your plan's usage limits. Pin `claude-opus-4-8` instead if you're on a Max plan and want the frontier tier as your daily driver; either way, the rule is that the pin is *explicit*. An unpinned CLI default once silently switched to a premium model on our system and burned a subscription plus real money in a day. The kit's `model-pin-guard` hook exists because of that day.

Re-running the installer is safe: it refreshes the kit's binaries and never touches your cockpit, knowledge repo, or data.

## 2. Connect Claude Code

The kit assumes a Claude **subscription** (Pro or Max — both include Claude Code; the Free tier does not). Run `claude` once and follow the browser login, or `/login` inside a session. That's the whole setup.

Two things worth knowing:

- **Headless mode works on your plan.** `claude -p "prompt"` — the non-interactive form that scheduled jobs and scripts use, and that several IDEAS.md items build on — works on every plan that includes Claude Code and draws from the same subscription usage.
- **An API key silently overrides your subscription.** If `ANTHROPIC_API_KEY` is set in a session's environment, Claude Code bills that key pay-as-you-go instead of using your subscription — by design, and without telling you. Keep the key out of your shell profile; if a tool needs it, scope it to that tool. (On our system a leaked key burned 43M tokens of API credit in three days before anyone noticed.)

Plan sizing: Pro is enough to start and to run everything in this kit interactively. If you hit the usage window regularly — heavy agentic use, big repos, overnight runs — that's what Max is for.

## 3. Your first co session

```bash
cd ~/agentic/substrate
co
```

A **co** is one Claude Code session opened in a particular directory whose `CLAUDE.md` defines its job. `co` (the launcher) adds the discipline: an explicit pinned model every time, a named + colored tmux window when you're inside tmux, and the refresh/resume behavior below.

You just opened the **steward** — the co that tends the system itself. Say hello; ask it what it can see. Its charter (`substrate/CLAUDE.md`) tells it to capture friction you flag into `backlog.md`, record design choices in `decisions.md`, and grow the system with you.

**Which co do I open when?**

- **The steward** (`cd ~/agentic/substrate && co`) — for anything about the *system*: install a new capability, add a hook, fix friction in the tooling, build an IDEAS.md item, reorganize the knowledge base. If the sentence starts with "make my setup…", it's a steward conversation.
- **A product co** (`cd <your-repo> && co`) — for anything about a *product*: features, bugs, refactors, PRs. Give a repo a charter by copying the template: `cp -R ~/agentic/product-template/CLAUDE.md ~/agentic/product-template/.claude <your-repo>/` and editing the CLAUDE.md header.
- **A role** (`co researcher`) — a one-off specialist loaded from `knowledge/projects/shared/agents/`. Add roles as files there.

As a rule of thumb, the steward improves the machine; product co's use it.

## 4. `co -r` — refresh and resume

`co -r` does two things before launching:

1. **Pulls the knowledge repo** (if you've given it a remote), so the session starts from current shared knowledge.
2. **Resumes from the latest handoff**: it launches the session with `/handoff-pickup` as the first prompt, which finds the newest handoff for this context and picks up where the last session left off.

Use plain `co` for a fresh start; use `co -r` when you're continuing yesterday's (or this morning's) work.

## 5. Compaction and `/handoff-leave`

A long session eventually outgrows its context window; Claude Code then **compacts**, summarizing older conversation to make room. Compaction is lossy. The defense is the handoff habit:

- Before ending a session with work in flight, say `/handoff-leave`. The session writes a dated handoff doc — state, in-flight items, decisions, a recommended next move — under `agent-runs/`.
- The next session (via `co -r` or `/handoff-pickup`) reads it and resumes without re-deriving anything.

This is the single highest-value habit in the kit. Sessions become checkpoints in one continuous piece of work instead of isolated conversations. The same discipline applies *within* a session: anything worth keeping — a decision, a flagged idea — should land in a file (`backlog.md`, `decisions.md`, a KB doc) the moment it comes up, because the conversation itself is not durable.

## 6. How the dev crews work

Each product repo carries its own crew in `.claude/agents/` — the template ships three:

- **coder** — implements a bounded, crisply-specified task end-to-end (code, tests, passing CI). Your product co dispatches it for large mechanical work and keeps judgment-heavy changes itself.
- **reviewer** — reviews every PR: reads the diff, runs the repo's *full* CI commands locally, requires green CI, posts findings to the PR thread.
- **security-reviewer** — reviews every PR for security issues; bails fast when the diff has no security surface.

The product template's charter wires them into a **review cycle**: every PR gets both reviewers; any substantive finding means revise and re-review on the new head; a prior approve never carries over a revision. Two rules are absolute: reviewers mirror the repo's actual CI (never a single file's worth), and **the human merges** — no agent ever merges a PR. The `agentic-guard` hook enforces the second rule mechanically, so even a confused agent can't do it.

Crews are Claude Code subagents: your co dispatches them with its Agent tool, they run with their own context and their defined tools, and they report back. Ask your product co to "run the review cycle on PR #4" and watch it happen.

## 7. The team site

```bash
agentic-site &
open http://127.0.0.1:8321
```

Four pages: **Overview** (stat tiles, the latest handoff, the backlog head), **Activity** (sessions and handoffs by day), **Knowledge** (browse + full-text search the KB), **Cockpit** (the backlog and decision log, rendered).

The dashboards exist because an agentic system does real work while you are not watching, and a system you can't inspect is a system you stop trusting. The site answers "what has it been doing, what did it decide, and what does it know" at a glance, for you and for anyone you're showing the system to. As your system grows (workers, overnight runs, cost telemetry), grow the site to match; on our system the equivalent pages became the primary way the operator supervises everything.

## 8. Verify, then go

- `co` in the cockpit launches on your pinned model (check `/status`)
- asking the steward to search the KB returns the seeded runbook (`mcp__kb__kb_search`)
- a `gh pr merge` attempt inside a session is refused by `agentic-guard`
- `/handoff-leave` then `co -r` round-trips your session state
- the team site renders at http://127.0.0.1:8321

Then open IDEAS.md, pick the one that solves your actual friction, and take it to the steward. EXTENDING.md explains why that works.

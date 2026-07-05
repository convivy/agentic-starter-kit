# agentic-starter-kit

A self-contained starter kit for agentic development on your own laptop. One install gives you:

- **`co`** — a session launcher that opens Claude Code in a named context, always on a model you pinned
- **Safety hooks** — an agent can never merge a PR, force-push a protected branch, or silently un-pin your default model
- **Handoff continuity** — `/handoff-leave` saves a session's state; `co -r` resumes it, so work spans days and context resets
- **A knowledge base** — a git repo of markdown docs with a full-text index, searchable from inside every session via MCP
- **A dev crew** — reviewer, security reviewer, and coder subagents, plus a product template that runs a review cycle on every PR
- **A local team site** — dashboards showing what your system has been doing and what it knows

It is distilled from a working multi-agent development environment that runs real products. The lessons in it were paid for.

## Quickstart

```bash
git clone https://github.com/convivy/agentic-starter-kit.git
cd agentic-starter-kit
./install.sh
cd ~/agentic/substrate && co
```

Requirements: [Claude Code](https://code.claude.com/docs) on a Pro or Max subscription, git, python3 ≥ 3.10. macOS and Linux.

## Read next

| Doc | What it covers |
|---|---|
| [BOOTSTRAP.md](BOOTSTRAP.md) | Install, auth, your first co session, `co -r`, compaction and handoffs, how the dev crews work, which co to open when, and what the team site is for |
| [IDEAS.md](IDEAS.md) | Where to take it: an always-on box, persistent sessions over tmux + Tailscale, overnight orchestration, a Slack comms plane, phone alerts for runaway spending, multi-provider gateways, and more |
| [EXTENDING.md](EXTENDING.md) | How to build any of those ideas — the short answer is *ask Claude*, and this explains why that works |
| [docs/llm-bootstrap.md](docs/llm-bootstrap.md) | The spec-driven alternative: hand this document to a fresh Claude Code session and it builds the whole system from scratch, confirming choices with you as it goes |

## The shape of the thing

Everything lives under one root (default `~/agentic`):

```
~/agentic/
  substrate/          the cockpit — the steward's charter, backlog, decision log, handoffs
  knowledge/          the KB git repo — docs your agents search and grow
  product-template/   copy into a repo to give it a charter + dev crew
  agent-runs/         handoff and run artifacts
  .index/             the SQLite full-text index over the KB
```

Binaries land in `~/.local/bin` (`co`, `agentic-guard`, `model-pin-guard`, `kb-index`, `kb-watch`, `agentic-site`); the MCP server in `~/.local/lib/agentic`.

The design bias throughout is a lean core that works, grown deliberately. The kit ships the foundation — ergonomics, safety, memory, observability — and defers workers, schedulers, and comms until a real, repeated need appears. When it does, see EXTENDING.md.

## License

MIT. Built by [Convivy](https://lab.convivy.com).

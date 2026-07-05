# IDEAS — where to take your system next

Everything below runs today on the system this kit was distilled from. None of it ships prebuilt, deliberately; each item earns its place when *your* friction demands it, and building it with your steward is how your system becomes yours (see EXTENDING.md). Every idea ends with a prompt you can hand the steward verbatim.

Ordered roughly by how early we needed each one.

## 1. Move the system to an always-on box

A laptop closes; an agentic system wants to outlive the lid. A Mac mini, an old NUC, or a $10/mo VPS becomes the machine where sessions, watchers, and (later) scheduled jobs live; the laptop becomes a window onto it. This is the enabling move for most of what follows — overnight runs, persistent sessions, services that are simply always there.

> *"I have a spare machine at `<address>`. Plan moving my agentic root there: what moves, what the laptop keeps, and how I work against it day to day. Then walk me through it."*

## 2. Persistent sessions: tmux + Tailscale

Run every co inside tmux on the always-on box, and reach it from anywhere with [Tailscale](https://tailscale.com) (free tier is plenty). `ssh box` from any machine — or your phone — attaches to the same running sessions: nothing stops when you walk away, and a day-long steward session is genuinely day-long. One `~/.ssh/config` alias (`RemoteCommand tmux attach || tmux new`) makes it a single command. `co` already names and colors tmux windows, so a screenful of sessions stays legible.

> *"Set up my ssh config and tmux so that `ssh agentic` from my laptop attaches to a persistent tmux on the box, with one window per co. Include OSC 52 clipboard so remote copies land on my laptop."*

## 3. Overnight orchestration

The largest single upgrade we ever made was an orchestrator that runs a work queue while you sleep. The shape that works: a nightly scheduled job (launchd/systemd) launches a headless orchestrator (`claude -p`); it drains a queue of well-specified tasks by dispatching worker sessions, **each in its own git worktree** so parallel workers never collide; every worker opens a PR; every PR gets the review cycle; nothing merges, so you wake to a queue of reviewed PRs and triage over coffee. Start small: one product, two workers, a hard budget cap. The human-merges rule is what makes this safe to run unattended.

> *"Design a minimal overnight orchestrator for my system: a task queue file, a nightly scheduled job that dispatches N headless workers in git worktrees, PRs + the review cycle for everything, a hard spend/turn cap, and a morning summary. Propose the design first; build after I approve."*

## 4. A communication plane: Slack (or similar)

Once anything runs while you're not watching, it needs a place to tell you. A Slack workspace (or Discord, or Matrix) with a few purpose-named channels — `#overnight-digest`, `#alerts`, `#agent-cost` — turns invisible background work into a feed you skim from your phone. Two disciplines matter: agents post as themselves via a bot token, never as you; and scheduled jobs always post their result to a channel, so silence reliably means "nothing ran" instead of "who knows."

> *"Wire a Slack bot into my system: a small helper any agent or script can call to post to a named channel, tokens kept out of the repo, and the conventions for which events go where. Start with a daily digest of handoffs and PRs."*

## 5. Phone alerts for runaway spending (ntfy)

Autonomous work can fail expensive: a looping agent, a mispinned model, a leaked API key silently billing pay-as-you-go. [ntfy.sh](https://ntfy.sh) gives you free push notifications with one `curl`; pair it with a periodic spend check (e.g. [ccusage](https://github.com/ryoppippi/ccusage) reads Claude Code's local logs) and a threshold, and your phone buzzes *during* the incident instead of the bill telling you next month. Our version of this lesson cost real money each time we learned it; the alert is cheap insurance.

> *"Add a spend watchdog: every 30 minutes, estimate today's token spend from local usage data, compare against a daily threshold, and push an ntfy alert if it's exceeded — plus an immediate alert if ANTHROPIC_API_KEY ever appears in a session environment. Make the checks visible on the team site."*

## 6. Experiment with gateway models

A [LiteLLM](https://github.com/BerriAI/litellm) proxy on localhost lets a co or a worker run against other providers — DeepSeek, Kimi, GPT — through the same Anthropic-shaped API: `ANTHROPIC_BASE_URL` points at the proxy, and `co -m deepseek` becomes a real option. It earned its keep for us on cheap mechanical work (log summarization, scribe tasks) routed to a budget model while judgment work stays on Claude. It did not on fallback chains that mask provider errors. Keep it fail-closed: an unknown model name should error, never silently substitute.

> *"Stand up a local LiteLLM gateway with one budget model behind it, teach `co -m <name>` to route through it, and pick one recurring mechanical task to move there as the pilot. Track its spend separately so we can judge the trade."*

## 7. Make the knowledge base an always-on service

The kit ships `kb-watch` as a foreground script; promote it to a login service (launchd on macOS, `systemd --user` on Linux) so the index is simply never stale. This is also the natural first service to build with your steward: small, low-risk, and it teaches the service pattern (absolute paths, thin environments, logs somewhere findable) that overnight orchestration reuses.

> *"Make kb-watch a login service on this machine, with logs I can find and a one-line health check. Then add a KB health tile to the team site."*

## 8. Scheduled maintenance

Recurring habits worth automating once they're habits: a nightly KB validation sweep, a weekly "what changed" digest, a periodic backlog-staleness nudge. The rule that keeps this sane: every scheduled job posts its result somewhere visible (the comms plane, the team site), and a job that only matters when a human reacts to it should say so loudly.

> *"Look at what I do manually every week to keep this system healthy, propose which of it to schedule, and build the first one — result posted where I'll see it."*

## 9. Grow the team site

The kit's site shows sessions, handoffs, knowledge, and the cockpit. Ours grew into live spending and cost-performance dashboards, agent-velocity and health views, and a browsable rendering of every decision ever recorded; it became the way the operator supervises the whole platform. Grow yours toward whatever question you keep asking in a terminal: every "wait, what did it do yesterday?" is a page request.

> *"Add a page to agentic-site that shows <the question you keep asking>, reading from the data the system already produces."*

---

Pick by pain, not by order. And read EXTENDING.md before you start — the method matters more than the item.

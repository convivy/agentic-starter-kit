# EXTENDING — how to build all of it

The instruction is one sentence: **ask Claude. Seriously.**

Open the steward (`cd ~/agentic/substrate && co`), describe the friction or the IDEAS.md item in plain language, and build it together in that conversation. Every part of this kit — the launcher, the hooks, the knowledge index, the site, this document — was built that way, on the system it was built for, by the model that now runs inside it.

## Why this works

The breakthrough most people are one realization away from: **you can partner with the LLM to develop the system that includes the LLM.** Claude Code isn't only a tool your environment invokes — it's a competent systems engineer sitting *inside* that environment, with full knowledge of its own harness: hooks, MCP servers, subagents, headless mode, settings. When you ask it to extend the system, it is extending something it understands from the inside and will itself run on tomorrow. Better hooks make its future sessions safer; better docs make them smarter; better dashboards make them inspectable. The loop compounds.

This is why the kit ships lean and IDEAS.md ships as prose instead of code. A prebuilt overnight orchestrator would fit our machine, our products, our risk tolerance. The one you build with your steward in an afternoon fits yours — and the building teaches you both how it works, which is what you'll need the day it misbehaves.

## The method

1. **Bring the friction, not the design.** "I keep losing work when my laptop sleeps" gets a better system than "install tmux." Let the steward propose the design; redirect it where it's wrong about your life.
2. **Ask for the smallest version that delivers the value.** One product, one worker, one alert. You can grow a working thing; a grand design that half-exists mostly generates debt.
3. **Make it record the decision.** The steward's charter already says so: non-trivial choices land in `decisions.md`, operational knowledge lands in the KB. Six months from now, a session that can *read why* beats a session that can only see *what*.
4. **Make it test what it built.** Have it exercise the real path end to end — fire the hook, run the service, render the page — before you call it done. "It should work" is not a state.
5. **Let it write the handoff.** If the build spans sessions, `/handoff-leave` at every break. The next session resumes mid-thought.

That's the whole loop: flag → design together → build smallest → record → verify → hand off. It is exactly the loop the steward's charter describes, because extending the system *is* the steward's job — you're not working around the system to improve it, you're using it.

## The deep end

`docs/llm-bootstrap.md` is the same idea at full strength: a specification you hand to a fresh Claude Code session on an empty machine, from which it builds this entire system — asking you to confirm the choices that are yours — and then *becomes its steward*. Read it even if you never run it; it will recalibrate what you consider reasonable to ask for.

Then go ask for something unreasonable.

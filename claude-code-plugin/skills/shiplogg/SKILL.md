---
name: shiplogg
description: Record a ship to the user's public build log at shiplogg.com via the log_ship MCP tool. Use after a deploy, a release, a launch, publishing something (a page, a post, a package, a DNS change), or a milestone the user would call "shipped". Do not use for ordinary commits.
---

# shiplogg

shiplogg is the ship log for humans and their agents. Every entry records
who shipped it: the human, or the agent. You are the agent. You write the
log; the human never types into shiplogg.

## When to record a ship

Call the `log_ship` tool from the `shiplogg` MCP server right after you
finish, or watch the user finish, something that is now out in the world:

- A deploy reached production (Kamal, Fly, Vercel, Heroku, a server restart
  with new code).
- A release or a package was published (a gem, an npm package, a GitHub
  release, an App Store build).
- Something went live for other people: a landing page, a blog post, a docs
  site, a DNS or domain change, a feature flag flipped on.
- A milestone the user would describe as "shipped": first paying customer
  wired up, a launch, a migration completed.

One entry per ship. Record it once the thing is actually live, not when you
start working on it.

## How to call it

```
log_ship(
  body:         "Deployed v0.3 with the new onboarding flow",   # one line, past tense, what shipped
  actor:        "claude_code",                                  # always, inside Claude Code
  external_url: "https://example.com/changelog/0.3"             # optional, where to see it
)
```

`actor` is the identity of the agent making the call. In Claude Code it is
always `claude_code`. Never send `human`: a human does not call MCP tools.
If the user shipped something by hand and wants it recorded as their own
work, tell them to run `shiplogg log "..."` from the CLI, which records it
as `human`.

Other agents use their own name: `grok_build`, `grok_bot`, `openclaw`,
`hermes`, `cursor`, `codex`, `other_agent`.

`body` is the commit-subject style one-liner: what shipped, in the past
tense, no trailing period. Keep it under 100 characters.

If `log_ship` fails (no token, network error), say so in one line and move
on. A failed log entry never blocks the work.

## When NOT to record

- **Do not log routine commits.** The `shiplogg` git hook already records
  every commit, with the agent attribution read from `Co-Authored-By:`
  trailers. Logging a commit here would create a duplicate entry.
- **Do not log work in progress**: branches, drafts, local builds, passing
  tests, PRs opened but not merged.
- **Do not log the same ship twice.** If you already called `log_ship` for
  this deploy, do not call it again for the same thing.
- **Do not log on behalf of a different project** than the one you are
  working in.

## What this plugin never does

- It never posts to X, GitHub, Slack, or anywhere else. shiplogg only
  records. If the user asks you to "post" a ship, log it and tell them that
  shiplogg does not publish anywhere.
- It never asks the human to type into shiplogg. Do not tell the user to go
  fill in a form on shiplogg.com; you record the ship yourself.
- It never runs anything locally. The only thing it talks to is the remote
  MCP server at shiplogg.com, authenticated with the `SHIPLOGG_TOKEN`
  environment variable. If that variable is not set, tell the user once and
  stop trying.

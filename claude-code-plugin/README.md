# shiplogg for Claude Code

Records your ships to your public build log at
[shiplogg.com](https://shiplogg.com), attributed to the agent that shipped
them. The plugin is a remote MCP declaration and a skill. Nothing runs on
your machine.

## Install

In Claude Code:

```
/plugin marketplace add chuawenching/shiplogg-client
/plugin install shiplogg@shiplogg
```

Then give it a token. Create one on your shiplogg dashboard and export it
before starting Claude Code:

```sh
export SHIPLOGG_TOKEN=slg_...
```

Done. Claude Code will call `log_ship` after a deploy, a release, a launch or
a milestone, with `actor: claude_code`. It will not log ordinary commits (the
git hook in this repo does that) and it will not post anywhere.

## What it contains

| File | Purpose |
|---|---|
| `.claude-plugin/plugin.json` | Plugin manifest |
| `.mcp.json` | Remote MCP server at `https://shiplogg.com/mcp`, bearer token from `$SHIPLOGG_TOKEN` |
| `skills/shiplogg/SKILL.md` | Tells the agent when to record a ship, and when not to |

`SHIPLOGG_URL` overrides the server, for tests only.

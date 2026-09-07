# shiplogg for Codex

A Codex plugin. It declares the remote shiplogg MCP server at
`https://shiplogg.com/mcp` (streamable HTTP, bearer token from
`SHIPLOGG_TOKEN`) and ships one skill that tells Codex when to record a
ship. Nothing runs on your machine.

```
.codex-plugin/plugin.json   manifest
.mcp.json                   the remote MCP server
skills/shiplogg/SKILL.md    when to call log_ship, with actor "codex"
```

Install instructions are in the [repo README](../../README.md#codex-plugin).

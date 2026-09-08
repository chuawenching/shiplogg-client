# shiplogg-client

The client side of [shiplogg](https://shiplogg.com), the ship log for humans
and their agents. Open source, MIT.

## What it does

`hooks/post-commit` is a git hook. Every time you commit, it records that
commit to your public build log at `shiplogg.com/@you`, together with **who
shipped it**: you, or the agent that co-authored the commit (Claude Code,
Codex, Cursor, Grok, OpenClaw, Hermes...). The server reads the
`Co-Authored-By:` trailers that agents already add to their commits, so the
attribution is a side-effect of working. You never type into shiplogg.

The hook is POSIX `sh` plus `curl`. No Ruby, no Node, no dependencies. It runs
in the background, gives up after 5 seconds, and never fails a commit. It
prints nothing on success and one line on failure.

Merge commits are skipped, and so is any commit whose message contains
`[skip shiplogg]`.

## Install

From the root of the repo you want to log:

```sh
curl -fsSL https://raw.githubusercontent.com/chuawenching/shiplogg-client/main/hooks/post-commit -o .git/hooks/post-commit && chmod +x .git/hooks/post-commit
```

Then give it a token. Create one on your shiplogg dashboard and either export
it:

```sh
export SHIPLOGG_TOKEN=slg_...
```

or put it in a `.shiplogg` file in the repo root, which must be gitignored:

```sh
printf 'token=slg_...\n' > .shiplogg && echo .shiplogg >> .gitignore
```

Optional: `project=my-app` in the same file (or `$SHIPLOGG_PROJECT`) picks
which of your shiplogg projects the entries go to. Without it, entries go to
your first project.

If you already have a `post-commit` hook, add a line to it that calls this
one. If your repo sets `core.hooksPath` (husky, lefthook), put the file in
that directory instead of `.git/hooks`.

## CLI

The `shiplogg` gem wraps the hook and the API. Ruby 3.2 or newer, no
dependencies beyond the standard library.

```sh
gem install shiplogg
```

Or from a checkout of this repo:

```sh
gem build shiplogg.gemspec && gem install --local shiplogg-*.gem
```

Then, from the root of the repo you want to log:

```
shiplogg init                       # token, project, .shiplogg, .gitignore, hook
shiplogg log "shipped the landing page"
shiplogg log "wired up auth" --by claude_code --url https://github.com/you/app/pull/12
shiplogg status                     # your stats and public URL
shiplogg hook install | uninstall   # just the post-commit hook
shiplogg init --agent codex         # register the Codex plugin, see below
shiplogg init --agent antigravity   # MCP server + skill + rule for Antigravity, see below
shiplogg disclose antigravity       # just the commit-attribution rule and skill
```

`init` reads the token from `$SHIPLOGG_TOKEN` or prompts for it without
echo, checks it against `/api/v1/me`, lets you pick a project when you have
more than one, writes `.shiplogg` (mode 600), adds it to `.gitignore`, and
installs the hook. It is safe to run again; nothing is duplicated.

`log` creates an entry with `source: cli`. The actor defaults to `human` and
must be one of `human`, `claude_code`, `grok_build`, `grok_bot`, `openclaw`,
`hermes`, `cursor`, `codex`, `gemini`, `other_agent`. It is for the ships that are not
a commit: a deploy, a launch, a DNS change. Commits come in through the hook.

`status` shows the self-reported split and, separately, the verified split
once any of your commits have been checked against GitHub. The two are never
merged.

The hook the gem installs is the same `hooks/post-commit` file as above, so
everything in "What gets sent" applies. A `post-commit` hook that the gem did
not write is left alone: `install` prints the line to add to it, and
`uninstall` refuses to delete it. Repos with `core.hooksPath` set (husky,
lefthook) get the hook in that directory.

Run the tests with `rake test`. HTTP is stubbed; nothing leaves the machine.

## Claude Code plugin

`claude-code-plugin/` is a Claude Code plugin. It declares the remote MCP
server at `https://shiplogg.com/mcp` and ships a skill that tells Claude Code
when to record a ship. Nothing runs locally.

In Claude Code:

```
/plugin marketplace add chuawenching/shiplogg-client
/plugin install shiplogg@shiplogg
```

Then export your token before starting Claude Code:

```sh
export SHIPLOGG_TOKEN=slg_...
```

Done. Claude Code calls `log_ship` after a deploy, a release, a launch or a
milestone, with `actor: claude_code`. It does not log ordinary commits (the
hook does that) and it does not post anywhere. See
[`claude-code-plugin/README.md`](claude-code-plugin/README.md).

## Codex plugin

`plugins/shiplogg-codex/` is a [Codex plugin](https://developers.openai.com/plugins/build/plugins).
It declares the remote MCP server at `https://shiplogg.com/mcp` (streamable
HTTP, bearer token from `SHIPLOGG_TOKEN`) and ships a skill that tells Codex
when to record a ship, with `actor: codex`. Nothing runs locally.

Install in three steps:

1. Add the marketplace. Either one line in your shell:

   ```sh
   codex plugin marketplace add chuawenching/shiplogg-client
   ```

   or, with the gem installed, let the CLI write the entry into your personal
   marketplace at `~/.agents/plugins/marketplace.json`:

   ```sh
   shiplogg init --agent codex
   ```

2. Export your token before starting Codex:

   ```sh
   export SHIPLOGG_TOKEN=slg_...
   ```

3. In Codex, run `/plugins`, open the marketplace (`shiplogg` or `Personal
   plugins`) and install shiplogg. Or from the shell:

   ```sh
   codex plugin add shiplogg@shiplogg      # after step 1a
   codex plugin add shiplogg@personal      # after step 1b
   ```

`codex mcp list` then shows `shiplogg` as an enabled streamable HTTP server
with `SHIPLOGG_TOKEN` as its bearer token variable, and the session has the
`log_ship`, `list_recent` and `stats` tools. Codex calls `log_ship` after a
deploy, a release, a launch or a milestone. It does not log ordinary commits
(the hook does that) and it does not post anywhere. See
[`plugins/shiplogg-codex/README.md`](plugins/shiplogg-codex/README.md).

Anyone who opens this repo in Codex also sees the marketplace, because it is
checked in at `.agents/plugins/marketplace.json`.

The OpenAI-curated marketplace (the "Codex official" list) is a separate
submission at [platform.openai.com/plugins](https://platform.openai.com/plugins).
It requires a verified developer identity, domain verification of the MCP
server, a privacy policy, and a set of test cases, and it is reviewed by
OpenAI. shiplogg is not there yet.

## Antigravity

Antigravity (the IDE, the `agy` CLI and the 2.0 app) has no plugin
marketplace. It reads one shared config root, `~/.gemini/config/`, and one
global rules file, `~/.gemini/GEMINI.md`. The gem writes to both. Two steps:

1. With the gem installed, and your token in `SHIPLOGG_TOKEN`:

   ```sh
   shiplogg init --agent antigravity
   ```

   This writes three things and prints each path:

   - The remote MCP server into `~/.gemini/config/mcp_config.json`, as
     `serverUrl: https://shiplogg.com/mcp` with an `Authorization: Bearer`
     header. **The token is written into that file in clear text**, because
     Antigravity does not substitute environment variables in headers. The
     file is set to mode 600. Other servers in the file are left alone.
   - The shiplogg skill into `~/.gemini/config/skills/shiplogg/SKILL.md`.
     Same content as the Claude Code skill, with `actor: gemini`.
   - A commit-attribution rule into `~/.gemini/GEMINI.md`, between
     `<!-- shiplogg:start -->` and `<!-- shiplogg:end -->` markers, so it
     can be updated later without touching your own rules.

2. Restart Antigravity, or run `/mcp` in the CLI. `shiplogg` shows up as a
   connected HTTP server with `log_ship`, `list_recent` and `stats`.

Run it again any time; nothing is duplicated.

### Why the rule, and `shiplogg disclose`

Claude Code and Codex add a `Co-Authored-By:` trailer to their commits on
their own. Antigravity does not, so its commits look human. The rule tells
it to end every commit it writes with:

```
Co-Authored-By: Antigravity <noreply@google.com>
```

The skill carries the same instruction, but Antigravity loads skills on
demand (only the description is in context until the agent decides it needs
the skill), and in testing a routine commit never triggered it. Rules in
`~/.gemini/GEMINI.md` are always applied, and with the rule in place the
trailer holds. Tested with `agy` 1.1.27:

```
$ git log -1 --format=%B
Add hello2.txt

Co-Authored-By: Antigravity <noreply@google.com>
```

The hook records that commit as `gemini`. Without the rule, the same test
produced a bare `Add hello.txt with greeting from agy`, recorded as `human`.

`shiplogg disclose antigravity` installs just the rule and the skill, for
people who want the attribution without the MCP server. It is the first
target of `disclose`; Cursor and the others follow.

### Paths, verified

Older tutorials say `~/.gemini/antigravity/skills/`, and the `agents-cli`
installer writes to `~/.agents/skills/`. Antigravity reads neither. The
current docs, the customization guide bundled inside the app, and the `agy`
skill list all agree on `~/.gemini/config/skills/`. The MCP file must use
`serverUrl`; `url` and `httpUrl` are rejected.

## What gets sent

One JSON request per commit, to `POST https://shiplogg.com/api/v1/entries`,
authenticated with your token:

| Field | Value |
|---|---|
| `body` | The commit subject line |
| `external_id` | The commit SHA |
| `shipped_at` | The author date |
| `commit_message` | The full commit message, so the server can read `Co-Authored-By:` trailers |
| `external_url` | The GitHub commit URL, only when `origin` is a GitHub remote |
| `source` | Always `git_hook` |
| `project` | Your project slug, only if configured |

The same SHA is never recorded twice. Re-running the hook on a commit that is
already logged is a no-op on the server.

## What does not get sent

- No diff. Not a single line of it.
- No file contents, file names, or paths.
- No branch names, tags, or remote URLs other than the derived GitHub commit link.
- No author name or email. Your identity on shiplogg comes from the token, not the commit.
- Nothing about commits that have not happened yet, and nothing about repos where the hook is not installed.

Only the subject, the SHA, the date, and the message with its trailers.
Read the hook; it is about 130 lines.

## Configuration reference

| Setting | Env | `.shiplogg` key | Default |
|---|---|---|---|
| API token | `SHIPLOGG_TOKEN` | `token` | none, required |
| Project slug | `SHIPLOGG_PROJECT` | `project` | your first project |
| Server | `SHIPLOGG_URL` | none | `https://shiplogg.com` |

Environment variables win over the file. `SHIPLOGG_URL` exists so the test
suite can point at a local server. `init --agent antigravity` writes the
`SHIPLOGG_URL` in effect into the MCP config, so run it without that
variable set unless you mean it.

## License

MIT. See `LICENSE`.

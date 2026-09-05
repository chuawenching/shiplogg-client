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
```

`init` reads the token from `$SHIPLOGG_TOKEN` or prompts for it without
echo, checks it against `/api/v1/me`, lets you pick a project when you have
more than one, writes `.shiplogg` (mode 600), adds it to `.gitignore`, and
installs the hook. It is safe to run again; nothing is duplicated.

`log` creates an entry with `source: cli`. The actor defaults to `human` and
must be one of `human`, `claude_code`, `grok_build`, `grok_bot`, `openclaw`,
`hermes`, `cursor`, `codex`, `other_agent`. It is for the ships that are not
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
suite can point at a local server.

## License

MIT. See `LICENSE`.

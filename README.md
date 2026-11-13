# goose.git-ai

Line-level AI attribution for [goose](https://goose-docs.ai), powered by [Git AI](https://usegitai.com).

This plugin connects goose to Git AI. Every line goose writes is recorded in your Git history together
with the agent, model and session, so `git-ai blame` and `git-ai stats` can tell goose's code apart from yours:

```text
$ git-ai blame app.py
^bb9998a (Jane Doe  ... 1) def hello():
^bb9998a (Jane Doe  ... 2)     return "hi"
8482bda0 (goose     ... 3)
8482bda0 (goose     ... 4) def bye():
8482bda0 (goose     ... 5)     return "bye"
```

Git AI does not support goose officially yet. The plugin fills that gap with two existing pieces:
goose [lifecycle hooks](https://goose-docs.ai/docs/guides/context-engineering/hooks/) and Git AI's
generic [`agent-v1`](https://usegitai.com/docs/add-your-agent) checkpoint preset.

## Quick start

You need goose with plugin support, `git`, `bash` and [`jq`](https://jqlang.org).

```bash
# 1. Install Git AI (1.7.7 or later) and its git hooks
curl -sSL https://usegitai.com/install.sh | bash
git-ai install-hooks

# 2. Install the plugin
goose plugin install https://github.com/janrauchfuss/goose.git-ai.git

# 3. Tell the plugin which model goose uses (if it is not in ~/.config/goose/config.yaml)
export GOOSE_MODEL=claude-sonnet-4-5
```

Without `git-ai install-hooks`, Git AI never writes attribution to your commits. The command is
needed even though Git AI has no built-in goose support.

Then work with goose as usual and commit.

### Other ways to install

| Scope | Command |
| --- | --- |
| User, with auto-update | `goose plugin install --auto-update https://github.com/janrauchfuss/goose.git-ai.git` |
| Single project, versioned with the repo | `git clone https://github.com/janrauchfuss/goose.git-ai .agents/plugins/git-ai` |
| Local checkout (symlink, for development) | `just install` |

Update with `goose plugin update git-ai`. To disable the plugin, add `"git-ai"` to `disabledPlugins` in
`~/.config/goose/settings.json`.

## Check that it works

```bash
git-ai status                 # before committing: pending checkpoints from goose
git log -1 --show-notes=ai    # after committing: the attribution note
git-ai stats --json           # AI vs. human lines, per agent and model
```

| Symptom | Likely cause |
| --- | --- |
| `git-ai status` shows no checkpoints | `git-ai` or `jq` is not on the `PATH` of the goose session |
| Checkpoints exist, but commits get no note | `git-ai install-hooks` was not run |
| Model shows as `unknown` | `GOOSE_MODEL` is not set and not in goose's `config.yaml` |
| Notes missing on the remote | Notes are not pushed: `git push origin refs/notes/ai` |

The hook writes its errors to stderr with the prefix `[goose-git-ai]`.

## How it works

goose runs [scripts/gitai-hook.sh](scripts/gitai-hook.sh) before and after each file-changing tool call.
The script sends the matching checkpoint to `git-ai checkpoint agent-v1`:

| goose event | Tool | Git AI checkpoint |
| --- | --- | --- |
| `PreToolUse` | `write`, `edit` | `human`: changes made since the last checkpoint count as yours |
| `PostToolUse` | `write`, `edit` | `ai_agent`: the edited file counts as goose's |
| `PreToolUse` | `shell` | `pre_shell_command`: Git AI snapshots the working tree |
| `PostToolUse`, `PostToolUseFailure` | `shell` | `post_shell_command`: Git AI attributes whatever the command changed |

The goose session ID becomes the Git AI conversation ID. The model comes from `GOOSE_MODEL`, then
`~/.config/goose/config.yaml`, otherwise `unknown`. At commit time, Git AI turns the checkpoints into a
note under `refs/notes/ai`.

The hook never gets in goose's way:

- It writes nothing to stdout, so it can't affect goose's tool decisions.
- It always exits `0`.
- It skips silently outside Git repositories or when `git-ai` is not installed.

## Limitations

- **Built-in tools only.** The hook covers `write`, `edit` and `shell`, with or without the `developer__`
  prefix. File-writing tools from other extensions need their names added to the matcher in
  [hooks/hooks.json](hooks/hooks.json).
- **No prompts.** `agent-v1` ignores transcripts, so notes link lines to a goose session, not to a prompt.
- **One model per session.** If you switch models mid-session, the hook still reports only the
  `GOOSE_MODEL` value.
- **Adjacent human edits.** Git AI may attribute a hand-written line to goose when it sits right next to
  goose's lines.
- **Containers.** Don't run as root, or set `GIT_AI_ALLOW_SUPERUSER=1`. Keep the container running until
  the push is done.
- **Squash and rebase merges in the web UI** drop notes. Run `git ai ci github install` (or `gitlab`) to fix
  them in CI.

## Development

```bash
mise install && just setup   # tools and git hooks (lefthook)
just check                   # shellcheck, shfmt, bats, JSON and workflow lint
just --list                  # all recipes
```

Commits follow [Conventional Commits](https://www.conventionalcommits.org/). [CHANGELOG.md](CHANGELOG.md)
is generated by [git-cliff](https://git-cliff.org) in the release workflow. To release, run `just release` (or `just release 0.2.0`).
See [CONTRIBUTING.md](CONTRIBUTING.md).

## License

This project is licensed under the [MIT License](LICENSE).

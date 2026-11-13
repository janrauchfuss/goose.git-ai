# Contributing

1. `mise install && just setup` – installs tools and git hooks.
2. Use [Conventional Commits](https://www.conventionalcommits.org/) – the changelog is generated from them via git-cliff.
3. `just check` must pass (shellcheck, shfmt, bats, JSON/workflow validation).
4. Keep the hook script POSIX-friendly Bash + `jq`, silent on stdout, and non-blocking (always exit 0).

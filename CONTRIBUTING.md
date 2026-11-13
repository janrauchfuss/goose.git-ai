# Contributing

Thanks for helping! Changes reach `main` only through pull requests.

## Workflow

1. Fork the repository and create a branch.
2. `mise install && just setup` installs the tools and git hooks.
3. Make your change. Keep the hook Bash + `jq`, silent on stdout and non-blocking (always exit 0).
4. `just check` must pass (shellcheck, shfmt, bats, JSON and workflow lint).
5. Open a pull request. Its title must follow [Conventional Commits](https://www.conventionalcommits.org/),
   for example `fix: resolve relative paths against working_dir`.

## Rules for `main`

- No direct pushes, force pushes or deletions.
- Every pull request needs a passing CI check (`check`) and an approval from the code owner.
- Pull requests are squash-merged, so the PR title becomes the commit message.
- Don't edit `CHANGELOG.md`. CI rejects pull requests that touch it; the release workflow generates it.

## Releases (maintainer)

Releases run entirely in GitHub Actions, the only place that writes `CHANGELOG.md`:

```bash
just next-version        # preview the version derived from conventional commits
just changelog-preview   # preview the release notes
just release             # or: just release 0.2.0
```

The [release workflow](.github/workflows/release.yml) runs the checks, regenerates `CHANGELOG.md`,
bumps `plugin.json`, commits `chore(release): vX.Y.Z` to `main`, tags it and creates the GitHub release.

## Security

Report vulnerabilities privately, see [SECURITY.md](SECURITY.md).

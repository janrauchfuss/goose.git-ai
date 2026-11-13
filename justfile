set shell := ["bash", "-euo", "pipefail", "-c"]

plugin_dir := env_var_or_default("GOOSE_PLUGIN_DIR", env_var("HOME") / ".agents/plugins/git-ai")

# List recipes
default:
    @just --list

# Install tools and git hooks
setup:
    mise install
    lefthook install

# Run all checks
check: lint test validate

# Lint and format-check
lint:
    shellcheck scripts/*.sh
    shfmt -d -i 2 -ci scripts/*.sh

# Auto-fix lint and formatting
fmt:
    shfmt -w -i 2 -ci scripts/*.sh

# Run unit tests
test:
    bats tests

# Validate JSON manifests and workflows
validate:
    jq empty plugin.json hooks/hooks.json
    actionlint

# Install the plugin for the current user (symlink, so edits apply immediately)
install:
    mkdir -p "$(dirname '{{ plugin_dir }}')"
    ln -sfn "{{ justfile_directory() }}" "{{ plugin_dir }}"
    @echo "Linked {{ plugin_dir }}"

# Remove the user-level plugin link
uninstall:
    rm -f "{{ plugin_dir }}"

# Preview the changelog for unreleased commits (CHANGELOG.md is written only by the release workflow)
changelog-preview:
    git cliff --unreleased

# Show the next version derived from conventional commits
next-version:
    git cliff --bumped-version

# Trigger the release workflow: `just release` (auto version) or `just release 0.2.0`
release version="":
    gh workflow run release.yml --ref main {{ if version != "" { "-f version=" + version } else { "" } }}
    @echo "Release started: gh run watch"

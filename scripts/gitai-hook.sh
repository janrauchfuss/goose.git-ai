#!/usr/bin/env bash
# goose plugin: report file changes made by goose to Git AI (preset agent-v1).
#
# Reads a goose hook payload as JSON on stdin and forwards the matching
# checkpoint to `git-ai checkpoint agent-v1 --hook-input stdin`.
#
# Never writes to stdout (goose reads it as a PreToolUse decision) and never
# blocks goose: every failure is logged to stderr and the exit code stays 0.

set -uo pipefail

AGENT_NAME="goose"
FILE_TOOLS='(^|__)(write|edit)$'
SHELL_TOOL='(^|__)shell$'

log() { printf '[goose-git-ai] %s\n' "$*" >&2; }

current_model() {
  if [[ -n "${GOOSE_MODEL:-}" ]]; then
    printf '%s' "$GOOSE_MODEL"
    return
  fi
  local cfg="${XDG_CONFIG_HOME:-$HOME/.config}/goose/config.yaml" line
  if [[ -r "$cfg" ]]; then
    line=$(grep -m1 '^GOOSE_MODEL:' "$cfg" 2>/dev/null) || line=""
    if [[ -n "$line" ]]; then
      line=${line#GOOSE_MODEL:}
      line=${line//[\'\" ]/}
      printf '%s' "$line"
      return
    fi
  fi
  printf 'unknown'
}

# Absolute path: expand ~, resolve relative paths against the working dir.
abs_path() {
  local p=$1 cwd=$2
  case "$p" in
    \~) p=$HOME ;;
    \~/*) p="$HOME/${p#\~/}" ;;
  esac
  case "$p" in
    /*) printf '%s' "$p" ;;
    *) printf '%s/%s' "${cwd%/}" "$p" ;;
  esac
}

checkpoint() {
  local payload=$1 err
  if ! err=$(printf '%s' "$payload" | git-ai checkpoint agent-v1 --hook-input stdin 2>&1 >/dev/null); then
    log "checkpoint failed: $err"
  fi
}

main() {
  command -v git-ai >/dev/null 2>&1 || return 0 # Git AI not installed
  command -v jq >/dev/null 2>&1 || {
    log "jq not found, skipping"
    return 0
  }

  local input
  input=$(cat)
  jq -e 'type == "object"' >/dev/null 2>&1 <<<"$input" || return 0

  local event tool cwd root session
  event=$(jq -r '.event // ""' <<<"$input")
  tool=$(jq -r '.tool_name // ""' <<<"$input")
  session=$(jq -r '.session_id // "unknown"' <<<"$input")
  cwd=$(jq -r '.working_dir // ""' <<<"$input")
  [[ -n "$cwd" ]] || cwd=$PWD

  root=$(git -C "$cwd" rev-parse --show-toplevel 2>/dev/null) || return 0 # not a git repo

  local payload
  if [[ "$tool" =~ $FILE_TOOLS ]]; then
    local path
    path=$(jq -r '.tool_input.path // ""' <<<"$input")
    [[ -n "$path" ]] || return 0
    path=$(abs_path "$path" "$cwd")
    case "$event" in
      PreToolUse)
        payload=$(jq -n --arg root "$root" --arg path "$path" \
          '{type: "human", repo_working_dir: $root, will_edit_filepaths: [$path]}')
        ;;
      PostToolUse)
        payload=$(jq -n --arg root "$root" --arg path "$path" --arg agent "$AGENT_NAME" \
          --arg model "$(current_model)" --arg sid "$session" \
          '{type: "ai_agent", repo_working_dir: $root, agent_name: $agent, model: $model,
            conversation_id: $sid, edited_filepaths: [$path]}')
        ;;
      *) return 0 ;;
    esac
  elif [[ "$tool" =~ $SHELL_TOOL ]]; then
    local type
    case "$event" in
      PreToolUse) type=pre_shell_command ;;
      PostToolUse | PostToolUseFailure) type=post_shell_command ;;
      *) return 0 ;;
    esac
    payload=$(jq --arg type "$type" --arg root "$root" --arg agent "$AGENT_NAME" \
      --arg model "$(current_model)" --arg sid "$session" \
      '{type: $type, repo_working_dir: $root, agent_name: $agent, model: $model,
        conversation_id: $sid,
        tool_use_id: (.tool_call_id // "shell"),
        command: (.tool_input.command // "")}' <<<"$input")
  else
    return 0
  fi

  checkpoint "$payload"
}

main || true
exit 0

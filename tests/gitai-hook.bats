#!/usr/bin/env bats

setup() {
  SCRIPT="$BATS_TEST_DIRNAME/../scripts/gitai-hook.sh"
  TMP=$(mktemp -d)
  REPO="$TMP/repo"
  mkdir -p "$REPO" "$TMP/bin"
  git -C "$REPO" init -q
  # Fake git-ai: records the args and stdin
  cat >"$TMP/bin/git-ai" <<'STUB'
#!/usr/bin/env bash
echo "$*" >"$CAPTURE.args"
cat >"$CAPTURE"
STUB
  chmod +x "$TMP/bin/git-ai"
  export CAPTURE="$TMP/capture"
  export PATH="$TMP/bin:$PATH"
  export GOOSE_MODEL=test-model
  REPO_REAL=$(cd "$REPO" && pwd -P)
}

teardown() { rm -rf "$TMP"; }

run_hook() { printf '%s' "$1" | "$SCRIPT"; }

@test "write PreToolUse -> human checkpoint" {
  out=$(run_hook "{\"event\":\"PreToolUse\",\"tool_name\":\"write\",\"working_dir\":\"$REPO\",\"tool_input\":{\"path\":\"a.py\"}}")
  [ -z "$out" ]
  [ "$(cat "$CAPTURE.args")" = "checkpoint agent-v1 --hook-input stdin" ]
  [ "$(jq -r .type "$CAPTURE")" = human ]
  [ "$(jq -r '.will_edit_filepaths[0]' "$CAPTURE")" = "$REPO/a.py" ]
  [ "$(jq -r .repo_working_dir "$CAPTURE")" = "$REPO_REAL" ]
}

@test "developer__edit PostToolUse -> ai_agent checkpoint" {
  run_hook "{\"event\":\"PostToolUse\",\"tool_name\":\"developer__edit\",\"session_id\":\"s1\",\"working_dir\":\"$REPO\",\"tool_input\":{\"path\":\"a.py\"}}"
  [ "$(jq -r .type "$CAPTURE")" = ai_agent ]
  [ "$(jq -r .agent_name "$CAPTURE")" = goose ]
  [ "$(jq -r .model "$CAPTURE")" = test-model ]
  [ "$(jq -r .conversation_id "$CAPTURE")" = s1 ]
  [ "$(jq -r '.edited_filepaths[0]' "$CAPTURE")" = "$REPO/a.py" ]
}

@test "shell Pre/Post/Failure map to shell checkpoints" {
  base="\"tool_name\":\"shell\",\"tool_call_id\":\"t1\",\"working_dir\":\"$REPO\",\"tool_input\":{\"command\":\"echo 'hi'\\nls\"}"
  run_hook "{\"event\":\"PreToolUse\",$base}"
  [ "$(jq -r .type "$CAPTURE")" = pre_shell_command ]
  [ "$(jq -r .tool_use_id "$CAPTURE")" = t1 ]
  [ "$(jq -r .command "$CAPTURE")" = "$(printf "echo 'hi'\nls")" ]
  for e in PostToolUse PostToolUseFailure; do
    rm "$CAPTURE"
    run_hook "{\"event\":\"$e\",$base}"
    [ "$(jq -r .type "$CAPTURE")" = post_shell_command ]
  done
}

@test "unrelated tool is ignored" {
  run_hook "{\"event\":\"PreToolUse\",\"tool_name\":\"other__write_file\",\"working_dir\":\"$REPO\",\"tool_input\":{\"path\":\"a\"}}"
  [ ! -e "$CAPTURE" ]
}

@test "missing path is ignored" {
  run_hook "{\"event\":\"PreToolUse\",\"tool_name\":\"write\",\"working_dir\":\"$REPO\",\"tool_input\":{}}"
  [ ! -e "$CAPTURE" ]
}

@test "missing session falls back to unknown" {
  run_hook "{\"event\":\"PostToolUse\",\"tool_name\":\"write\",\"working_dir\":\"$REPO\",\"tool_input\":{\"path\":\"a\"}}"
  [ "$(jq -r .conversation_id "$CAPTURE")" = unknown ]
}

@test "model falls back to config.yaml, then unknown" {
  unset GOOSE_MODEL
  mkdir -p "$TMP/cfg/goose"
  echo "GOOSE_MODEL: 'foo'" >"$TMP/cfg/goose/config.yaml"
  XDG_CONFIG_HOME="$TMP/cfg" run_hook "{\"event\":\"PostToolUse\",\"tool_name\":\"write\",\"working_dir\":\"$REPO\",\"tool_input\":{\"path\":\"a\"}}"
  [ "$(jq -r .model "$CAPTURE")" = foo ]
  XDG_CONFIG_HOME="$TMP/none" run_hook "{\"event\":\"PostToolUse\",\"tool_name\":\"write\",\"working_dir\":\"$REPO\",\"tool_input\":{\"path\":\"a\"}}"
  [ "$(jq -r .model "$CAPTURE")" = unknown ]
}

@test "non-git directory, bad JSON and failing git-ai never fail" {
  run_hook "{\"event\":\"PreToolUse\",\"tool_name\":\"write\",\"working_dir\":\"$TMP\",\"tool_input\":{\"path\":\"a\"}}"
  [ ! -e "$CAPTURE" ]
  run bash -c "echo 'not json' | $SCRIPT"
  [ "$status" -eq 0 ]
  printf '#!/usr/bin/env bash\nexit 1\n' >"$TMP/bin/git-ai"
  run bash -c "printf '%s' '{\"event\":\"PreToolUse\",\"tool_name\":\"write\",\"working_dir\":\"$REPO\",\"tool_input\":{\"path\":\"a\"}}' | $SCRIPT"
  [ "$status" -eq 0 ]
  [ -z "$output" ] || [[ "$output" == *"goose-git-ai"* ]]
}

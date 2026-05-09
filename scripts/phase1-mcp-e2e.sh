#!/usr/bin/env bash
set -euo pipefail

# 打印带统一前缀的执行日志。
log() {
  printf '[phase1-mcp-e2e] %s\n' "$*"
}

# 判断命令是否存在。
has_command() {
  command -v "$1" >/dev/null 2>&1
}

# 打印单个命令的存在状态。
check_command() {
  local name="$1"
  if has_command "$name"; then
    log "OK command: $name -> $(command -v "$name")"
  else
    log "MISSING command: $name"
  fi
}

# 打印环境变量是否存在，但不输出变量值。
check_env_key() {
  local name="$1"
  if [[ -n "${!name:-}" ]]; then
    log "OK env: $name is set"
  else
    log "MISSING env: $name"
  fi
}

# 安全打印 SliceAI MCP 配置摘要，不泄露 env 值。
print_mcp_config_summary() {
  local config_path="$HOME/Library/Application Support/SliceAI/mcp.json"
  if [[ ! -f "$config_path" ]]; then
    log "MISSING config: $config_path"
    return
  fi

  log "OK config: $config_path"
  if ! has_command jq; then
    log "SKIP config summary: jq not found"
    return
  fi

  jq '{
    servers: [
      .servers[]? | {
        id,
        transport,
        command,
        args,
        url,
        env_keys: ((.env // {}) | keys)
      }
    ]
  }' "$config_path"
}

# 打印 5 个 MCP server 的推荐本地命令模板。
print_server_command_templates() {
  cat <<'EOF'

Recommended local server commands:

1. filesystem
   npx -y @modelcontextprotocol/server-filesystem "$SLICEAI_E2E_FILESYSTEM_DIR"

2. postgres
   npx -y @modelcontextprotocol/server-postgres "$SLICEAI_E2E_POSTGRES_URL"

3. brave-search
   BRAVE_API_KEY="<set in shell or SliceAI env>" npx -y @modelcontextprotocol/server-brave-search

4. git
   uvx --from mcp-server-git mcp-server-git --repository "$SLICEAI_E2E_GIT_REPO"

5. sqlite
   uvx --from mcp-server-sqlite mcp-server-sqlite --db-path "$SLICEAI_E2E_SQLITE_DB"
EOF
}

# 打印需要在 SliceAI App 中完成并记录的手工 E2E 矩阵。
print_manual_e2e_matrix() {
  cat <<'EOF'

Manual MCP E2E evidence to record:

- filesystem: Settings test connection lists tools; one safe read-only call succeeds.
- postgres: Settings test connection lists tools; one read-only schema/query call succeeds.
- brave-search: Settings test connection lists tools; one search call succeeds.
- git: Settings test connection lists tools; one read-only status/log call succeeds.
- sqlite: Settings test connection lists tools; one read-only query succeeds.

Manual App regression evidence to record:

- Safari web-search-summarize completes.
- Notes web-search-summarize completes.
- Slack web-search-summarize completes.
- Permission approval path continues execution.
- Permission denial path returns a structured denial, not a crash.
- ResultPanel shows proposed, approved, result, denied, and error rows where applicable.
- Per-tool hotkey triggers the selected tool.
- Command palette still opens with the global hotkey.
EOF
}

# 脚本入口：只做只读探测和 checklist 输出。
main() {
  log "SliceAI Phase 1 MCP E2E checklist"
  log "This script does not print secrets and does not modify SliceAI config."

  check_command node
  check_command npm
  check_command npx
  check_command uvx
  check_command git
  check_command sqlite3
  check_command psql
  check_command jq

  check_env_key BRAVE_API_KEY
  check_env_key SLICEAI_E2E_FILESYSTEM_DIR
  check_env_key SLICEAI_E2E_POSTGRES_URL
  check_env_key SLICEAI_E2E_GIT_REPO
  check_env_key SLICEAI_E2E_SQLITE_DB

  print_mcp_config_summary
  print_server_command_templates
  print_manual_e2e_matrix
}

main "$@"

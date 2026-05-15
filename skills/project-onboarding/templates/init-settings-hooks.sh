#!/usr/bin/env bash
# =============================================================================
# mempalace hook 注册脚本 — 写入 <cwd>/.opencode/settings.json
#
# opencode fork 完全兼容 Claude Code settings.json 协议，
# 自动合并 6 层 settings。本脚本只负责 mempalace 的 4 个 hook：
#   - SessionStart  → 会话开始加载记忆
#   - Stop          → 每 15 条自动存档
#   - PreCompact    → 上下文压缩前紧急存档
#   - PreToolUse    → Glob/Grep/Read 时提醒语义检索可用
#
# graphify hook 由 `graphify claude install` 写入 <cwd>/.claude/settings.json
# gitnexus hook 由 `gitnexus setup` 写入 ~/.claude/settings.json
# 三者由 OPENCODE settings 链自动合并，互不覆盖。
#
# 用法：在目标项目根目录执行
#   bash ~/.agents/skills/project-onboarding/templates/init-settings-hooks.sh
#
# 幂等：已存在且 4 个 hook 全部注册 → 跳过
#       已存在但缺少 → 列出缺失，不覆盖（保护用户自定义）
#       不存在 → 创建完整配置
# =============================================================================

set -euo pipefail

OPENCODE_DIR=".opencode"
SETTINGS_FILE="${OPENCODE_DIR}/settings.json"

detect_mempalace_cmd() {
    local cmd
    cmd=$(command -v mempalace 2>/dev/null)
    if [ -n "$cmd" ]; then
        echo "$cmd"
        return
    fi
    if [ -x "$HOME/.local/bin/mempalace" ]; then
        echo "$HOME/.local/bin/mempalace"
        return
    fi
    echo "mempalace"
}

write_full_settings() {
    local MEMPALACE_CMD
    MEMPALACE_CMD=$(detect_mempalace_cmd)

    cat > "$SETTINGS_FILE" << SETTINGS_EOF
{
  "_comment": "Project-level mempalace hooks. GitNexus hooks live in ~/.claude/settings.json (gitnexus setup); graphify hooks live in <cwd>/.claude/settings.json (graphify claude install). OPENCODE settings chain merges them all — do not duplicate here.",
  "hooks": {
    "SessionStart": [
      {
        "matcher": "*",
        "hooks": [
          {
            "type": "command",
            "command": "${MEMPALACE_CMD} hook run --hook session-start --harness claude-code 2>/dev/null || true"
          }
        ]
      }
    ],
    "PreToolUse": [
      {
        "matcher": "Glob|Grep|Read",
        "hooks": [
          {
            "type": "command",
            "command": "command -v mempalace >/dev/null 2>&1 && [ -d \"\$HOME/.mempalace\" ] && echo '{\"hookSpecificOutput\":{\"hookEventName\":\"PreToolUse\",\"additionalContext\":\"[mempalace] Semantic memory available. Use mempalace_search MCP tool or mempalace search CLI for historical experience retrieval.\"}}' || true"
          }
        ]
      }
    ],
    "Stop": [
      {
        "matcher": "*",
        "hooks": [
          {
            "type": "command",
            "command": "${MEMPALACE_CMD} hook run --hook stop --harness claude-code 2>/dev/null || true"
          }
        ]
      }
    ],
    "PreCompact": [
      {
        "matcher": "*",
        "hooks": [
          {
            "type": "command",
            "command": "${MEMPALACE_CMD} hook run --hook precompact --harness claude-code 2>/dev/null || true"
          }
        ]
      }
    ]
  }
}
SETTINGS_EOF
}

# 主逻辑
mkdir -p "$OPENCODE_DIR"

if [ -f "$SETTINGS_FILE" ]; then
    HAS_SESSION=false
    HAS_STOP=false
    HAS_PRECOMPACT=false
    HAS_PRETOOLUSE=false
    grep -q "hook run --hook session-start" "$SETTINGS_FILE" 2>/dev/null && HAS_SESSION=true
    grep -q "hook run --hook stop"          "$SETTINGS_FILE" 2>/dev/null && HAS_STOP=true
    grep -q "hook run --hook precompact"    "$SETTINGS_FILE" 2>/dev/null && HAS_PRECOMPACT=true
    grep -q "mempalace.*Semantic memory"    "$SETTINGS_FILE" 2>/dev/null && HAS_PRETOOLUSE=true

    if [ "$HAS_SESSION" = true ] && [ "$HAS_STOP" = true ] && [ "$HAS_PRECOMPACT" = true ] && [ "$HAS_PRETOOLUSE" = true ]; then
        echo "⏭️  ${SETTINGS_FILE} 已含 4 个 mempalace hook，跳过"
        exit 0
    fi

    echo "ℹ️  ${SETTINGS_FILE} 已存在但缺少 hook："
    [ "$HAS_SESSION"    = false ] && echo "   ❌ SessionStart  未注册"
    [ "$HAS_PRETOOLUSE" = false ] && echo "   ❌ PreToolUse    未注册"
    [ "$HAS_STOP"       = false ] && echo "   ❌ Stop          未注册"
    [ "$HAS_PRECOMPACT" = false ] && echo "   ❌ PreCompact    未注册"
    echo ""
    echo "   保护现有自定义配置，不覆盖。"
    echo "   如需重置：rm ${SETTINGS_FILE} && bash $0"
    exit 0
fi

write_full_settings

echo "✅ ${SETTINGS_FILE} 创建完成（4 个 mempalace hook）"
echo "   - SessionStart  → 会话开始加载记忆"
echo "   - PreToolUse    → Glob/Grep/Read 时提醒语义检索"
echo "   - Stop          → 每 15 条自动存档"
echo "   - PreCompact    → 上下文压缩前紧急存档"
echo ""
echo "   graphify hook → <cwd>/.claude/settings.json （graphify claude install）"
echo "   gitnexus hook → ~/.claude/settings.json     （gitnexus setup）"
echo "   OPENCODE settings 链自动合并三层"

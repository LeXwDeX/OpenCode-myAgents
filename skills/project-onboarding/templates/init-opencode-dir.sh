#!/usr/bin/env bash
# =============================================================================
# 初始化 .opencode/ 目录 — 项目级 opencode 配置
#
# 创建 .opencode/ 目录，包含：
#   - settings.json（mempalace 4 个 hook，通过 init-settings-hooks.sh）
#   - .gitignore（排除 node_modules 等）
#
# 用法：在目标项目根目录执行
#   bash ~/.agents/skills/project-onboarding/templates/init-opencode-dir.sh
#
# 幂等：已存在的文件不会被覆盖
# =============================================================================

set -euo pipefail

OPENCODE_DIR=".opencode"

mkdir -p "$OPENCODE_DIR"

# ── settings.json（mempalace hook） ───────────────────────────────

SETTINGS_FILE="${OPENCODE_DIR}/settings.json"
if [ ! -f "$SETTINGS_FILE" ]; then
    # 调用专门的 hook 初始化脚本
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    if [ -f "${SCRIPT_DIR}/init-settings-hooks.sh" ]; then
        bash "${SCRIPT_DIR}/init-settings-hooks.sh"
    else
        # 回退：内联写完整的 mempalace 4 hook（与 init-settings-hooks.sh 一致）
        MEMPALACE_CMD=$(command -v mempalace 2>/dev/null || echo "mempalace")
        cat > "$SETTINGS_FILE" << SETTINGS_EOF
{
  "_comment": "Project-level mempalace hooks. graphify → <cwd>/.claude/settings.json. gitnexus → ~/.claude/settings.json. OPENCODE merges all.",
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
            "command": "command -v mempalace >/dev/null 2>&1 && [ -d \"\\\$HOME/.mempalace\" ] && echo '{\"hookSpecificOutput\":{\"hookEventName\":\"PreToolUse\",\"additionalContext\":\"[mempalace] Semantic memory available. Use mempalace_search MCP tool or mempalace search CLI for historical experience retrieval.\"}}' || true"
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
        echo "✅ ${SETTINGS_FILE} 创建完成（回退路径，4 个 mempalace hook）"
    fi
else
    echo "⏭️  ${SETTINGS_FILE} 已存在，跳过"
fi

# ── .gitignore ────────────────────────────────────────────────────

GITIGNORE_FILE="${OPENCODE_DIR}/.gitignore"
if [ ! -f "$GITIGNORE_FILE" ]; then
    cat > "$GITIGNORE_FILE" << 'EOF'
node_modules
package.json
package-lock.json
bun.lock
.gitignore
EOF
    echo "✅ ${GITIGNORE_FILE} 创建完成"
else
    echo "⏭️  ${GITIGNORE_FILE} 已存在，跳过"
fi

# ── 确保 .opencode/ 在项目 .gitignore 中 ─────────────────────────

if [ -f .gitignore ]; then
    grep -q "^\.opencode/$" .gitignore 2>/dev/null || echo ".opencode/" >> .gitignore
elif [ -d .git ]; then
    echo ".opencode/" > .gitignore
fi

echo ""
echo "✅ .opencode/ 目录初始化完成"
echo "   graphify hook → graphify claude install → <cwd>/.claude/settings.json"
echo "   gitnexus hook → gitnexus setup → ~/.claude/settings.json"
echo "   mempalace hook → 本脚本 → <cwd>/.opencode/settings.json"
echo "   OPENCODE settings 链自动合并三层"

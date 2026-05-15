#!/usr/bin/env bash
# =============================================================================
# install-opencode-tmux.sh — 环境自适应安装 opencode-tmux 自动包装器
#
# 目标：让 `opencode` 命令自动进入 tmux 会话
#   - 已有 opencode 会话 → attach 恢复
#   - 无会话 → 新建并运行
#   - 已在 tmux 内 → 直接执行真实二进制（避免嵌套）
#   - 进程退出后 → tmux 保留窗口显示输出（崩溃时尤其重要）
#
# 自适应能力：
#   1. 自动定位**真实** opencode 二进制（绕开自身 shim/function）
#   2. 检测 tmux 版本 ≥1.5 → set-option remain-on-exit on
#   3. 选择安装策略：
#        策略 A：PATH shim — 在 $HOME/.local/bin 写包装脚本
#                条件：$HOME/.local/bin 在 PATH 中且**优先级高于**真实 opencode 路径
#        策略 B：shell function — 在 ~/.bashrc / ~/.zshrc 注入 opencode() 函数
#                条件：策略 A 不满足时
#
# 用法：
#   bash install-opencode-tmux.sh           # 自动选择策略
#   FORCE_STRATEGY=shim bash <script>       # 强制 PATH shim
#   FORCE_STRATEGY=function bash <script>   # 强制 shell function
#   bash install-opencode-tmux.sh --uninstall
# =============================================================================

set -euo pipefail

WRAPPER_NAME="opencode"
SHIM_DIR="$HOME/.local/bin"
SHIM_PATH="$SHIM_DIR/$WRAPPER_NAME"
WRAPPER_LIB="$HOME/.local/share/opencode-tmux/wrapper.sh"
RC_FILES=()
[ -f "$HOME/.bashrc" ] && RC_FILES+=("$HOME/.bashrc")
[ -f "$HOME/.zshrc" ] && RC_FILES+=("$HOME/.zshrc")
MARKER_BEGIN="# >>> opencode-tmux auto-wrap (managed by install-opencode-tmux.sh) >>>"
MARKER_END="# <<< opencode-tmux auto-wrap <<<"

# ── 可选卸载 ──────────────────────────────────────────────────────
if [ "${1:-}" = "--uninstall" ]; then
    [ -L "$SHIM_PATH" ] && [ "$(readlink -f "$SHIM_PATH" 2>/dev/null)" = "$WRAPPER_LIB" ] && rm -f "$SHIM_PATH"
    [ -f "$SHIM_PATH" ] && head -1 "$SHIM_PATH" 2>/dev/null | grep -q "opencode-tmux" && rm -f "$SHIM_PATH"
    rm -f "$WRAPPER_LIB"
    for rc in "${RC_FILES[@]}"; do
        if grep -q "opencode-tmux auto-wrap" "$rc"; then
            sed -i.bak "/opencode-tmux auto-wrap (managed/,/opencode-tmux auto-wrap <<</d" "$rc"
            echo "🧹 已从 $rc 移除 shell function"
        fi
    done
    echo "✅ 已卸载 opencode-tmux 包装器"
    exit 0
fi

# ── Step 1 — 依赖检测 ─────────────────────────────────────────────
if ! command -v tmux &>/dev/null; then
    echo "❌ tmux 未安装。先执行：sudo apt-get install -y tmux  (或 brew install tmux)" >&2
    exit 1
fi

TMUX_VERSION=$(tmux -V 2>&1 | awk '{print $2}' | tr -d '[:alpha:]')
echo "ℹ️  tmux 版本：$TMUX_VERSION"

# remain-on-exit 自 1.5 起支持；进一步 ≥2.4 支持 'failed'
TMUX_MAJOR=$(echo "$TMUX_VERSION" | cut -d. -f1)
TMUX_MINOR=$(echo "$TMUX_VERSION" | cut -d. -f2 | tr -d '[:alpha:]')
TMUX_MINOR=${TMUX_MINOR:-0}
REMAIN_ON_EXIT="on"
if [ "$TMUX_MAJOR" -lt 1 ] || { [ "$TMUX_MAJOR" -eq 1 ] && [ "$TMUX_MINOR" -lt 5 ]; }; then
    echo "⚠️  tmux <1.5，不支持 remain-on-exit；崩溃画面将无法保留"
    REMAIN_ON_EXIT=""
fi

# ── Step 2 — 定位真实 opencode 二进制（绕开旧 shim/function） ────
RAW_OC=""
# 候选路径（按优先级）
CANDIDATES=(
    "/usr/local/bin/opencode"
    "/opt/homebrew/bin/opencode"
    "/usr/bin/opencode"
    "/opt/opencode/bin/opencode"
    "$HOME/.bun/bin/opencode"
    "$HOME/.npm-global/bin/opencode"
)
# 把 PATH 中所有可执行 opencode 加入候选（去重）
while IFS= read -r p; do
    [ -n "$p" ] && CANDIDATES+=("$p")
done < <(which -a opencode 2>/dev/null || true)

# 第一轮：跳过 SHIM_PATH，挑非冲突候选
for cand in "${CANDIDATES[@]}"; do
    [ -z "$cand" ] && continue
    [ "$cand" = "$SHIM_PATH" ] && continue            # 跳过我们自己 / 跳过将来要写入的 shim 位置
    [ ! -x "$cand" ] && continue
    if head -1 "$cand" 2>/dev/null | grep -q "opencode-tmux"; then continue; fi
    RAW_OC="$cand"
    break
done

# 第二轮：若没找到，但 SHIM_PATH 是真实 ELF（用户把 opencode 装在 ~/.local/bin），
# 就移到 backup 路径并用 backup 作为真实二进制
if [ -z "$RAW_OC" ] && [ -x "$SHIM_PATH" ] && ! head -1 "$SHIM_PATH" 2>/dev/null | grep -q "opencode-tmux"; then
    BACKUP_BIN="$HOME/.local/share/opencode-tmux/opencode-real"
    mkdir -p "$(dirname "$BACKUP_BIN")"
    if [ ! -f "$BACKUP_BIN" ] || ! cmp -s "$SHIM_PATH" "$BACKUP_BIN"; then
        cp -p "$SHIM_PATH" "$BACKUP_BIN"
        echo "🔄 检测到真实 opencode 位于将要写入 shim 的路径 ($SHIM_PATH)"
        echo "   已备份真实二进制到：$BACKUP_BIN"
    fi
    RAW_OC="$BACKUP_BIN"
fi

if [ -z "$RAW_OC" ]; then
    echo "❌ 找不到真实 opencode 二进制。请先安装 opencode 后再运行本脚本。" >&2
    echo "   可执行 'which -a opencode' 检查路径。" >&2
    exit 1
fi
echo "ℹ️  真实 opencode 二进制：$RAW_OC"

# ── Step 3 — 写 wrapper 主体（共享代码，shim 与 function 都引用） ─
mkdir -p "$(dirname "$WRAPPER_LIB")"
cat > "$WRAPPER_LIB" << WRAPPER_EOF
#!/usr/bin/env bash
# opencode-tmux wrapper — auto-managed; do not edit manually
# Generated $(date -u +%Y-%m-%dT%H:%M:%SZ)

OPENCODE_REAL_BIN="${RAW_OC}"
OPENCODE_TMUX_SESSION="\${OPENCODE_TMUX_SESSION:-opencode}"

# 紧急绕过
if [ "\${OPENCODE_NO_TMUX:-0}" = "1" ]; then
    exec "\$OPENCODE_REAL_BIN" "\$@"
fi

# 非交互命令（--version/--help 等）→ 直接透传，避免误进 detached tmux session 后瞬退
case "\${1:-}" in
    --version|-v|--help|-h|version|help)
        exec "\$OPENCODE_REAL_BIN" "\$@"
        ;;
esac

# 已在 tmux 内 → 不嵌套
if [ -n "\${TMUX:-}" ]; then
    exec "\$OPENCODE_REAL_BIN" "\$@"
fi

# tmux 不可用 → 透传
if ! command -v tmux >/dev/null 2>&1; then
    exec "\$OPENCODE_REAL_BIN" "\$@"
fi

# 已有同名会话 → attach
if tmux has-session -t "\$OPENCODE_TMUX_SESSION" 2>/dev/null; then
    exec tmux attach-session -t "\$OPENCODE_TMUX_SESSION"
fi

# 新建会话；构造命令
ESC_BIN=\$(printf '%q' "\$OPENCODE_REAL_BIN")
CMD="\$ESC_BIN"
for arg in "\$@"; do
    CMD="\$CMD \$(printf '%q' "\$arg")"
done

# 创建会话（detached）
tmux new-session -d -s "\$OPENCODE_TMUX_SESSION" "\$CMD"

# 保留崩溃画面（tmux ≥1.5）
WRAPPER_EOF

if [ -n "$REMAIN_ON_EXIT" ]; then
    cat >> "$WRAPPER_LIB" << WRAPPER_EOF
tmux set-option -t "\$OPENCODE_TMUX_SESSION" remain-on-exit ${REMAIN_ON_EXIT} 2>/dev/null || true
WRAPPER_EOF
fi

cat >> "$WRAPPER_LIB" << 'WRAPPER_EOF'
exec tmux attach-session -t "$OPENCODE_TMUX_SESSION"
WRAPPER_EOF

chmod +x "$WRAPPER_LIB"
echo "✅ Wrapper 已写入：$WRAPPER_LIB"

# ── Step 4 — 决定安装策略 ────────────────────────────────────────
STRATEGY="${FORCE_STRATEGY:-}"
if [ -z "$STRATEGY" ]; then
    # 检查 ~/.local/bin 是否在 PATH 中
    if echo ":$PATH:" | grep -q ":$SHIM_DIR:"; then
        # 进一步：~/.local/bin 是否在真实 opencode 路径之前
        REAL_DIR=$(dirname "$RAW_OC")
        SHIM_POS=$(echo "$PATH" | tr ':' '\n' | grep -n "^$SHIM_DIR\$" | head -1 | cut -d: -f1)
        REAL_POS=$(echo "$PATH" | tr ':' '\n' | grep -n "^$REAL_DIR\$" | head -1 | cut -d: -f1)
        if [ -n "$SHIM_POS" ] && [ -n "$REAL_POS" ] && [ "$SHIM_POS" -lt "$REAL_POS" ]; then
            STRATEGY="shim"
        elif [ -n "$SHIM_POS" ] && [ -z "$REAL_POS" ]; then
            STRATEGY="shim"
        else
            STRATEGY="function"
        fi
    else
        STRATEGY="function"
    fi
fi
echo "ℹ️  安装策略：$STRATEGY"

# ── Step 5a — PATH shim ──────────────────────────────────────────
install_shim() {
    mkdir -p "$SHIM_DIR"
    # 若 SHIM_PATH 已存在且不是我们自己（即真实 opencode 占住该路径），先备份
    if [ -e "$SHIM_PATH" ] && ! head -1 "$SHIM_PATH" 2>/dev/null | grep -q "opencode-tmux"; then
        # RAW_OC 已经是非 SHIM_PATH 的真实二进制；现在要把 SHIM_PATH 上的旧二进制移到备份
        local backup="$HOME/.local/share/opencode-tmux/opencode-shim-prev-$(date +%s)"
        mkdir -p "$(dirname "$backup")"
        # 用 mv 而非 cp+rm（避开 Text file busy）
        if mv "$SHIM_PATH" "$backup" 2>/dev/null; then
            echo "🔄 已将原 $SHIM_PATH 备份到 $backup"
        else
            echo "⚠️  无法移动 $SHIM_PATH（可能正在运行）。" >&2
            echo "   降级为 shell function 策略。" >&2
            STRATEGY="function"
            install_function
            return
        fi
    fi
    # 写到临时文件然后原子 mv，避免 Text file busy
    local tmp="${SHIM_PATH}.tmp.$$"
    cat > "$tmp" << SHIM_EOF
#!/usr/bin/env bash
# opencode-tmux PATH shim — auto-managed; do not edit
exec "$WRAPPER_LIB" "\$@"
SHIM_EOF
    chmod +x "$tmp"
    mv "$tmp" "$SHIM_PATH"
    echo "✅ PATH shim 已安装：$SHIM_PATH"
}

# ── Step 5b — Shell function ─────────────────────────────────────
install_function() {
    if [ ${#RC_FILES[@]} -eq 0 ]; then
        echo "❌ 找不到 ~/.bashrc 或 ~/.zshrc，且未启用 shim 策略。" >&2
        echo "   解决：FORCE_STRATEGY=shim bash $0   （需把 ~/.local/bin 加入 PATH）" >&2
        exit 1
    fi
    local block
    block="$MARKER_BEGIN
opencode() { command \"$WRAPPER_LIB\" \"\$@\"; }
$MARKER_END"

    for rc in "${RC_FILES[@]}"; do
        if grep -q "opencode-tmux auto-wrap" "$rc"; then
            # 替换旧 block
            sed -i.bak "/opencode-tmux auto-wrap (managed/,/opencode-tmux auto-wrap <<</d" "$rc"
        fi
        printf '\n%s\n' "$block" >> "$rc"
        echo "✅ shell function 已注入：$rc"
    done
    echo "ℹ️  请执行 'source $rc' 或重开终端使函数生效"
}

case "$STRATEGY" in
    shim)     install_shim ;;
    function) install_function ;;
    *)        echo "❌ 未知策略 $STRATEGY" >&2; exit 1 ;;
esac

# ── Step 6 — 验证 ────────────────────────────────────────────────
echo ""
echo "=== 验证 ==="
echo "tmux 版本     : $TMUX_VERSION (remain-on-exit: ${REMAIN_ON_EXIT:-不支持})"
echo "真实 opencode : $RAW_OC"
echo "Wrapper       : $WRAPPER_LIB"
echo "策略          : $STRATEGY"
if [ "$STRATEGY" = "shim" ]; then
    echo "Shim          : $SHIM_PATH"
    echo ""
    echo "测试：which -a opencode  应将 $SHIM_PATH 排在前面"
fi
echo ""
echo "✨ 安装完成。下次执行 'opencode' 将自动进入 tmux 会话。"
echo "   多项目并行：OPENCODE_TMUX_SESSION=proj-a opencode"
echo "   紧急绕过： OPENCODE_NO_TMUX=1 opencode"
echo "   查看会话： tmux ls"
echo "   销毁会话： tmux kill-session -t opencode"
echo "   卸载：     bash $0 --uninstall"

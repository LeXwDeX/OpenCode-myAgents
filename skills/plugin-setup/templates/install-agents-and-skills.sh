#!/usr/bin/env bash
# install-agents-and-skills.sh
# ----------------------------------------------------------------------------
# 把本仓自带的 OPENCODE 专属 agents 与配套 skills 部署到本机全局位置。
#
# 部署矩阵：
#   agents_multi-orchestration/agents/*.md  →  ~/.config/opencode/agents/
#   agents_multi-orchestration/skills/*     →  ~/.agents/skills/
#
# 行为：
#   - 幂等：可重复执行，rsync 仅传输有差异的文件
#   - 安全：覆盖前先把已存在的目标备份为 <file>.bak.<unix-ts>
#   - 跳过：源中名为 no_permission / old_agents 的子目录
#   - 干跑：传 -n 仅打印将要做的事，不真改动
#   - 跨平台：Linux/macOS/WSL/Git-Bash 通用，依赖 rsync + bash
#
# 用法：
#   bash install-agents-and-skills.sh        # 实跑
#   bash install-agents-and-skills.sh -n     # 干跑预览
#
# 退出码：0=OK；1=源目录定位失败；2=rsync 缺失
# ----------------------------------------------------------------------------

set -euo pipefail

DRY_RUN=0
if [ "${1:-}" = "-n" ] || [ "${1:-}" = "--dry-run" ]; then
  DRY_RUN=1
  echo "[DRY-RUN] 仅打印动作，不真实修改文件"
fi

# 依赖检测
if ! command -v rsync >/dev/null 2>&1; then
  echo "ERROR: rsync 未安装。Debian/Ubuntu: apt-get install -y rsync ; macOS: brew install rsync" >&2
  exit 2
fi

# 定位仓内源目录：脚本位置在
#   <repo>/agents_multi-orchestration/skills/plugin-setup/templates/install-agents-and-skills.sh
# 或部署后位置：
#   ~/.agents/skills/plugin-setup/templates/install-agents-and-skills.sh
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_SETUP_DIR="$(dirname "$SCRIPT_DIR")"      # .../skills/plugin-setup
SKILLS_PARENT_DIR="$(dirname "$PLUGIN_SETUP_DIR")"  # .../skills

# 源 agents：与 skills 父级同级的 agents 目录（仓内布局）
# 仓内：agents_multi-orchestration/{agents,skills}/
# 部署后：~/.agents/skills/ 下没有 agents 兄弟——这种情况下不能从已部署位置反向部署 agents
AGENTS_PARENT_DIR="$(dirname "$SKILLS_PARENT_DIR")"  # 仓内 = .../agents_multi-orchestration ; 部署后 = ~/.agents
SRC_AGENTS_DIR="$AGENTS_PARENT_DIR/agents"
SRC_SKILLS_DIR="$SKILLS_PARENT_DIR"

if [ ! -d "$SRC_AGENTS_DIR" ] || ! ls "$SRC_AGENTS_DIR"/*.md >/dev/null 2>&1; then
  echo "ERROR: 找不到本仓 agents 源目录：$SRC_AGENTS_DIR" >&2
  echo "       期望布局：<repo>/agents_multi-orchestration/agents/{main,explore,implement,verify,patcher}.md" >&2
  echo "       提示：从仓内 plugin-setup/templates/ 调用本脚本，而不是部署后的 ~/.agents/skills/plugin-setup/templates/" >&2
  exit 1
fi
if [ ! -d "$SRC_SKILLS_DIR" ]; then
  echo "ERROR: 找不到本仓 skills 源目录：$SRC_SKILLS_DIR" >&2
  exit 1
fi

DEST_AGENTS_DIR="$HOME/.config/opencode/agents"
DEST_SKILLS_DIR="$HOME/.agents/skills"
mkdir -p "$DEST_AGENTS_DIR" "$DEST_SKILLS_DIR"

TS="$(date +%s)"
backup_if_exists() {
  local target="$1"
  if [ -e "$target" ] && [ ! -L "$target" ]; then
    if [ "$DRY_RUN" -eq 1 ]; then
      echo "  [DRY] 备份 $target → $target.bak.$TS"
    else
      cp -a "$target" "$target.bak.$TS"
      echo "  备份 $target → $target.bak.$TS"
    fi
  fi
}

echo "========================================"
echo "源 agents:  $SRC_AGENTS_DIR"
echo "源 skills:  $SRC_SKILLS_DIR"
echo "目标 agents: $DEST_AGENTS_DIR"
echo "目标 skills: $DEST_SKILLS_DIR"
echo "========================================"

# ---- 部署 agents ----
echo
echo "[1/2] 部署 agents → $DEST_AGENTS_DIR"
shopt -s nullglob
for src in "$SRC_AGENTS_DIR"/*.md; do
  name="$(basename "$src")"
  dest="$DEST_AGENTS_DIR/$name"
  if [ -f "$dest" ] && cmp -s "$src" "$dest"; then
    echo "  跳过 $name（与目标完全一致）"
    continue
  fi
  backup_if_exists "$dest"
  if [ "$DRY_RUN" -eq 1 ]; then
    echo "  [DRY] cp $src → $dest"
  else
    cp -a "$src" "$dest"
    echo "  部署 $name"
  fi
done

# ---- 部署 skills ----
echo
echo "[2/2] 部署 skills → $DEST_SKILLS_DIR"
RSYNC_FLAGS=(-a --delete-after --exclude='node_modules' --exclude='.git')
if [ "$DRY_RUN" -eq 1 ]; then
  RSYNC_FLAGS+=(-n -v)
fi

for src_skill in "$SRC_SKILLS_DIR"/*/; do
  skill_name="$(basename "$src_skill")"
  case "$skill_name" in
    no_permission|old_agents) echo "  跳过保留目录 $skill_name"; continue ;;
  esac
  dest_skill="$DEST_SKILLS_DIR/$skill_name"
  # 备份策略：整个 skill 目录已存在就 tar 一份
  if [ -d "$dest_skill" ]; then
    if [ "$DRY_RUN" -eq 1 ]; then
      echo "  [DRY] 备份 $dest_skill → $dest_skill.bak.$TS (tar)"
    else
      # 用 cp -a 做整目录备份；rsync --delete-after 后已部署目录会被同步成源的样子
      cp -a "$dest_skill" "$dest_skill.bak.$TS"
      echo "  备份 $dest_skill → $dest_skill.bak.$TS"
    fi
  fi
  echo "  rsync $skill_name/"
  rsync "${RSYNC_FLAGS[@]}" "$src_skill" "$dest_skill/"
done

# 给所有 templates 下的 .sh 加可执行权限
if [ "$DRY_RUN" -eq 0 ]; then
  find "$DEST_SKILLS_DIR" -path '*/templates/*.sh' -exec chmod +x {} \; 2>/dev/null || true
fi

# 检测残留双写
if [ -d "$HOME/.config/opencode/skills" ]; then
  echo
  echo "提示：检测到 ~/.config/opencode/skills/ 目录存在（fork 也会扫此处）"
  echo "      本脚本只写 ~/.agents/skills/ 单点；如需清理双写残留，由用户自行判断："
  ls "$HOME/.config/opencode/skills/" 2>/dev/null | sed 's/^/        /'
fi

echo
echo "✅ Done. 干跑模式：$DRY_RUN"
echo "下一步：进入任意项目，触发 project-onboarding skill"

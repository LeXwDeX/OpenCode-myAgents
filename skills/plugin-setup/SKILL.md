---
name: plugin-setup
description: 把 graphify / mempalace / GitNexus / DCP / tmux 等插件的二进制安装到本机系统（Linux/macOS/Windows-WSL），并把 project-onboarding skill 部署到全局 `~/.agents/skills/`。**仅负责安装，不做任何插件初始化或 Hook 配置**。当用户说"装插件"、"装 graphify/mempalace/gitnexus"、"配置本机 OPENCODE 环境"、"在新机器上准备 opencode 生态"时触发。
---

# Plugin Setup — 系统级插件安装器

> **职责边界（必须严格遵守）**
>
> | 本 skill (`plugin-setup`) | 兄弟 skill (`project-onboarding`) |
> |---|---|
> | **系统级**：把工具二进制装到本机 PATH | **项目级**：在某个项目内调用工具、写 hook、建索引、部署插件 skill |
> | pipx / npm / curl 安装 CLI | `gitnexus setup`、`graphify claude install`、skill 拷贝到 `<project>/.agents/skills/` |
> | 部署 tmux 包装器到 `~/.local/bin/` | 写 `<project>/.opencode/settings.json` hook |
> | **把 project-onboarding skill 复制到 `~/.agents/skills/`** | 创建 `.memory/` `.codex_plan/` `.gitnexus/` `graphify-out/` |
> | 一次安装，全机生效 | 每个新项目执行一次 |
>
> 本 skill **不**调用 `gitnexus setup`、**不**写任何 settings.json、**不**注册 hook、**不**碰项目目录。这些都属于 `project-onboarding`。

---

## 触发场景
- 新机器首次准备 OPENCODE 生态
- 用户说"装插件"、"装 graphify/mempalace/gitnexus/DCP"、"装 tmux 包装"
- 升级插件版本
- `project-onboarding` 在 Step 1 检测到工具缺失，回头建议执行本 skill

## 不触发的场景
- 用户在某个项目里说"初始化"、"接入项目" → 走 `project-onboarding`
- 用户说"配置 hook"、"启用 mempalace 项目记忆" → 走 `project-onboarding`

---

## 在线 / 离线模式
**默认在线**（pipx / npm / uvx / bunx 直连官方源）。仅当用户明确说"离线"、"无网络"、"air-gap"时切换到离线模式（详见末尾 § 离线模式）。

---

## Step 1 — 前置依赖检测

```bash
command -v pipx &>/dev/null && echo "pipx: OK" || echo "pipx: MISSING"
command -v npm  &>/dev/null && echo "npm: OK"  || echo "npm: MISSING"
command -v uvx  &>/dev/null && echo "uvx: OK"  || echo "uvx: MISSING"
command -v bunx &>/dev/null && echo "bunx: OK" || echo "bunx: MISSING"
command -v jq   &>/dev/null && echo "jq: OK"   || echo "jq: MISSING"
command -v tmux &>/dev/null && echo "tmux: OK ($(tmux -V))" || echo "tmux: MISSING"
```

缺失则按需安装：

```bash
python3 -m pip install --user pipx && python3 -m pipx ensurepath
curl -LsSf https://astral.sh/uv/install.sh | sh        # 提供 uv/uvx
curl -fsSL https://bun.sh/install | bash               # 提供 bun/bunx
# Debian/Ubuntu
sudo apt-get update && sudo apt-get install -y tmux jq
# macOS
brew install tmux jq
```

> 不要尝试装 nvm/node — npm 通常已随 Node 安装。本 skill 不为缺失 Node 的环境兜底，让用户自行安装。

---

## Step 2 — 安装 graphify CLI

```bash
pipx install graphifyy   # 注意包名是 graphifyy（双 y）
# 验证（无 --version 子命令）
command -v graphify &>/dev/null && graphify --help 2>&1 | grep -q "graphify <command>" \
  && echo "graphify: INSTALLED" || echo "graphify: FAILED"
```

> ⚠️ **不执行任何 `graphify install` / `graphify claude install` / `graphify opencode install`**。
> graphify 的 skill 文件和 hook 都由 `project-onboarding` 在项目级部署（`<project>/.agents/skills/graphify/`）。
> 本 skill 只装 CLI 二进制。

---

## Step 3 — 安装 mempalace CLI

```bash
pipx install mempalace
mempalace --version && echo "mempalace: INSTALLED" || echo "mempalace: FAILED"
```

ChromaDB ONNX 模型在首次运行 mempalace 时自动下载到 `~/.cache/chroma/onnx_models/`，无需预装。

> ⚠️ **本 skill 不写** mempalace hook 到任何 settings.json。hook 注册由 `project-onboarding` 在每个项目内通过 `templates/init-settings-hooks.sh` 完成。

---

## Step 4 — 安装 GitNexus CLI

```bash
npm install -g gitnexus     # 官方推荐 npm，不用 bun
gitnexus --version 2>&1 | head -1 && echo "gitnexus: INSTALLED" || echo "gitnexus: FAILED"
```

> ⚠️ **本 skill 不执行** `gitnexus setup`。该命令会写 `~/.claude/settings.json` + 部署 hook 脚本 + 注册 MCP，属于"插件初始化"工作，由 `project-onboarding` 在首次接入任何项目时执行一次（全局生效）。

---

## Step 5 — 安装 OPENCODE DCP 插件

```bash
opencode plugin @tarquinen/opencode-dcp@latest --global
grep -q "opencode-dcp" "$HOME/.config/opencode/opencode.json" && echo "DCP: REGISTERED" || echo "DCP: MISSING"
```

DCP 配置文件优先级：项目 `.opencode/dcp.jsonc` > 全局 `~/.config/opencode/dcp.jsonc`（首次运行自动创建）。

---

## Step 5b — 安装 RTK CLI（命令输出压缩器）

RTK 是 PreToolUse hook 改写型工具：把 `git status` / `ls -l` 等冗长命令改写为 `rtk git status` 紧凑输出，给 LLM 省 token。**本 skill 只装二进制**，hook 注册 / `~/.claude/` 配置由 `project-onboarding` 完成。

```bash
# 在线主路径（走 GitHub raw，无法走 npm/pip/apt 内网镜像）
curl -fsSL https://raw.githubusercontent.com/rtk-ai/rtk/refs/heads/master/install.sh | sh

# 验证
command -v rtk >/dev/null && rtk --version && echo "rtk: INSTALLED" || echo "rtk: FAILED"
# 改写自检（应输出 `rtk git status`，证明二进制 + 内置规则就位）
rtk rewrite "git status" 2>/dev/null | grep -q "^rtk git status$" \
  && echo "rtk rewrite: OK" || echo "rtk rewrite: FAILED"
```

降级路径（在线 install.sh 失败时）：

```bash
# 1) cargo 源码构建（需 rust 工具链）
cargo install --git https://github.com/rtk-ai/rtk --locked

# 2) 手动下 release tarball
# https://github.com/rtk-ai/rtk/releases → rtk-x86_64-unknown-linux-musl.tar.gz
# 解包后 install -m755 rtk /root/.local/bin/rtk
```

> ⚠️ **本 skill 不执行** `rtk init -g` / 不写 `~/.claude/settings.json` / 不注入 `RTK.md` 到 `CLAUDE.md`。这些由 `project-onboarding` 在首次接入项目时全局执行一次。
> ⚠️ RTK **全走 GitHub**（install.sh + release + cargo --git），不走 npm/pip/apt；内网镜像代理对它无效，离线场景见末尾 § 离线模式。

---

## Step 6 — 安装 tmux 自动包装器（系统级、环境感知）

让用户直接执行 `opencode` 即自动进入 tmux 会话（可恢复、可销毁、保留崩溃输出）。

```bash
bash "$(dirname "$0")/templates/install-opencode-tmux.sh"
# 或从全局位置调用：
# bash "$HOME/.agents/skills/plugin-setup/templates/install-opencode-tmux.sh"
```

脚本会**根据本机环境自适应**：
- 自动定位真实 opencode 二进制（跳过 shim）
- 检测 `$HOME/.local/bin` 在 PATH 的位置 → 选 PATH-shim 还是 `~/.bashrc` shell-function
- tmux ≥ 1.5 启用 `remain-on-exit on`（保留崩溃画面）
- 原子 `mv` 避免 Text-file-busy
- 备份冲突文件到 `~/.local/share/opencode-tmux/`

卸载：`bash templates/install-opencode-tmux.sh --uninstall`

---

## Step 7 — 部署 `project-onboarding` skill 到全局

> **这是本 skill 的关键交付物**：把 project-onboarding 装到全局 skills 目录，让用户在**任意其它项目**里都能触发它。

```bash
SRC="$(cd "$(dirname "$0")" && pwd)/../project-onboarding"   # 项目内同级目录
DEST="$HOME/.agents/skills/project-onboarding"

# 兜底：如果本 skill 是从 ~/.agents/skills/plugin-setup 调用的，源同样在 ~/.agents/skills/
[ -d "$SRC" ] || SRC="$HOME/.agents/skills/project-onboarding"

mkdir -p "$HOME/.agents/skills"
# 备份用户已有版本
[ -d "$DEST" ] && cp -r "$DEST" "$DEST.bak.$(date +%s)" && echo "已备份旧版本"
rm -rf "$DEST"
cp -r "$SRC" "$DEST"
chmod +x "$DEST/templates/"*.sh 2>/dev/null || true
echo "project-onboarding deployed → $DEST"
```

**Windows（PowerShell / Git Bash）等价**：
```powershell
$dest = "$HOME\.agents\skills\project-onboarding"
if (Test-Path $dest) { Move-Item $dest "$dest.bak.$(Get-Date -UFormat %s)" }
Copy-Item -Recurse "$PSScriptRoot\..\project-onboarding" $dest
```

> `~/.agents/skills/` 是**唯一**全局 skill 目录。不再向 `~/.config/opencode/skills/` 部署——OPENCODE fork 已配置为从 `~/.agents/skills/` 读取。

---

## Step 8 — 配置基础 MCP 服务（仅注册，**不**写 hook）

仅向 `~/.config/opencode/opencode.json` 的 `mcp` 节追加 mempalace MCP（gitnexus MCP 由 `project-onboarding` 触发的 `gitnexus setup` 自动注册，本 skill 不碰）：

```bash
# 检测，不存在则提示用户手动加入（避免破坏用户已有 mcp 配置）
grep -q '"mempalace"' "$HOME/.config/opencode/opencode.json" 2>/dev/null \
  && echo "mempalace MCP: 已注册" \
  || echo "mempalace MCP: 未注册，请在 ~/.config/opencode/opencode.json 的 mcp 节追加："
```

待追加的 JSON 片段（在线模式默认）：
```json
"mempalace": {
  "type": "local",
  "command": ["uvx", "--from", "mempalace", "mempalace-mcp"],
  "enabled": true
}
```

> 本步骤是**唯一**写到全局 OPENCODE 配置的动作，且仅追加 MCP 条目，不动 provider/key/hook。

---

## Step 9 — 验证

```bash
echo "=== 工具二进制 ==="
command -v graphify  >/dev/null && echo "graphify: OK"  || echo "graphify: MISSING"
mempalace --version  2>/dev/null && echo "mempalace: OK" || echo "mempalace: MISSING"
gitnexus --version   2>/dev/null && echo "gitnexus: OK"  || echo "gitnexus: MISSING"
rtk --version        2>/dev/null && echo "rtk: OK"       || echo "rtk: MISSING"
command -v tmux      >/dev/null && echo "tmux: OK"      || echo "tmux: MISSING"

echo "=== DCP plugin ==="
grep -q "opencode-dcp" "$HOME/.config/opencode/opencode.json" && echo "DCP: OK"

echo "=== tmux 包装 ==="
which opencode && readlink -f "$(which opencode)"

echo "=== project-onboarding 全局可用 ==="
[ -f "$HOME/.agents/skills/project-onboarding/SKILL.md" ] && echo "project-onboarding: OK" || echo "project-onboarding: MISSING"
```

---

## 输出格式（安装报告）

```
## 系统级插件安装报告

| 组件 | 状态 | 版本 |
|---|---|---|
| graphify (pipx)            | ✅/❌ | x.y.z |
| mempalace (pipx)           | ✅/❌ | x.y.z |
| gitnexus (npm)             | ✅/❌ | x.y.z |
| rtk (curl install.sh)      | ✅/❌ | x.y.z |
| DCP plugin (opencode)      | ✅/❌ | x.y.z |
| tmux + 自动包装             | ✅/❌ | x.y |
| mempalace MCP 注册          | ✅/❌ | — |
| project-onboarding 全局部署 | ✅/❌ | — |

### 下一步（用户操作）
进入任意项目目录，触发 `project-onboarding` skill：
- 它会在该项目内调用 gitnexus setup（首次全局执行一次）
- graphify claude install（每个项目一次，写项目级 .claude/settings.json PreToolUse hook + CLAUDE.md）
- 写 .opencode/settings.json 的 mempalace hook
- 创建 .memory/ / .codex_plan/ 等
```

---

## 注意事项（铁律）

- **本 skill 绝不**：写任何 settings.json hook；调用 `gitnexus setup`、`graphify claude install`、`graphify install --platform *`、`graphify opencode install`、`gitnexus analyze`、`mempalace mine`；创建 `.memory/` / `.codex_plan/`；进入任何用户项目目录；向 `~/.claude/skills/` / `~/.config/opencode/skills/` 安装 skill 文件。
- **本 skill 只做**：装 CLI 二进制；装 tmux 包装；把 project-onboarding skill 部署到 `~/.agents/skills/`；追加一条 mempalace MCP。
- **Skill 唯一全局目录**：`~/.agents/skills/`。不向 `~/.config/opencode/skills/`、`~/.claude/skills/` 或任何其它位置写入 skill 文件。
- **跨平台**：Linux/macOS/WSL 走 bash 路径；Windows 原生用 PowerShell 等价命令（pipx / npm 同样跨平台）。
- 若 `~/.agents/skills/` 不存在，新建即可；不要为了"风格统一"硬把 project-onboarding 放到 `~/.config/opencode/skills/`——遵守 OPENCODE/Claude Code 的 skills.sh 全局规范，`~/.agents/skills/` 是首选位置。

---

## 升级插件

```bash
pipx upgrade graphifyy
pipx upgrade mempalace
npm update -g gitnexus
curl -fsSL https://raw.githubusercontent.com/rtk-ai/rtk/refs/heads/master/install.sh | sh   # rtk 自更新
opencode plugin @tarquinen/opencode-dcp@latest --global
# project-onboarding 升级 = 重新执行 Step 7
```

---

## ⚠️ 离线模式附加操作

> 默认无需。仅当用户声明"离线"、"无网络"、"air-gap"时执行。

### 1. mempalace MCP 改为本地二进制
```jsonc
"command": ["/root/.local/bin/mempalace-mcp"]   // 替换 uvx
```

### 2. DCP plugin 字段固定版本
```jsonc
"plugin": ["@tarquinen/opencode-dcp@3.1.9"]    // 不要 @latest
```

### 3. RTK 离线安装

RTK 不经 npm/pip/apt，**内网镜像无法代理**。离线机器需预先在联网机下载 release tarball：

```bash
# 联网机：https://github.com/rtk-ai/rtk/releases 下 rtk-x86_64-unknown-linux-musl.tar.gz
# 离线机：
tar -xzf rtk-x86_64-unknown-linux-musl.tar.gz
install -m755 rtk /root/.local/bin/rtk   # 或 /usr/local/bin/
rtk --version
```

参考第一步 opencode 的离线方案（仓根 `packages/` 模式）：可把 rtk 二进制与 SHA256 一同纳入仓内分发。

### 4. bun 全局原生模块手动链接
```bash
find "$HOME/.bun/install/global/node_modules" -name "*.node"
# 缺失则手动 cp 到对应包目录
```

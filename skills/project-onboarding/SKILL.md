---
name: project-onboarding
description: 三步流水线的第三步——在项目内完成插件初始化并验证 hook 协同。前置：plugin-setup 已完成。流程：检查 CLI → 执行官方安装 → 验证结果。当用户说"接入项目"、"启用插件"、"配置 hook"、"验证插件协同"时触发。
---

# project-onboarding — 项目级插件初始化

## 核心原则

> **opencode fork 完全兼容 Claude Code settings.json 协议。插件直接走 claude 模式安装，不搞特殊路径。**

OPENCODE fork 自动合并 6 层 settings（`~/.claude/`、`~/.config/opencode/`、`<cwd>/.claude/`、`<cwd>/.opencode/` + `.local`），所有 claude 模式的安装产物 fork 直接识别。

---

## 三步流水线定位

| 步 | 职责 | 触发 |
|---|---|---|
| ① 装 fork OPENCODE | GitHub/本地包装 fork | 仓根 `AGENTS.md` |
| ② 装 CLI + 组件 + agents + skills | 9/9 自检全绿 | `plugin-setup` SKILL |
| ③ **项目内初始化 + 协同验证** | **本 skill** | 用户说"接入项目" |

---

## Phase 1 — 基础检查

确认 CLI 工具全部就位，否则先回第二步：

```bash
TOOLS=(graphify gitnexus mempalace rtk opencode)
for t in "${TOOLS[@]}"; do
  command -v "$t" >/dev/null 2>&1 \
    && echo "✅ $t $(command -v $t)" \
    || { echo "❌ $t MISSING — 先跑 plugin-setup"; exit 1; }
done
```

---

## Phase 2 — 执行官方安装

### 2.1 graphify（项目级，每个项目跑一次）

```bash
graphify claude install
```

| 产物 | 位置 |
|---|---|
| CLAUDE.md graphify 段 | `<cwd>/CLAUDE.md` |
| PreToolUse Bash hook | `<cwd>/.claude/settings.json` |

> ℹ️ `graphify claude install` 是项目级 hook 安装器。全局 skill 安装（`graphify install --platform claude` → `~/.claude/skills/graphify/`）在第二步 plugin-setup 完成。两者互不替代。

幂等：重复执行输出 `already registered`。

### 2.2 gitnexus（全局，首次跑一次）

```bash
npx gitnexus setup
```

交互式选 **Claude Code**（fork 兼容），自动写入：

| 产物 | 位置 |
|---|---|
| PreToolUse hook (Grep/Glob/Bash) | `~/.claude/settings.json` |
| PostToolUse hook (Bash) | `~/.claude/settings.json` |
| hook 脚本 | `~/.claude/hooks/gitnexus/` |
| 7 个 gitnexus skill | `~/.claude/skills/gitnexus-*/` |

全局一次即永久生效，后续新项目无需重复。

### 2.3 rtk（全局，首次跑一次）

RTK 是 PreToolUse Bash 改写型 hook：把 `git status` / `ls -l` 等命令改写为 `rtk ...` 紧凑输出。**全局执行一次**即对所有项目生效，不每个项目跑。

> 前置：`plugin-setup` Step 4.5 已装 rtk 二进制（`rtk --version` 可执行）。本 skill 只负责注册项目级 hook，不再装二进制。

```bash
# 备份现有全局 settings 与 CLAUDE.md（rtk 自带 .bak，这里再加一份带 -rtk 后缀防丢）
[ -f ~/.claude/settings.json ] && cp ~/.claude/settings.json ~/.claude/settings.json.bak-rtk
[ -f ~/.claude/CLAUDE.md ]     && cp ~/.claude/CLAUDE.md     ~/.claude/CLAUDE.md.bak-rtk

# 全局初始化（hook 模式 + 自动 patch settings.json）
rtk init -g --auto-patch

# 卸掉可能存在的 opencode plugin 模式，避免与 hook 双重 rewrite
rm -f ~/.config/opencode/plugins/rtk.ts
```

| 产物 | 位置 |
|---|---|
| PreToolUse Bash hook → `rtk hook claude` | `~/.claude/settings.json`（合并，**不**覆盖 gitnexus） |
| LLM 紧凑输出指南 | `~/.claude/RTK.md` |
| CLAUDE.md 末尾追加 `@RTK.md` | `~/.claude/CLAUDE.md` |
| 用户级过滤模板 | `~/.config/rtk/filters.toml` |

> ⚠️ **顺序敏感**：`~/.claude/settings.json` 的 PreToolUse(Bash) 数组中，gitnexus（注入型）必须在 rtk（改写型）**之前**。`rtk init -g --auto-patch` 默认追加到数组尾部，与现有 gitnexus 顺序天然正确；若手动调整过 hook，跑下面 5 项验证确认。

**验证：5 项全绿**

```bash
rtk init --show
# 期望：
#  ✅ hook 已注册 (~/.claude/settings.json)
#  ✅ RTK.md 已写入 (~/.claude/RTK.md)
#  ✅ CLAUDE.md 已注入 @RTK.md
#  ✅ filters.toml 已创建 (~/.config/rtk/filters.toml)
#  ✅ rtk 二进制可调用
```

**重启 opencode 后实测**：

```bash
git status   # 期望紧凑格式：* main...origin/main / ~ Modified / ? Untracked
rtk gain     # 期望看到 rtk git status 节省 token 统计
```

不开遥测：默认即关；强制硬关 `export RTK_TELEMETRY_DISABLED=1`。

幂等：重复 `rtk init -g --auto-patch` 不会重复追加 hook，不破坏 gitnexus。
卸载：`rtk init -g --uninstall` 用 `~/.claude/settings.json.bak` 自动恢复。

### 2.4 mempalace（项目级初始化 + hook 注册）

mempalace 没有 `claude install` 子命令，分两步：

**① 初始化 palace**

```bash
mempalace init .
```

首次会自动下载 ONNX embedding 模型到 `~/.cache/chroma/onnx_models/`（需联网）。

**② 注册 hook**

```bash
bash "$HOME/.agents/skills/project-onboarding/templates/init-settings-hooks.sh"
```

写入 `<cwd>/.opencode/settings.json`：

| Hook 事件 | 命令 | 用途 |
|---|---|---|
| SessionStart | `mempalace hook run --hook session-start --harness claude-code` | 会话开始加载记忆 |
| Stop | `mempalace hook run --hook stop --harness claude-code` | 每 15 条自动存档 |
| PreCompact | `mempalace hook run --hook precompact --harness claude-code` | 上下文压缩前紧急存档 |
| PreToolUse | 检测 mempalace 可用性返回提示 | Glob/Grep/Read 时提醒语义检索 |

**③ 可选：挖掘现有项目物料**

```bash
mempalace mine . 2>/dev/null || true
```

---

## Phase 3 — 验证结果

### 3.1 文件检查

逐项确认安装产物存在：

```bash
echo "=== graphify ==="
[ -f ".claude/settings.json" ] && grep -q "graphify\|graph.json" .claude/settings.json \
  && echo "✅ .claude/settings.json 含 graphify hook" \
  || echo "❌ graphify hook 未注册"

echo "=== gitnexus ==="
[ -f "$HOME/.claude/settings.json" ] && grep -q "gitnexus" "$HOME/.claude/settings.json" \
  && echo "✅ ~/.claude/settings.json 含 gitnexus hook" \
  || echo "❌ gitnexus hook 未注册"
[ -d "$HOME/.claude/hooks/gitnexus" ] \
  && echo "✅ ~/.claude/hooks/gitnexus/ 存在" \
  || echo "❌ gitnexus hook 脚本目录不存在"

echo "=== rtk ==="
[ -f "$HOME/.claude/settings.json" ] && grep -q "rtk hook claude" "$HOME/.claude/settings.json" \
  && echo "✅ ~/.claude/settings.json 含 rtk hook" \
  || echo "❌ rtk hook 未注册"
[ -f "$HOME/.claude/RTK.md" ] \
  && echo "✅ ~/.claude/RTK.md 存在" \
  || echo "❌ RTK.md 未写入"
grep -q "@RTK.md" "$HOME/.claude/CLAUDE.md" 2>/dev/null \
  && echo "✅ CLAUDE.md 已注入 @RTK.md" \
  || echo "❌ CLAUDE.md 未注入 @RTK.md"
# 顺序：gitnexus 必须在 rtk 之前（注入 → 改写）
# settings.json 中 PreToolUse 是多 entry 数组（gitnexus matcher="Grep|Glob|Bash" 与
# rtk matcher="Bash" 是两条独立 entry），必须跨 entry 扁平化命令列表后再判索引。
python3 - <<'PY'
import json, os
s = json.load(open(os.path.expanduser('~/.claude/settings.json')))
pre = s.get('hooks', {}).get('PreToolUse', [])
cmds = []
for entry in pre:
    if 'Bash' in str(entry.get('matcher', '')):
        for h in entry.get('hooks', []):
            cmds.append(h.get('command', ''))
gi = next((i for i, c in enumerate(cmds) if 'gitnexus' in c), -1)
ri = next((i for i, c in enumerate(cmds) if 'rtk hook claude' in c), -1)
if ri == -1:
    print('⚠️  rtk hook 未注册（跑 `rtk init -g --auto-patch`）')
elif gi == -1:
    print('⚠️  gitnexus hook 未注册（跑 `npx gitnexus setup`）')
elif gi < ri:
    print('✅ gitnexus→rtk 顺序正确')
else:
    print('❌ hook 顺序错误：gitnexus(注入) 必须在 rtk(改写) 之前')
PY

echo "=== mempalace ==="
[ -f ".opencode/settings.json" ] && grep -q "mempalace\|hook run" .opencode/settings.json \
  && echo "✅ .opencode/settings.json 含 mempalace hook" \
  || echo "❌ mempalace hook 未注册"
```

### 3.2 Hook 可执行性验证

逐个触发 hook 确认 EXIT 0：

```bash
# graphify
echo '{"tool_input":{"command":"grep test ."}}' | bash -c '
  [ -f graphify-out/graph.json ] && echo "graphify: graph exists" || echo "graphify: no graph yet (正常，需先 /graphify .)"
'; echo "graphify EXIT: $?"

# gitnexus
echo '{"tool_name":"Grep","tool_input":{"pattern":"test"}}' \
  | node "$HOME/.claude/hooks/gitnexus/gitnexus-hook.cjs" 2>/dev/null
echo "gitnexus EXIT: $?"

# rtk（改写型，stdin 给一个 Bash PreToolUse 事件，期望 stdout 是 JSON {hookSpecificOutput:{updatedInput:{command:"rtk git status"}}}）
echo '{"tool_name":"Bash","tool_input":{"command":"git status"}}' \
  | rtk hook claude 2>/dev/null | grep -q '"rtk git status"' \
  && echo "rtk rewrite EXIT: 0" || echo "rtk rewrite: 改写失败"

# mempalace (3 endpoints)
for h in session-start stop precompact; do
  mempalace hook run --hook "$h" --harness claude-code 2>/dev/null
  echo "mempalace $h EXIT: $?"
done
```

### 3.3 settings 链加载验证

```bash
opencode --help 2>&1 | head -5
echo "opencode EXIT: $?"
```

成功标准：opencode 正常启动（EXIT 0），三层 settings 被加载：

| settings 文件 | 来源 | 包含 |
|---|---|---|
| `~/.claude/settings.json` | `gitnexus setup` + `rtk init -g` | PreToolUse (gitnexus 注入 → rtk 改写) + PostToolUse |
| `<cwd>/.claude/settings.json` | `graphify claude install` | PreToolUse Bash matcher |
| `<cwd>/.opencode/settings.json` | `init-settings-hooks.sh` | mempalace 4 hook |

加 `OPENCODE_LOG=debug opencode --help` 可看详细加载日志。

---

## 故障排查

| 现象 | 原因 | 处理 |
|---|---|---|
| `graphify claude install` 报 `already configured` | 已跑过 | 正常，幂等 |
| `gitnexus setup` 提示 settings 已存在 | 已跑过 | 正常，幂等 |
| `rtk init -g --auto-patch` 报 hook already present | 已跑过 | 正常，幂等 |
| `git status` 仍是原始格式（未变 rtk 紧凑） | opencode 未重启 / hook 顺序错 | 重启 opencode；跑 `rtk init --show` 5 项检查；确认 gitnexus 在 rtk 前 |
| `rtk gain` 空 | 还没跑过被改写命令 / 刷盘延迟 | 跑一条 `git status` 后再看 |
| 同时存在 `~/.config/opencode/plugins/rtk.ts` 和 hook | 双重 rewrite | 删掉 plugin：`rm ~/.config/opencode/plugins/rtk.ts` |
| `mempalace init .` 报 ChromaDB 模型未下载 | 首次需联网 | 等 ONNX 自动下载 |
| `.opencode/settings.json` 已有自定义 hook | 用户保护 | 脚本不覆盖，列出缺失让用户手加 |
| opencode 启动看不到 settings 日志 | 日志级别 | `OPENCODE_LOG=debug` |
| gitnexus hook EXIT 非 0 | Node.js 环境问题 | 检查 `node --version`，需 ≥18 |

---

## 严格不做清单

- 不创建 `.memory/` / `.gitnexus/` / `graphify-out/`（运行时插件自产）
- 不改 `.gitignore`
- 不跑 `graphify update .` / `gitnexus analyze`（建图 ≠ 配置）
- 不写官方文档之外的 hook 逻辑

---

## 相关文件

- `templates/init-settings-hooks.sh` — mempalace hook 注册脚本
- `~/.agents/skills/plugin-setup/SKILL.md` — 第二步（前置）
- 仓根 `AGENTS.md` — 第一步（前置）

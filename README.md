# opencode 多 Agents 设计 — 按需调度的轻量骨架

> 面向**代码修复**类长任务的 opencode 多 agent 方案。
> 设计哲学：**按需调度的迭代循环** + **极简调度骨架** + **四项工程纪律** + **文件持久化规划**。

---

## 1. 设计目标

| 维度 | 取舍 |
|---|---|
| **范围** | 代码修复 / 重构 / 多步骤实现类任务 |
| **轻量** | 5 个 agent，无固定流水线，按需触发 |
| **高分** | 重 Explore（AST 图谱）+ Verify（test-driven loop）+ 文件持久化规划 |
| **不做** | 独立 plan agent、reviewer、doc-writer（不计分） |

### 推翻的旧设计

旧 `consult_agents/multi-build` 是 **planner→coder→reviewer→doc-writer 固定四阶段流水线**。本设计**完全推翻**——固定流水线按预定顺序前进，信息不足也要跑完全流程；本设计采用**按信息状态切换阶段的迭代循环**：探索未满足就多探索，验证未通过就回 implement，不按预定顺序。

---

## 2. 5-Agent 骨架

```
┌──────────────────────────────────────────────────────┐
│                    main (primary)                    │
│   主控 · 文件规划 · 子 agent 调度                    │
└────────┬───────────┬────────────┬──────────┬─────────┘
         │           │            │          │
    @explore    @implement    @verify   @patcher
    (read-only)  (edit)      (test)     (final patch)
```

### 调度图（迭代循环）

```
    ┌─────────────────────────────────┐
    │            main                 │
    │  Observe → Plan → Act → Verify  │
    │     ↑                       │   │
    │     └───────────────────────┘   │
    └─────────────────────────────────┘
        │       │        │       │
        ▼       ▼        ▼       ▼
     explore implement verify patcher
       (信息) (变更)   (验证)  (交付)
```

### 边界与触发

| Agent | 模式 | 何时调度 | 输入 | 输出 |
|---|---|---|---|---|
| **main** | primary | 默认主控（用户通过 Tab 进入） | 任务 | 全过程产物 |
| **explore** | subagent | 不熟悉代码 / 全局检索 / AST 关系 | 模糊问题 | 候选符号 + 调用图 |
| **implement** | subagent | 方案明确，需精确编辑 | work spec | 工作树变更 + 自验报告 |
| **verify** | subagent | 任何代码修改后 | 测试范围 | PASS/FAIL + root cause |
| **patcher** | subagent | 准备最终交付 | 工作树状态 | 干净 patch + 全量测试报告 |

---

## 3. 工具调用时机

### gitnexus（AST 知识图谱）

| 工具 | 主用 agent | 何时用 |
|---|---|---|
| `gitnexus_query` | explore | 模糊问题找执行流 |
| `gitnexus_context` | explore | 已知符号名查 360 度引用 |
| `gitnexus_cypher` | explore | 复杂结构查询 |
| `gitnexus_impact` | implement | **改前必跑** — 评估爆炸半径 |
| `gitnexus_route_map` / `api_impact` | explore | API 路由相关任务 |
| `gitnexus_detect_changes` | verify | 失败诊断时映射变更到 process |
| `gitnexus_rename` | implement | 多文件协调重命名 |

### mempalace（持久记忆）

**只在 main agent 中读写**。subagent 不写记忆，避免污染。

| 操作 | 时机 |
|---|---|
| `mempalace_search` | main 接到任务时查历史决策 / explore 开工前查相关 wing |
| `mempalace_add_drawer` | main 完成里程碑（room=decisions）/ 踩坑时（room=pitfalls）|
| `mempalace_kg_*` | main 在多 session 间维护实体关系（可选） |

### opencode 内置

- `task` — main 调度子 agent 的唯一通道
- `read/edit/write` — 受 permission 约束
- `bash` — verify/patcher 限定测试相关命令
- `lsp` — implement 改后类型/语法检查
- `skill` — main 启动任务时加载 `goal-driven-planning`（见 §4）

---

## 4. 文件规划层（goal-driven-planning skill）

**核心命题**：上下文窗口是易失内存，文件系统是持久磁盘。任何重要内容必须落盘。

`agents/skills/goal-driven-planning/` 提供：
- 三文件协作：`task_plan.md`（目标/阶段/决策/错误）、`findings.md`（探索结果/外部内容隔离区）、`progress.md`（会话日志/测试结果）
- 四协议：决策前重读 / 两步落盘 / 三次失败协议 / 五问重启
- **hooks 自动注入**（opencode hooks 系统）：
  - `UserPromptSubmit` — 检测活跃 task_plan 提示读取
  - `PreToolUse` — 每次工具调用前注入 task_plan.md 头部
  - `PostToolUse(Write|Edit)` — 提示更新 progress
  - `Stop` — 会话结束盘点未完成阶段

**子 agent 协作模式**：

| sub-agent | 是否能写规划文件 | 协作模式 |
|---|---|---|
| explore（read-only） | ❌ | 返回结构化报告 → main 落盘到 `findings.md` |
| verify（read-only） | ❌ | 返回 PASS/FAIL → main 落盘到 `progress.md` 与错误台账 |
| implement（edit allow） | ✅ progress / findings | 完成 WP 后追加；新发现追加 findings |
| patcher（edit allow） | ✅ progress（装配段） | **不写 task_plan**；最终阶段必须清理整个 `.task_state/` |

`task_plan.md` **只 main 写**。决策权与目标定义不外放。

---

## 5. 四项工程纪律映射

四项纪律已在 opencode 系统级提示词中固化，各 agent 不复制全文，只在主战场显式锚点：

| 纪律 | 主战场 | 落地形式 |
|---|---|---|
| **思考前置** | explore | 多种解释先列出，模糊 query 必须二次过滤 |
| **简洁优先** | main / implement | 200→50 行重写自检；禁止过度抽象 |
| **外科式修改** | implement / patcher | 每行变更可追溯；patch 装配最严 |
| **目标驱动** | verify | 必须有客观 PASS/FAIL；无可跑测试 = 阻断 |

---

## 6. 安装与使用

### 项目级（推荐）

```bash
mkdir -p .opencode/agents .opencode/skills
cp agents/*.md             .opencode/agents/
cp -r agents/skills/*      .opencode/skills/
```

### 全局

```bash
mkdir -p ~/.config/opencode/agents ~/.config/opencode/skills
cp agents/*.md             ~/.config/opencode/agents/
cp -r agents/skills/*      ~/.config/opencode/skills/
```

### 与内置 agent 共存

opencode 自带 `build`（默认 primary）/ `plan` / `general` / `explore`。本套设计：

- **覆盖**：内置 `explore` 会被本设计的 `explore.md` 覆盖（同名）
- **新增**：`main` / `implement` / `verify` / `patcher` 都是新 agent
- **保留**：内置 `build` 保留，用户可 Tab 在 `main` 和 `build` 间切换；如想强制用 main，在 `opencode.json` 中设置：

  ```json
  { "agent": { "build": { "disable": true } } }
  ```

### 使用方式

启动 opencode 后默认进入 `build`（内置）。**Tab 切换到 `main`** 即激活本套调度 + 文件规划。

或在 `opencode.json` 中把 main 设为默认入口：

```json
{ "agent": { "main": { "mode": "primary" } } }
```

---

## 7. 模型选型策略（不写死）

frontmatter 中**未指定 model**，由用户在 `opencode.json` 中按预算与任务难度自配。

**分层原则**（按价值密度从高到低）：

| 层 | 价值密度 | 配置建议 |
|---|---|---|
| `main` | 调度判断决定全局走向 | 选最强一档（推理 + 长上下文） |
| `implement` | 代码生成质量直接决定 patch 成败 | 选最强一档（与 main 同档或更高） |
| `explore` | 信息提取，可批量重复 | 选中等档（速度优先） |
| `verify` | 客观判断 PASS/FAIL，结构化输出 | 选中等档 |
| `patcher` | 装配 + 测试，需严格遵守清理铁律 | 选中等档以上 |

**配置方式**：在 `opencode.json` 的 `agent.<name>.model` 显式指定。不指定时 sub-agent 继承 main 的模型。

```json
{
  "agent": {
    "main":      { "model": "<provider>/<top-tier-model>" },
    "explore":   { "model": "<provider>/<mid-tier-model>" },
    "implement": { "model": "<provider>/<top-tier-model>" },
    "verify":    { "model": "<provider>/<mid-tier-model>" },
    "patcher":   { "model": "<provider>/<mid-tier-model>" }
  }
}
```

> 不在 frontmatter 写死模型 = subagent 默认继承 main 的模型；显式配置 `opencode.json` 才会分层。

---

## 8. 反模式自检

部署前确认：

- [ ] 没有把固定流水线塞回去（main 必须支持回流）
- [ ] subagent 没有调度其他 subagent 的能力（只 main 调度）
- [ ] verify 的 permission 中 edit/write 必须 deny
- [ ] explore 的 permission 中 edit/write/任意 bash 必须 deny
- [ ] implement 在 spec 之外不修改文件
- [ ] patcher 把 `.task_state/`（含 task_plan/findings/progress）清干净，不进 patch
- [ ] mempalace 只在 main 写入
- [ ] 外部网页/搜索内容只写 findings.md，永远不进 task_plan.md

---

## 9. 文件清单

```
agents/
├── main.md                              # primary 主控
├── explore.md                           # subagent 只读侦察
├── implement.md                         # subagent 外科编辑
├── verify.md                            # subagent 测试裁判
├── patcher.md                           # subagent 交付装配
├── README.md                            # 本文件
└── skills/
    └── goal-driven-planning/            # 文件规划 skill（含 hooks）
        ├── SKILL.md                     # 协议、纪律、hooks 配置
        └── templates/
            ├── task_plan.md             # 目标 / 阶段 / 决策台账模板
            ├── findings.md              # 探索 / 外部内容隔离区模板
            └── progress.md              # 会话日志 / 测试结果模板
```

---

## 10. 后续可选增强（非本期范围）

- **multi-repo 支持**：扩展 main 调度到 gitnexus 的 group mode（`@<groupName>`）
- **自我进化**：让 main 在踩坑后自动写经验性 SKILL（需要明确权限边界）
- **压缩策略**：长任务自动调用 `compress`，可在 main prompt 中加阈值规则
- **失败案例回放**：把典型失败案例写入 mempalace `wing_pitfalls`，跨任务复用

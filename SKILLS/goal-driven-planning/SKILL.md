---
name: goal-driven-planning
description: 目标驱动的文件规划系统，专为长任务多步骤代码修复 agent 设计。核心范式：模型用 opencode TodoWrite 提醒自己工作，而非靠提示词文本指挥。把易失的上下文窗口（内存）与持久的文件系统（磁盘）解耦：三文件（task_plan/findings/progress）装知识，TodoWrite 装实时动作队列，hooks 把目标推回上下文。支持长任务、多轮失败、/clear 后恢复。当任务涉及多步骤代码修复、需要跨子 agent 协作、需要避免重复失败、需要长期跟踪决策与错误时使用。触发词：目标规划、文件规划、长任务规划、代码修复规划、多步骤任务、任务恢复、agent 协作规划。
metadata:
  audience: "primary-agent"
  workflow: "long-task-code-repair"
hooks:
  UserPromptSubmit:
    - hooks:
        - type: command
          command: "if [ -f .task_state/task_plan.md ]; then echo '[goal-driven-planning] 检测到活跃 task_plan.md。如果本会话还未读取 .task_state/{task_plan,findings,progress}.md，请立即读取以恢复目标与状态，并用 TodoWrite 把当前阶段的待办动作 push 进执行队列。'; fi"
  PreToolUse:
    - matcher: "Write|Edit|Bash|Read|Glob|Grep"
      hooks:
        - type: command
          command: "if [ -f .task_state/task_plan.md ]; then echo '---BEGIN TASK_PLAN HEAD---'; sed -n '1,30p' .task_state/task_plan.md 2>/dev/null; echo '---END TASK_PLAN HEAD---'; fi"
  PostToolUse:
    - matcher: "Write|Edit"
      hooks:
        - type: command
          command: "if [ -f .task_state/task_plan.md ]; then echo '[goal-driven-planning] 文件已修改 → 若本次编辑构成关键事件（verify 结论、失败根因、重大决策/范围变化、patcher 装配摘要、跨 /clear 恢复点），可追加 progress.md checkpoint；普通成功编辑、工具调用、hook 提醒、纯状态推进不写。如对应 TodoWrite 动作完成，立刻标 completed；阶段全部 milestone 完成才动 task_plan.md 状态。'; fi"
    - matcher: "Bash"
      hooks:
        - type: command
          command: "if [ -f .task_state/task_plan.md ]; then echo '[goal-driven-planning] 若刚跑了测试，请把 PASS/FAIL 与失败 traceback 摘要写入 progress.md「测试结果」段，并把对应 TodoWrite 动作标 completed。'; fi"
  Stop:
    - hooks:
        - type: command
          command: "if [ -f .task_state/task_plan.md ]; then UNRESOLVED=$(grep -c 'in_progress\\|pending' .task_state/task_plan.md 2>/dev/null || echo 0); echo \"[goal-driven-planning] 会话结束 — task_plan.md 中仍有 ${UNRESOLVED} 个 in_progress/pending 阶段。注意：TodoWrite 队列是会话级内存，下次会话恢复时请先读三文件，再用 TodoWrite 重建当前阶段的执行队列。\"; fi"
---

# Goal-Driven Planning

三层各司其职：上下文窗口（易失内存）、文件系统（持久磁盘）、TodoWrite（会话级动作队列）。所有阶段、动作、决策、错误处理都从**目标**反推。

## 1. 三层职责（避免双头记账）

| 层 | 载体 | 装什么 | 不装什么 | 生命周期 |
|---|---|---|---|---|
| 持久知识 | `.task_state/*.md` 三文件 | 目标 / 成功标准 / 阶段 milestone / 决策（带 D-NNN ID）/ 错误台账（带 E-NNN ID）/ 探索结论 / 测试日志 / **关键事件 checkpoint** | 实时动作 / 外部内容 | 跨会话、跨 /clear |
| 实时动作 | TodoWrite | 当前阶段细粒度动作（每条 = 一个可兑现动作，可覆盖多个工具或一次 sub-agent 调度） | 知识、目标、决策 | 当前会话；/clear 后从三文件重建 |
| 注意力推送 | hooks | 自动化提醒 | — | 工具触发瞬间 |

铁律：

- 知识只进三文件，不进 TodoWrite（TodoWrite 装"做什么"，不装"是什么"）
- 动作清单只进 TodoWrite，不进 task_plan.md 的 `- [ ]` checklist（task_plan checkbox 只代表阶段级 milestone）
- task_plan.md 的 milestone checkbox 只在对应 TodoWrite 全部 completed 后才能勾掉——单向同步，TodoWrite 是源

## 2. 三文件分工

| 文件 | 用途 | 写入者 | 信任级别 |
|---|---|---|---|
| `.task_state/task_plan.md` | 目标 / 成功标准 / 阶段 milestone / 决策 / 错误台账 | 只 main | 高（被反复读取） |
| `.task_state/findings.md` | 代码探索结果 / 外部文档 / 网页内容 / 隔离区 | main 或 explore→main 沉淀 | 低（外部内容隔离，不进 task_plan） |
| `.task_state/progress.md` | **关键事件 checkpoint** + 测试结果摘要 + 错误回流摘要 + 五问重启答案 | main 主写；sub-agent 仅在输出中提供可选 `checkpoint_hint` | 中 |

> progress.md 是关键事件日志，不是流水账。它只保留 60 天后仍能帮助恢复任务状态或解释回流决策的 checkpoint；普通工具调用、成功 explore / implement 返回、hook 提醒、纯状态推进不写。详见 §5.5。

> task_plan.md 的「决策」「错误台账」每条带稳定 ID（D-NNN / E-NNN），便于跨文件反向引用。错误台账还要写触发它的 checkpoint 与 `关联决策`。

## 3. TodoWrite 动作模板

每个 agent（含 sub-agent）有各自独立的 TodoWrite 队列；sub-agent 的队列不会回流到 main。下面所有模板针对 main 的全任务执行主线。

### 3.1 各阶段标准清单（进入新阶段时一次性 push）

#### 阶段 0：启动协议（任务进入 main 第一件事）

```
TodoWrite:
  - [pending] 复杂度自检（4 信号），决定是否走规划路径
  - [pending] 若命中 → mkdir -p .task_state/ + 复制三模板
  - [pending] 在 task_plan.md 顶部填目标 + 成功标准（未填禁下一步）
  - [pending] 持久记忆查询：查历史决策 / pitfalls
```

#### 阶段恢复（/clear 后或新会话进入已有 .task_state/）

```
TodoWrite:
  - [pending] 读 task_plan.md（目标、当前阶段、决策、错误台账）
  - [pending] 读 progress.md（上次会话最后做了什么、测试到哪）
  - [pending] 读 findings.md（已积累的探索结果）
  - [pending] 执行五问重启自检（见 §7）
  - [pending] 用 TodoWrite 重建当前阶段的执行队列
```

#### 阶段 1：理解 + 复现

```
TodoWrite:
  - [pending] 阅读 issue / 任务描述并提取关键词
  - [pending] 调度 @explore 定位涉及符号 / 调用图
  - [pending] 把 explore 报告落盘到 findings.md
  - [pending] 写复现脚本（如可行）跑通使其 fail
  - [pending] 在 task_plan.md 阶段 1 milestone checkbox 全部勾选
```

#### 阶段 2：方案设计

```
TodoWrite:
  - [pending] 列 ≥2 种方案（写入 task_plan.md「决策」段）
  - [pending] 对每个目标符号跑 影响分析工具评估爆炸半径
  - [pending] 选定方案并填阶段 3 任务列表
```

#### 阶段 3：Implement → Verify 循环（每个 WP 一组）

```
TodoWrite:
  - [pending] 调度 @implement 完成 WP-N
  - [pending] 若 implement 返回高风险/BLOCKED/影响下游决策，则记录 progress.md checkpoint
  - [pending] 调度 @verify 跑定向测试
  - [pending] 把 verify PASS/FAIL/BLOCKED 写入 progress.md checkpoint
  - [pending][条件] verify FAIL → 把根因写入 task_plan.md 错误台账，决定回流方向
```

#### 阶段 4：装配交付

```
TodoWrite:
  - [pending] 调度 @patcher 清理残留 + 跑全量测试
  - [pending] 确认 .task_state/ 已被清理
  - [pending] 写决策摘要到 持久记忆（写入任务决策摘要）
```

### 3.2 动态插入触发器

下列情境 main 必须立即往 TodoWrite 插新 todo，不允许"心里记着"：

| 触发情境 | 必插 todo |
|---|---|
| verify PASS/FAIL/BLOCKED | "记录 verify checkpoint；FAIL/BLOCKED 同步写错误根因与回流方向" |
| sub-agent 返回 BLOCKED / 高风险 / 改变下游决策 | "记录 checkpoint_hint 并由 main 决定回流方向" |
| 重大计划变更 / 范围扩大 / 用户确认 | "写 task_plan.md 决策 D-NNN，并记录 progress.md checkpoint" |
| 看了大段网页 / PDF / 截图 | "把外部内容落盘到 findings.md" |
| verify FAIL | "写错误根因到 task_plan.md 错误台账" + "决策回流方向" |
| 同一错误第 3 次 | "停下，重读 task_plan 目标，质疑当前假设" + "记录 checkpoint；必要时向用户求助" |
| 即将切阶段 | "重读 task_plan.md 目标 + 成功标准段" |
| 即将调度 sub-agent | "准备 spec：目标/范围/方案/验收四项齐全" |
| 发现复杂度超初判 | "补建 / 升级 .task_state/ 三件套并告知用户" |

### 3.3 状态机纪律

- 任意时刻最多 1 个 in_progress（opencode 原生约束）
- 完成立刻标 completed，不批量延后
- 不再需要的 todo 标 cancelled，不留 zombie
- TodoWrite 队列空 ≠ 任务完成 — 任务完成的判定看 task_plan.md「成功标准」全部 PASS

## 4. 启动协议

### 任务开始前

```
Step 1: 复杂度自检（4 信号，由 main 提示词定义）
  ├── 全不命中 → 走轻量路径，不启用本 skill
  └── 任一命中 → 进入下面步骤

Step 2: 检查 .task_state/ 是否存在
  ├── 不存在 → 进入「初始化」
  └── 存在  → 进入「恢复」

Step 3: 用 TodoWrite push 阶段 0 标准清单（见 §3.1）
```

### 初始化

```bash
mkdir -p .task_state
cp ${CLAUDE_PLUGIN_ROOT}/templates/task_plan.md  .task_state/task_plan.md
cp ${CLAUDE_PLUGIN_ROOT}/templates/findings.md   .task_state/findings.md
cp ${CLAUDE_PLUGIN_ROOT}/templates/progress.md   .task_state/progress.md
```

立刻填 task_plan.md 顶部：

- 目标（一句话最终状态）
- 成功标准（可验证的测试 / 命令 / 行为，不允许"看起来对了"）

未填完成功标准前，不进入下一阶段。

### 恢复（/clear 后或新会话）

按 §3.1「阶段恢复」标准 todo 清单执行。读完三文件后必须执行五问重启（§7），任一答不上 → 补做该项再继续。

## 5. 执行期纪律

### 5.1 决策前重读

任何重大决策前必须重读 task_plan.md 的「目标」和「成功标准」段：

- 切阶段
- 调度 sub-agent
- 决定回流 vs 继续
- 决定是否扩大改动范围

操作上：在 TodoWrite 插一条 "重读 task_plan 目标段" todo，标 in_progress，读完标 completed，再开始决策。

### 5.2 落盘规则

探索类操作（grep / glob / 代码查询 / webfetch / 大文件读取）产生**可复用的关键发现**时，必须在 TodoWrite 插一条 "把关键发现写入 findings.md" 并立即执行。纯验证性查询（已知答案的确认）不落盘。

### 5.3 三次失败协议（绝不重复失败）

```
第 1 次失败 → TodoWrite: "读错误，找根因，针对性修复"
第 2 次失败 → TodoWrite: "换工具 / 换库 / 换路径"；不重复同一动作
第 3 次失败 → TodoWrite: "停下，质疑假设，重读 task_plan，必要时拆分阶段"
≥ 3 次失败 → TodoWrite: "向用户求助：列已尝试方案 + 具体错误"
```

每次失败必须写入 task_plan.md「错误台账」段，附尝试次数与解决方案。重复同一失败 = 协议违反。

### 5.4 行动后更新

任何 TodoWrite 动作完成后：

- 立刻标 completed（不批量延后）
- 只在触发关键事件时追加 progress.md checkpoint（见 §5.5）；普通成功动作不写
- 若产生决策，写入 task_plan.md「决策」段（分配 D-NNN ID）
- 若踩坑，写入 task_plan.md「错误台账」段（分配 E-NNN ID + 关联 checkpoint + 关联决策 D-NNN）
- 若该阶段所有 TodoWrite 全 completed，才去 task_plan.md 勾掉对应阶段 milestone checkbox，并把阶段状态改为 `complete`

### 5.5 checkpoint 写入规范（progress.md 顶部「关键事件 checkpoint」段）

每行 9 字段：

| 字段 | 含义 | 取值示例 |
|---|---|---|
| `time` | ISO8601 本地时间 | `2026-05-13T09:42:11` |
| `agent` | 执行体 | `main` / `explore` / `implement` / `verify` / `patcher` |
| `phase` | 五段循环 | `observe` / `plan` / `act` / `verify` / `reflect` |
| `action` | 一句话关键事件 | `verify PASS` / `verify FAIL 根因定位` / `patcher 装配摘要` |
| `tool` | 实际调用的工具 | `task` / `gitnexus_query` / `bash` / `edit` |
| `input_ref` | 输入摘要或引用 | `WP-2 spec / targets=[Foo,Bar]` |
| `output_ref` | 输出摘要或引用 | `findings.md#关键符号` / `verify.PASS` |
| `result` | 客观结果 | `PASS` / `FAIL` / `BLOCKED` / `OK` |
| `next` | 下一步 | `调度 implement WP-2` |

写入纪律：

- **只 main 写**。sub-agent 仅在触发关键事件时通过 `checkpoint_hint` 字段提供原料，main 决定是否落盘
- 默认不记录：成功 explore 返回、成功 implement 返回、普通工具调用、hook 提醒、纯状态推进、已在 findings.md 或 changed_files 可追溯的内容
- 必须记录：verify PASS/FAIL/BLOCKED；FAIL/BLOCKED 根因与回流方向；重大计划变更/范围扩大/用户确认；同一错误第三次；patcher 最终装配和全量测试摘要；跨 `/clear` 恢复所需 checkpoint
- 错误台账新增条目时，把对应 checkpoint 的 `time` 抄进 task_plan.md 错误台账的「关联 checkpoint」列，形成双向追溯

#### 信噪比硬规则（违反即视为污染 checkpoint，应回删）

每一行必须同时满足以下条件，否则**禁止写入**：

1. `input_ref` 与 `output_ref` 都不为空，且至少一个指向具体符号 / 文件路径 / 错误码 / 决策 ID（D-NNN / E-NNN）；不接受 `已完成` / `进行中` / `成功` 这类裸状态
2. `action` 是动词短语 + 直接对象（如 `读 SKILL.md §5.5`、`同步 project-onboarding 到部署版`），不是 `处理任务` / `继续推进`
3. `result` 取自客观信号（PASS/FAIL/BLOCKED/具体退出码 / 文件 hash / 测试名），不是"看起来对了"
4. `next` 指向下一条可被 TodoWrite 立即兑现的动作；若无下一步写 `-`，不写 `继续观察`

反模式（禁止）：

| ❌ 低信噪比示例 | 病因 |
|---|---|
| `... \| main \| act \| WP-3 已完成 \| - \| - \| - \| OK \| -` | 全字段空，纯打卡 |
| `... \| main \| act \| 修改文件 \| edit \| SKILL.md \| 已修改 \| OK \| -` | output_ref 空话；未指出修改的具体段/规则 |
| `... \| main \| reflect \| 推进任务 \| - \| - \| - \| OK \| 继续` | 动词模糊、无引用、next 空话 |
| hook 触发后补一行 `心跳` 行 | hook 提醒不是 checkpoint |

正例：

```
2026-05-13T14:25 | main | verify | verify PASS | bash | WP-2 test_target | 12/12 passed | PASS | patcher 装配
2026-05-13T14:40 | main | reflect | patcher 装配摘要 | bash+git | verify.PASS | full test 247/247 + patch apply check pass | PASS | -
```

判定口径：一条 checkpoint 被 60 天后回看时仍能复原"为什么这么做、改到了哪、出了什么、下一步去哪"，才算合格；否则就是噪声。

## 6. sub-agent 协作

opencode 的 sub-agent 权限是粗粒度的；只读 sub-agent（explore / verify）不能直接写规划文件。task_plan.md 的写权与 main 全任务执行主线只属于 main。

| sub-agent | 能写规划文件 | 协作模式 |
|---|---|---|
| explore（read-only） | ❌ | 返回结构化报告 → main 在 TodoWrite 插一条 "落盘 explore 报告到 findings.md" → main 落盘 |
| verify（read-only） | ❌ | 返回 PASS/FAIL/BLOCKED + root cause + `checkpoint_hint` → main 落盘 checkpoint / 错误台账 |
| implement（edit allow） | ❌ 规划文件 | 成功返回默认无需 checkpoint；仅 BLOCKED / 高风险 / 影响下游决策时给 `checkpoint_hint` |
| patcher（edit allow） | ❌ 规划文件 | 返回最终装配和全量测试摘要的 `checkpoint_hint`；不写 task_plan.md |

> sub-agent 也可以在自己会话内用 TodoWrite 管理本次任务的内部步骤——这是 agent 私有队列，不会回流到 main。但 task_plan.md 的写权与全任务执行主线只属于 main。

## 7. 五问重启自检

任何长任务中或恢复后必须能回答：

| 问题 | 答案来源 |
|---|---|
| 我在哪里？ | task_plan.md 当前阶段 |
| 我要去哪里？ | task_plan.md 剩余阶段 |
| 目标是什么？ | task_plan.md 顶部 Goal |
| 成功标准是什么？ | task_plan.md 顶部 Success Criteria |
| 我学到了什么？ | findings.md |
| 我做了什么关键节点？ | progress.md（**不是**看 TodoWrite — 它已被 /clear 清空） |

任一答不上 = 上下文管理失败 → 立刻读相应文件补齐再继续。

恢复后必须用 TodoWrite 把当前阶段的执行队列重建（按 §3.1 模板），不要假设上次会话的 TodoWrite 还在。

## 8. 何时使用此 skill

- **使用**：见 main 提示词「复杂度自检 4 信号」，任一命中即启用
- **跳过**：4 信号全不命中的极小任务（单文件单行修复 / 拼写 / 纯查询解释）；用户明确说"快速看看"

## 9. 反模式

| ❌ 不要 | ✅ 应该 |
|---|---|
| 把目标 / 决策 / 错误台账塞 TodoWrite | 这些是知识，进 task_plan.md |
| 把分步动作清单塞 task_plan.md 的 `- [ ]` | 进 TodoWrite；task_plan checkbox 只代表阶段级 milestone |
| 完成 TodoWrite 动作不及时标 completed | 立刻标，不批量延后 |
| /clear 后假设 TodoWrite 还在 | 必须从三文件重建 |
| 把网页 / 搜索结果塞 task_plan.md | 只写 findings.md |
| sub-agent 自行写 task_plan.md | task_plan.md 写权属 main |
| 失败了静默重试 | 写错误台账 + TodoWrite 插换方案 todo |
| 跳过初始化直接干活 | 先填目标 + 成功标准 |
| 重读 task_plan 时只看阶段不看目标 | 必须重读目标段 |
| 把 .task_state/ 提交到 git | patcher 阶段必须清理 |
| TodoWrite 队列空了就以为任务完成 | 任务完成 = task_plan.md 成功标准全 PASS |
| 写无信息量 checkpoint（"已完成"/"继续推进"/打卡心跳） | 见 §5.5 信噪比硬规则；不达标的行禁止落盘，已落盘的应回删 |

## 10. 与 main 工作流的对接

§3.1 各阶段模板已定义完整执行流程，§5 执行期纪律定义行为约束，此处不重复。main 的 Observe → Plan → Act → Verify → Reflect 五步循环对应：复杂度自检（§4）→ 填 task_plan（§3.1 阶段 0）→ 按 TodoWrite 执行（§3.1 阶段 1-4）→ 调度 verify（§3.1 阶段 3）→ 决策前重读目标（§5.1）。

## 11. 模板

直接复制 [templates/task_plan.md](templates/task_plan.md) / [templates/findings.md](templates/findings.md) / [templates/progress.md](templates/progress.md) 到项目 `.task_state/` 目录。

> 模板里的 `- [ ]` checklist 是阶段级 milestone，不是分步动作清单。分步动作走 TodoWrite。两者区分见 §1。

# OPENCODE 多 Agent 工作流 · 合约工程化版

> 本目录是 OPENCODE fork 的 **多 agent 编排系统**。采用合约式接口 + 确定性路由 + 可重放执行 + 强隔离的工程化重构。
>
> **⚠️ 适用范围**：本系统 **仅服务代码工作流**——读代码、改代码、跑测试、装配 patch。**不处理**文档翻译、客服问答、PPT/Excel 生成、通用聊天等非代码任务；收到此类请求时 main 直接拒绝并向用户说明。

---

## 一、系统拓扑

```
                         ┌──────────┐
                         │   USER   │
                         └────┬─────┘
                              │ user_intent
                              ▼
                       ┌──────────────┐
                       │   main 🎯    │  ← 唯一入口/编排者/决策者/checkpoint 中枢
                       │  (primary)   │
                       └──┬──┬──┬──┬──┘
                          │  │  │  │
            ┌─────────────┘  │  │  └─────────────┐
            ▼                ▼  ▼                ▼
       ┌─────────┐    ┌──────────┐    ┌────────┐    ┌─────────┐
       │ explore │ →  │implement │ →  │ verify │ →  │ patcher │
       │ (read)  │    │ (write)  │    │ (test) │    │(deliver)│
       └─────────┘    └──────────┘    └────────┘    └─────────┘
            │              │               │              │
            └──────────────┴───────────────┴──────────────┘
                              │
                              ▼ output_variables（结构化字段）
                       ┌─────────────────┐
                       │  .task_state/   │  ← 持久治理层
                       │  task_plan.md   │
                       │  findings.md    │
                       │  progress.md    │
                       └─────────────────┘
                              │
                              ▼
                       ┌─────────────────┐
                       │   mempalace     │  ← 跨任务记忆
                       │  wing_<task>/   │
                       │  decisions      │
                       │  pitfalls       │
                       └─────────────────┘
```

---

## 二、五 agent 角色一览

| Agent | mode | 职责 | 写权限 | 关键工具 |
|---|---|---|---|---|
| **main** | primary | 编排 / 决策 / checkpoint | task_plan.md / progress.md / mempalace | 调度 sub-agent + gitnexus + compress |
| **explore** | subagent | 只读侦察，找符号 / 调用关系 | ❌ 零写入 | gitnexus_query/_context/_impact + grep + glob |
| **implement** | subagent | 按 spec 落地代码 | edit / write | read + edit + gitnexus_impact + lint/typecheck |
| **verify** | subagent | 跑测试，PASS/FAIL/BLOCKED 三态 | ❌ 规划文件零写入 | bash(test) + gitnexus_detect_changes |
| **patcher** | subagent | 清理残留 + 全量测试 + 装配 patch | edit(清理) / 删 `.task_state/` | bash + git + 全量测试 |

---

## 三、职责 × 权限 × 越权路由（核心契约）

### 3.1 一表看清谁能做什么
| Agent | 任务域 | 写权限 | 可越权操作 | 越权处置 |
|---|---|---|---|---|
| **main** | 编排 / 决策 / checkpoint / 装配交付 | task_plan.md / progress.md / mempalace | — | （编排者本身无上层）拒绝非代码任务 |
| **explore** | 只读代码侦察 | ❌ 任何写入 | 写文件、调用 webfetch、跑测试 | `BLOCKED_NEED_ESCALATION` 返回 main |
| **implement** | 按 spec 落地代码 | edit / write（仅 spec.targets 内） | 写 spec 外的文件、跑全量测试、提交 git | `BLOCKED_NEED_ESCALATION` 返回 main |
| **verify** | 跑测试 / 诊断 | ❌ 规划文件零写入 | 改代码、装配 patch、提交 git | `BLOCKED_NEED_ESCALATION` 返回 main |
| **patcher** | 清理残留 + 全量测试 + 装配 patch | edit（仅清理）/ 删 `.task_state/` | 改业务代码、改 verify 结论 | `BLOCKED_NEED_ESCALATION` 返回 main |

### 3.2 两类阻塞码（sub-agent 越权时必须返回）
| 阻塞码 | 触发情形 | 必返字段 |
|---|---|---|
| `BLOCKED_NEED_ESCALATION` | 需要超出 frontmatter 权限的工具/操作 | reason / required_capability / suggested_owner |
| `BLOCKED_OUT_OF_SCOPE` | 收到非代码工作流任务（文档翻译、客服、通用问答、PPT/Excel 生成等） | reason / detected_intent |

### 3.3 main 收到阻塞的三选一（自动判断）
1. **拒绝**：任务本身越界（`BLOCKED_OUT_OF_SCOPE`）→ 向用户回复「本系统仅服务代码工作流」并终止。
2. **代执行**：动作合理但归属错位（如 explore 想 webfetch）→ main 自己执行后把结果落 findings.md，再让 sub-agent 继续。
3. **改派**：动作合理且应换执行者（如 verify 发现还需补代码）→ 改派给正确的 sub-agent，保留已完成上下文。

**判断优先级**：是否在代码工作流域 → 否则拒绝；是否 main 可代办 → 是则代执行；否则改派。

**铁律**：sub-agent **不得自行变通绕过权限**，发现越界必须 return BLOCKED；main **不得**把 BLOCKED 直接抛回用户（除非任务本身确需用户澄清）。

详见 `main.md §2.5`、各 sub-agent §4.2「边界场景」。

---

## 四、工程化范式 → 本系统映射

| 工程化概念 | 本系统落地 | 文件锚 |
|---|---|---|
| Worker Agent 6 元组（Name+Desc+Instructions+Inputs+Outputs+MCP+Env） | agent.md frontmatter + 第 1 层「角色契约」 | 每个 agent.md |
| Inputs Schema | sub-agent 文档的 `Input Schema` 表 | explore/implement/verify/patcher §1.2 |
| Output Variables（KEY=value） | Output Schema 中的 `output_variables` 段 | explore/implement/verify/patcher §1.3 |
| MCP Connectors / Tool Whitelist | 第 1 层「权限矩阵」表 | 每个 agent §1.4 |
| max_turns | sub-agent 边界场景中的"过量收敛/失败次数上限" | 各 agent 第 4 层 |
| Trigger Context Injection | main 调度时把上下文打包进 spec | main §2.2 路由表 |
| Output Variable Gate（VALIDATION_STATUS） | verify 的 PASS/FAIL/BLOCKED 三态 | verify §1.3 |
| Auto-Compaction | 上下文压缩 (compress) 触发规则 | main §3.4 |
| Persistent Memory（MEMORY.md） | mempalace 写入时机 | main §3.5 |
| Checkpoint Log | progress.md 关键事件 checkpoint | main §3.3 |
| Pre/PostToolUse Hooks | goal-driven-planning skill 的自动注入 | skill 文档 |

**未引入的外部范式概念**（避免过度工程化）：
- Pipeline / Stage / Trigger 表达式 — 本系统不是 CI/CD，main 自己就是 orchestrator
- agent versioning + marketplace — 单仓库 git 已经是版本管理
- container 隔离 — opencode sub-agent 已经是独立 session

---

## 五、Schema 闭环一致性

agent 间通过 **output_variables → 下游 Input Schema** 形成闭环。任一环断裂即拒绝下一阶段。

```
explore.output_variables.targets
   │
   ▼ main 转交
implement.Input.targets         ✅ 1:1 引用
implement.output_variables.changed_files + test_target
   │
   ▼ main 转交
verify.Input.changed_files + test_target   ✅ 涵盖
verify.output_variables.status (PASS|FAIL|BLOCKED)
   │
   ▼ main 转交（仅 PASS 时）
patcher.Input.precondition.verify_status == PASS   ✅ 强检
patcher.output_variables.status (READY|BLOCKED)
   │
   ▼ main 交付
user 收到 deliverable + checkpoint_log
```

**断裂处置**：
- explore 没给 targets → implement 回绝
- implement 没给 changed_files → verify 回绝
- verify 不是 PASS → patcher 回绝
- patcher 不是 READY → main 不交付，回流 verify/implement

---

## 六、checkpoint schema（progress.md 关键事件格式）

progress.md 是临时关键事件 checkpoint，不覆盖所有动作。仅 main 写入；sub-agent 只在触发关键事件时返回 `checkpoint_hint`，由 main 判断是否落盘。

```
| time | agent | phase | action | tool | input_ref | output_ref | result | decision_ref |
```

| 字段 | 说明 |
|---|---|
| time | ISO8601（精确到分） |
| agent | main / explore / implement / verify / patcher |
| phase | Observe / Plan / Act / Verify / Reflect / Cleanup |
| action | 一句话关键事件描述 |
| tool | 工具名（多个用 `+` 连接）；纯思考写 `-` |
| input_ref | 输入引用（如 `findings.md#L42`、`Foo.bar@src/foo.py:42`），不复制原文 |
| output_ref | 输出引用 |
| result | ok / partial / fail / blocked |
| decision_ref | 关联 D-NNN（决策） / E-NNN（错误台账）；无关联写 `-` |

必须记录：verify PASS/FAIL/BLOCKED；FAIL/BLOCKED 根因与回流方向；重大计划变更/范围扩大/用户确认；同一错误第三次；patcher 最终装配和全量测试摘要；跨 `/clear` 恢复所需 checkpoint。

禁止记录：成功 explore 返回、成功 implement 返回、普通工具调用、hook 提醒、纯状态推进、已在 findings.md 或 changed_files 可追溯的内容。

checkpoint 随 `.task_state/` 一起被 patcher 清理；写入意义是被 main 实时消费做决策回流，不进 patch。

---

## 七、启动流程速查

### 用户给 main 一个任务后：

```
1. main 复杂度自检（4 信号宽松判定）
   ├─ 任一命中 → 走规划路径（建 .task_state/ + 加载 goal-driven-planning skill）
   └─ 全不中  → 轻量路径（直接做但仍验证）

2. 规划路径：
   阶段 0  启动协议       建/恢复 .task_state/ + mempalace_search
   阶段 1  Observe       调度 @explore，落 findings.md
   阶段 2  Plan          列方案 / 跑 gitnexus_impact / 写决策 D-NNN
   阶段 3  Act (循环)    @implement → @verify → 失败回流
   阶段 4  Verify        嵌入阶段 3，强制三态结论
   阶段 5  Reflect       @patcher 清理+全测+装配 → mempalace 写决策摘要

3. 每阶段切换前自答四问（main §3.2）：
   - 假设是否显式？
   - 200 行能压到 50 行吗？
   - 每行变更可追溯任务需求？
   - 成功是可跑测试还是"看起来对"？
```

---

## 八、提交规范（Conventional Commits 中文版）

格式：`<type>：(<scope>)<subject>`

| 类型 | 说明 |
|---|---|
| `功能` | 新增功能 |
| `修复` | 缺陷修复 |
| `文档` | 文档变更 |
| `样式` | 格式或静态检查类调整 |
| `重构` | 不改变行为的代码重构 |
| `测试` | 测试新增或重构 |
| `维护` | 构建工具或依赖维护 |
| `优化` | 性能改进 |
| `运维` | CI/CD 与脚本变更 |
| `回滚` | 撤销提交 |

- 破坏性变更可用 `!` 标识
- 标题不超过 72 字符，正文每行不超过 200 字符
- main **不主动提交**，由用户明确指令触发；patcher 装配 READY + 用户确认即可 commit

---

## 九、文件索引

| 文件 | 内容 |
|---|---|
| `main.md` | 主控编排器（四层契约：角色 / 路由 / 协议 / checkpoint 反模式） |
| `explore.md` | 只读侦察 sub-agent |
| `implement.md` | 代码落地 sub-agent |
| `verify.md` | 测试与诊断 sub-agent |
| `patcher.md` | 装配交付 sub-agent |
| `README.md` | 本文档 — 系统总览与工程化范式映射 |
| `old_agents/` | 历史版本归档（已废弃，仅供回溯） |

---

## 十、与外部组件的协作

| 组件 | 关系 |
|---|---|
| **goal-driven-planning skill** | main 阶段 0 自检命中即加载，提供 .task_state/ 三模板与 hooks（自动推目标到上下文） |
| **mempalace MCP** | 跨任务记忆。main 读历史决策、写本任务 decisions；sub-agent 只读不写 |
| **gitnexus MCP** | AST 知识图谱。代码理解的首选工具，比 grep 收敛快 |
| **上下文压缩 (compress)** | OpenCode 内置压缩工具。main 在阶段闭合时主动调用 |
| **opencode TodoWrite** | 实时动作队列。每个 agent 各有独立队列，main 这条是全任务主线 |

---

## 十一、版本与维护

- **当前版本**：v2.0.0（合约工程化重构，2026-05-13）
- **上一版**：v1.x（散文式约定）见 `old_agents/`
- **修改原则**：Schema 字段命名跨版本稳定；新增字段优先于改名；废弃字段保留 1 个 minor 版本

修改任何 agent.md 时请同步：
1. 检查 §五的闭环一致性是否破坏
2. 更新 frontmatter 的 `version` + `last_review`
3. 在本 README §九/十列出新增依赖
4. 写一份 mempalace 决策摘要（`wing_harness-refactor/decisions`）

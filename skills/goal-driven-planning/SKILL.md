---
name: goal-driven-planning
description: 目标驱动的文件规划系统，专为长任务多步骤代码修复 agent 设计。把易失的上下文窗口（内存）和持久的文件系统（磁盘）解耦，用 task_plan.md / findings.md / progress.md 三文件协作，支持长任务、多轮失败、/clear 后恢复。当任务涉及多步骤代码修复、需要跨子 agent 协作、需要避免重复失败、需要长期跟踪决策与错误时使用。触发词：目标规划、文件规划、长任务规划、代码修复规划、多步骤任务、任务恢复、agent 协作规划。
metadata:
  audience: "primary-agent"
  workflow: "long-task-code-repair"
hooks:
  UserPromptSubmit:
    - hooks:
        - type: command
          command: "if [ -f .task_state/task_plan.md ]; then echo '[goal-driven-planning] 检测到活跃 task_plan.md。如果本会话还未读取 .task_state/{task_plan,findings,progress}.md，请立即读取以恢复目标与状态。'; fi"
  PreToolUse:
    - matcher: "Write|Edit|Bash|Read|Glob|Grep"
      hooks:
        - type: command
          command: "if [ -f .task_state/task_plan.md ]; then echo '---BEGIN TASK_PLAN HEAD---'; sed -n '1,30p' .task_state/task_plan.md 2>/dev/null; echo '---END TASK_PLAN HEAD---'; fi"
  PostToolUse:
    - matcher: "Write|Edit"
      hooks:
        - type: command
          command: "if [ -f .task_state/task_plan.md ]; then echo '[goal-driven-planning] 文件已修改 → 请追加 .task_state/progress.md（时间戳 / 操作 / 修改文件）。如阶段完成，请同步更新 task_plan.md 状态。'; fi"
    - matcher: "Bash"
      hooks:
        - type: command
          command: "if [ -f .task_state/task_plan.md ]; then echo '[goal-driven-planning] 若刚跑了测试，请把 PASS/FAIL 与失败 traceback 摘要写入 progress.md「测试结果」段。'; fi"
  Stop:
    - hooks:
        - type: command
          command: "if [ -f .task_state/task_plan.md ]; then UNRESOLVED=$(grep -c 'in_progress\\|pending' .task_state/task_plan.md 2>/dev/null || echo 0); echo \"[goal-driven-planning] 会话结束 — task_plan.md 中仍有 ${UNRESOLVED} 个 in_progress/pending 阶段。下次会话恢复时请先读取三文件。\"; fi"
---

> **注**：本 skill 依赖 opencode 与 Claude Code 兼容的 hooks 系统。hooks 在 UserPromptSubmit / PreToolUse / PostToolUse / Stop 四个触点把 task_plan.md 反复推回上下文窗口，把"决策前重读"从「自觉」变成「强制」。

# Goal-Driven Planning：目标驱动的文件规划

> **核心命题**：上下文窗口是易失内存，文件系统是持久磁盘。任何重要的内容必须落盘。
> **首要主轴**：**目标（Goal）**。所有阶段、决策、错误处理都从目标反推。

---

## 1. 三文件分工

| 文件 | 用途 | 写入者 | 信任级别 |
|---|---|---|---|
| `.task_state/task_plan.md` | 目标 / 成功标准 / 阶段 / 决策 / 错误台账 | **只 main** | 高（被反复读取） |
| `.task_state/findings.md` | 代码探索结果 / 外部文档 / 网页内容 / 隔离区 | main 或 explore→main 沉淀 | 低（外部内容隔离） |
| `.task_state/progress.md` | 会话日志 / 测试结果 / 错误日志 / 五问重启 | main 主写；implement / patcher 可追加 | 中 |

**安全边界**：外部网页 / 搜索结果 / mcp 不可信内容**只能写 findings.md**，永远不能直接进 task_plan.md。task_plan.md 是高频读取目标，污染它会被反复放大。

---

## 2. 启动协议（三步走）

### 任务开始前

```
Step 1: 检查 .task_state/ 是否存在
  ├── 不存在 → 进入"初始化"
  └── 存在  → 进入"恢复"
```

### 初始化

```bash
mkdir -p .task_state
# 复制三模板（${CLAUDE_PLUGIN_ROOT} 是 opencode skill 根变量）
cp ${CLAUDE_PLUGIN_ROOT}/templates/task_plan.md  .task_state/task_plan.md
cp ${CLAUDE_PLUGIN_ROOT}/templates/findings.md   .task_state/findings.md
cp ${CLAUDE_PLUGIN_ROOT}/templates/progress.md   .task_state/progress.md
```

然后**立刻填 task_plan.md 顶部**：
- 目标（一句话最终状态）
- 成功标准（可验证的测试 / 命令 / 行为，**不允许"看起来对了"**）

未填完成功标准前，**不允许进入下一阶段**。

### 恢复（/clear 后或新会话）

按顺序读：
1. `task_plan.md` — 目标 + 当前阶段 + 已做决策
2. `progress.md` — 上一会话最后做了什么、测试通过到哪
3. `findings.md` — 已积累的探索结果

读完执行**五问重启**（见 §6），任何一问答不上 → 补做该项再继续。

---

## 3. 执行期纪律

### 3.1 决策前重读（attention manipulation）

任何"重大决策"前必须重读 task_plan.md 的「目标」和「成功标准」段：
- 切换阶段
- 调度子 agent
- 决定回流 vs 继续
- 决定是否扩大改动范围

理由：长任务的注意力会被最近输入主导，目标会"漂移"。重读是把目标重新拉回当前 token 窗口。

### 3.2 两步落盘规则

每执行 **2 次**「探索类操作」（grep / glob / gitnexus_query / webfetch / 大文件读取）后，**立刻**把关键发现写入 `findings.md`。

理由：探索结果是大量易失上下文，再过几轮 tool call 就被推出窗口。

### 3.3 三次失败协议（绝不重复失败）

```
第 1 次失败 → 读错误，找根因，针对性修复
第 2 次失败 → 换工具 / 换库 / 换路径；绝不重复同一动作
第 3 次失败 → 停下来，质疑假设，回头重读 task_plan，必要时拆分阶段
≥ 3 次失败 → 报告用户，列出已尝试方案与具体错误，请求指导
```

每次失败必须写入 `task_plan.md` 的「错误台账」段，附尝试次数与解决方案。**重复同一失败 = 协议违反**。

### 3.4 行动后更新

任何阶段完成 / 子 agent 返回 / 测试结束后：
- 标记 task_plan.md 阶段状态：`pending` → `in_progress` → `complete`
- 在 progress.md 追加一段（时间戳 / 操作 / 修改文件 / 测试结果）
- 若产生决策，写入 task_plan.md「决策」段
- 若踩坑，写入 task_plan.md「错误台账」段

---

## 4. 子 agent 协作模式（重要）

> opencode 的 sub-agent 权限是粗粒度的；**只读** sub-agent（如 explore / verify）**不能直接写**规划文件。

| sub-agent | 是否能写规划文件 | 协作模式 |
|---|---|---|
| explore（read-only） | ❌ | 返回结构化报告 → main 消化后落盘到 `findings.md` |
| verify（read-only） | ❌ | 返回 PASS/FAIL + root cause → main 落盘到 `progress.md` 和 `task_plan.md` 错误台账 |
| implement（edit allow） | ✅ progress.md / findings.md | 完成 WP 后追加进度；新发现追加 findings |
| patcher（edit allow） | ✅ progress.md（最终装配段） | **不写 task_plan.md**，patch 装配阶段不再产生新决策 |

**任何 sub-agent 都不写 `task_plan.md`** —— 决策权与目标定义只属于 main。

---

## 5. 读 vs 写决策矩阵

| 情境 | 操作 | 理由 |
|---|---|---|
| 刚写完一个文件 | 不要立即重读 | 内容还在上下文里 |
| 看了大段网页 / PDF / 截图 | 立刻写入 findings.md | 多模态/外部内容易失 |
| explore / verify 子 agent 返回 | 必须落盘到对应文件 | 子 agent 上下文不共享 |
| 开始新阶段 | 重读 task_plan.md 目标段 | 注意力刷新 |
| 遇到错误 | 读相关文件 + 错误台账 | 避免重复失败 |
| /clear 或新会话 | 三文件全读 + 五问 | 状态恢复 |
| 跑测试前 | 读 progress.md 上次结果 | 避免重跑已通过测试 |

---

## 6. 五问重启检查（自检）

任何长任务中或恢复后，必须能回答：

| 问题 | 答案来源 |
|---|---|
| 我在哪里？ | task_plan.md 当前阶段 |
| 我要去哪里？ | task_plan.md 剩余阶段 |
| 目标是什么？ | task_plan.md 顶部 Goal |
| 成功标准是什么？ | task_plan.md 顶部 Success Criteria |
| 我学到了什么？ | findings.md |
| 我做了什么？ | progress.md |

**任一答不上** = 上下文管理失败 → 立刻读相应文件补齐再继续。

---

## 7. 何时使用此 skill

**使用**：
- 多步骤代码修复（≥ 3 步）
- 需要 explore → implement → verify 循环的任务
- 跨多次 sub-agent 调度
- 任务可能需要 /clear 后恢复
- 任务有失败重试可能性
- 需要跨会话保持目标与决策一致性的长任务

**跳过**：
- 单文件单行修复
- 纯查询 / 解释类任务（不修改代码）
- 用户明确说"快速看看"

---

## 8. 反模式（明确禁止）

| ❌ 不要 | ✅ 应该 |
|---|---|
| 用 TodoWrite 工具替代 task_plan.md | 用文件持久化（TodoWrite 上下文易失） |
| 把网页 / 搜索结果塞进 task_plan.md | 只写 findings.md |
| 子 agent 自行写 task_plan.md | 只 main 写 task_plan.md |
| 失败了静默重试 | 写错误台账，换方案 |
| 跳过初始化直接干活 | 先填目标 + 成功标准 |
| 重读 task_plan 时只看阶段不看目标 | 必须重读目标段 |
| 把 task_plan.md / progress.md / findings.md 提交到 git | patcher 阶段必须清理 .task_state/ |

---

## 9. 与 main 工作流的对接

main agent 的 5 步工作流（Observe → Plan → Act → Verify → Reflect）与本 skill 的对接：

```
任务进入 main
  ↓
[Observe] 初始化 / 恢复 .task_state/  ←── 本 skill 启动协议
  ↓
[Plan] 填 task_plan.md：目标 / 成功标准 / 阶段
  ↓
[Act] 调度 explore → 落盘 findings.md
       调度 implement → 追加 progress.md
  ↓
[Verify] 调度 verify → 落盘 progress.md（测试结果）
                     → 失败时落盘 task_plan.md 错误台账
  ↓
[Reflect] 决策前重读 task_plan.md
          阶段切换 → 更新状态
  ↓
[最后] patcher 阶段清理 .task_state/（不能进 patch）
```

---

## 10. 模板

直接复制 [templates/task_plan.md](templates/task_plan.md) / [templates/findings.md](templates/findings.md) / [templates/progress.md](templates/progress.md) 到项目 `.task_state/` 目录。

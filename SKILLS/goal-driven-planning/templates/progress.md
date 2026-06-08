# Progress — 关键事件 checkpoint、测试结果、恢复线索

> 本文件承载三件事：
> 1. **关键事件 checkpoint**（每条 9 字段，机器可解析）—— 只记录影响恢复、回流、交付的关键节点
> 2. **测试结果摘要**—— verify PASS/FAIL/BLOCKED 与 patcher 全量测试摘要
> 3. **错误台账联动**—— FAIL/BLOCKED 根因、三次失败、回流方向

---

## 关键事件 checkpoint

> Schema：`time | agent | phase | action | tool | input_ref | output_ref | result | next`
>
> - `time`：ISO8601（精确到秒）
> - `agent`：main / explore / implement / verify / patcher
> - `phase`：observe / plan / act / verify / reflect / deliver
> - `action`：一句话动作描述（动词开头，如「调度 explore 定位符号」「跑定向测试」）
> - `tool`：实际调用的工具名（gitnexus_query / read / edit / bash / @explore ...）
> - `input_ref`：输入指针（task_plan.md§N / findings.md§M / WP-N / 上一行 result）
> - `output_ref`：输出指针（findings.md§N / progress.md§M / 文件路径 / "inline"）
> - `result`：PASS / FAIL / BLOCKED / DONE / SKIP（可附简要附注）
> - `next`：下一步意图（"调度 implement WP-1" / "重新规划" / "回流 main 决策"）

| time | agent | phase | action | tool | input_ref | output_ref | result | next |
|---|---|---|---|---|---|---|---|---|

> **写入规则**：
> - 必写：verify PASS/FAIL/BLOCKED；FAIL/BLOCKED 根因与回流方向；重大计划变更/范围扩大/用户确认；同一错误第三次；patcher 最终装配和全量测试摘要；跨 `/clear` 恢复所需 checkpoint
> - 禁止：成功 explore 返回、成功 implement 返回、普通工具调用、hook 提醒、纯状态推进、已在 findings.md 或 changed_files 可追溯的内容
> - 仅 main 写入；sub-agent 只在触发关键事件时返回 `checkpoint_hint`，由 main 判断是否落盘

---

## 关键事件叙事（可选）

### 会话：[日期 / 任务 ID]

#### [时间戳] 阶段 X：[标题]
- 状态：in_progress / complete
- 关键事件：
  -
- 创建/修改的文件：
  -
- 关键产出：[一句话]

---

## 测试结果

| 时间 | 命令 | 范围 | 通过/总 | 失败用例 | 状态 | 关联 checkpoint |
|------|------|------|---------|---------|------|---------|
|      |      |      |         |         |      |         |

## 错误台账（与 task_plan.md「错误台账」联动）

| 时间 | 错误摘要 | 触发动作 | 第几次 | 解决方案 | 关联 checkpoint |
|------|---------|---------|---------|---------|---------|
|      |         |         | 1       |         |         |

> 同一错误第 3 次出现 → main 必须停下重读 task_plan.md 目标段，必要时求助用户。

---

## 五问重启检查（/clear 或恢复时填写）

| 问题 | 答案 |
|------|------|
| 我在哪里？ | 阶段 X，状态 ... |
| 我要去哪里？ | 剩余阶段 ... |
| 目标是什么？ | [同步自 task_plan.md] |
| 成功标准是什么？ | [同步自 task_plan.md] |
| 我学到了什么？ | 见 findings.md |
| 我做了什么关键节点？ | 见上方 checkpoint + 测试结果 |

---
*hooks 只提醒检查是否出现关键事件；低价值流水账禁止写入。*

# 任务计划：[一句话描述任务]

> 职责边界（先读）：
> - 本文件 `- [ ]` 是阶段级 milestone（粗粒度，跨多次工具调用）
> - 分步动作清单（每条 = 一次工具调用 / 一次 sub-agent 调度）走 opencode TodoWrite，不写在这里
> - 一个 milestone 可对应多条 TodoWrite 动作；TodoWrite 全 completed 后才能勾掉 milestone checkbox
> - 单向同步：TodoWrite 是源，milestone 是汇总

## 目标（Goal）
[最终状态的一句话描述。让任何接手者立刻理解"做完是什么样"。]

## 成功标准（Success Criteria）
- [ ] 可验证标准 1（必须是可跑命令 / 可断言行为，不允许"看起来对了"）
- [ ] 可验证标准 2
- [ ] 可验证标准 3

> 未填完成功标准前，不进入下一阶段。每条标准必须由 verify sub-agent 给出客观 PASS/FAIL。

## 当前阶段
阶段 1

---

## 各阶段（milestone 级，非分步动作）

### 阶段 1：理解 + 复现
- [ ] milestone：能稳定复现 issue
- [ ] milestone：关键符号 / 调用图已落盘 findings.md
- 状态：in_progress
- 门禁：能复现 = 通过；不能复现需向用户确认

### 阶段 2：方案设计
- [ ] milestone：≥ 2 种方案已写入「决策」段
- [ ] milestone：每个目标符号已跑 gitnexus_impact
- [ ] milestone：选定方案颗粒度到符号 / 行级
- 状态：pending
- 门禁：方案颗粒度到符号 / 行级

### 阶段 3：实现 + 验证循环
- [ ] milestone：所有 WP 定向测试 PASS
- [ ] milestone：错误台账闭环（无第 3 次同类失败遗留）
- 状态：pending
- 门禁：所有定向测试 PASS

### 阶段 4：装配交付
- [ ] milestone：`.task_state/` + 调试残留全部清理
- [ ] milestone：全量测试 PASS
- [ ] milestone：patch 可干净 apply
- 状态：pending
- 门禁：全量测试 PASS + patch 可干净 apply

---

## 关键问题
1. [开放性问题 1，影响方案选择]
2. [开放性问题 2]

## 已做决策

> 每条决策给一个稳定 ID（D-001 起递增），便于在 progress.md checkpoint / findings.md / 错误台账中反向引用。

| ID | 时间 | 决策 | 理由 | 影响范围 | 触发回流时回到此处审视 |
|----|------|------|------|---------|------|
| D-001 |      |      |      |         |      |

## 错误台账（三次失败协议）

> 每条错误给一个稳定 ID（E-001 起递增）。`关联 checkpoint` 指向 progress.md 中触发该错误的具体 checkpoint 时间戳；`关联决策` 指向相关 D-NNN（若该错误源于某个决策的副作用）。

| ID | 错误摘要 | 第几次 | 尝试方案 | 解决/状态 | 关联 checkpoint | 关联决策 |
|----|------|---------|---------|---------|---------|---------|
| E-001 |      | 1       |         |         |         |         |

> 同一错误第 3 次出现 → 停下，质疑假设，重读目标，必要时拆分阶段或求助用户。

## 备注
- 阶段状态流转：pending → in_progress → complete
- 重大决策前重读本文件「目标」「成功标准」段
- 外部网页 / 搜索内容不写本文件，只进 findings.md
- 分步动作不写本文件，全部走 TodoWrite

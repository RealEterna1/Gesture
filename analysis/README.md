# 技术层：离线评分与评估

这个目录只做一件事：把 App 导出的 JSON 变成“本人 vs 冒用者”的分数、阈值和错误率。

不依赖 App 源码，不需要新数据，只依赖 Python 3.10+ 和 numpy。

## 目录

```
analysis/
├─ auth_eval.py              主程序：加载、特征、DTW、融合、FAR/FRR/EER、SVG
├─ selftest.py               自检：确认 DTW / 特征 / EER 计算没有写错
├─ fixtures/
│  ├─ make_fixture.py        生成“明确标注 synthetic”的假数据
│  ├─ synthetic_separable.json
│  └─ synthetic_random.json
├─ legacy/                   旧脚本（归档，不参与流程）
└─ out/                      所有输出，按 run 分目录
```

## 快速自检

```powershell
$py = "C:\Users\lenovo\AppData\Local\Programs\Python\Python312\python.exe"

# 1) 生成假数据
& $py analysis\fixtures\make_fixture.py

# 2) 跑自检（应全部 PASS）
& $py analysis\selftest.py

# 3) 跑“可分”假数据：behaviour EER 应接近 0，shape EER 应接近 0.5
& $py analysis\auth_eval.py --input analysis\fixtures\synthetic_separable.json `
    --gesture G1 --outdir analysis\out\separable --assume-target-other

# 4) 跑“不可分”假数据：所有模式 EER 应接近 0.5
& $py analysis\auth_eval.py --input analysis\fixtures\synthetic_random.json `
    --gesture G1 --outdir analysis\out\random --assume-target-other
```

这两组假数据只是**代码测试**，不能当实验结果写进论文。

## 真实 pilot 怎么跑

```powershell
& $py analysis\auth_eval.py `
    --input data\pilot\*.json `
    --gesture G1 `
    --outdir analysis\out\pilot `
    --assume-target-other
```

如果 App 里的 `notes` 没写 `target=P02`，用 manifest：

```powershell
& $py analysis\auth_eval.py --input data\pilot\*.json --gesture G1 `
    --outdir analysis\out\pilot --manifest admin\pilot\manifest_filled.csv
```

## 输入要求

每个 JSON 至少包含：

- `subject_id`：谁在画；
- `gesture_id`：手势编号，两个人必须一致；
- `condition`：`genuine` 或 `mimic`；
- `strokes[].points[]`：每个点有 `t`、`x`、`y`、`p`。

模仿样本必须能确定“模仿的是谁”，优先级：

1. `notes` 里的 `target=P02`；
2. `--manifest` 指定的 CSV；
3. 两人模式 `--assume-target-other`（只有一个其他被试时才可用）。

## 输出

每个 run 目录下：

| 文件 | 内容 |
|---|---|
| `features.csv` | 每个样本的聚合特征，便于检查压力/速度是否正常 |
| `scores.csv` | 每个样本在各模式下的分数与是否接受 |
| `metrics.json` | EER、置信区间、AUC、阈值、样本数、警告 |
| `score_distribution.svg` | 本人 vs 冒用的分数分布 + 阈值线 |
| `det_curve.svg` | DET 曲线 |

## 两种判定模式

- `gate`：先过形状门（默认接受 95% 本人），再用行为分判；
- `weighted`：形状分和行为分各自标准化后加权成一个分数。

另外单独输出 `shape`（只看形状）和 `behaviour`（只看行为），用于消融。

## 指标定义

- 分数越低越像本人；
- 接受条件：`score <= threshold`；
- `FAR`：冒用样本被接受的比例；
- `FRR`：本人样本被拒绝的比例；
- `EER`：FAR 与 FRR 相等时的错误率。

## 必须知道的限制

- 2 人 pilot 的 EER 只能说明“管线是否工作”，不能作为论文结论；
- 冒充样本少于 20 条时，程序会打印 `pilot only` 警告；
- 阈值是在同一批数据上扫描出来的，pilot 阶段只能用于调试；
- 正式结果需要跨会话、更多被试，并固定阈值规则后再报。

## 怎么人工确认结果没算错

1. `features.csv` 里 P01 与 P02 的压力均值应明显不同（合成数据里约为 0.46 vs 0.24）；
2. `scores.csv` 里模仿样本的分数应整体高于本人样本；
3. `synthetic_random.json` 的 EER 应接近 0.5，如果显著低于 0.5，说明有数据泄漏或标签用错；
4. `selftest.py` 全部 PASS；
5. 打开两个 SVG，阈值线应落在两组分布之间，而不是把所有样本都判成同一类。

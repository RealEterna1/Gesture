# Touchscreen Gesture Authentication — FYP Workspace

毕设：平板 + 主动笔的触屏手势认证。两段式：形状门 + 逐笔行为相似度 + 阈值判定。手指输入的压力值是接触面积代理，不可用；正式数据统一用主动笔。

## 目录地图

| 目录 | 用途 | 是否进 git |
|---|---|---|
| `admin/` | FYP 官方文件、CA1 材料、伦理与导师记录、pilot 协议与同意书 | 是 |
| `pilot_app/` | 采集 App 全部内容：`source/` 源码、`release/` APK、`build_env/` Android SDK | 源码是；其余否 |
| `analysis/` | 离线评分与评估（Python + numpy） | 是；`out/` 否 |
| `data/` | 所有采集数据：`raw/`、`processed/`、`pilot/` | 否 |
| `literature/` | 文献索引与简介 | 是 |

App 相关的东西全部在 `pilot_app/` 下，根目录不再单独出现 SDK 或构建产物：

```
pilot_app/
├─ source/       Flutter 源码
├─ release/      可直接安装的 APK
└─ build_env/    Android SDK 与 cmdline-tools
```

根目录的 `app/` 已删除；App 只保留 `pilot_app/` 这一份。

## 重新构建 App

```powershell
$env:ANDROID_HOME="D:\Gesture\pilot_app\build_env\android-sdk"
$env:ANDROID_SDK_ROOT=$env:ANDROID_HOME
$env:FLUTTER_STORAGE_BASE_URL="https://storage.googleapis.com"

cd D:\Gesture\pilot_app\source
& "D:\flutter\bin\flutter.bat" build apk --release
```

构建产物在 `pilot_app\source\build\app\outputs\flutter-apk\app-release.apk`，复制到 `pilot_app\release\` 即可。

## 端上认证演示

App 现在不只是采集器，已经能在端上完成：

1. 首页填好被试编号和手势编号（G1~G10）；
2. 点“注册模板”，连续采 10 次本人手势；
3. 模板生成后，点“验证”，采 1 次，显示形状距离、行为距离和通过/拒绝；
4. 模板保存在 App 的 `documents/templates/` 下，重启不丢。

判定规则：形状距离和行为距离都不超过各自阈值才通过。阈值目前由注册样本自动估计，pilot 之后可以用离线脚本算出的 EER 阈值替换。

注意：当前形状层是“与该用户注册模板比对”，不是自动识别 G1/G2/G3；手势编号只是选择模板的标签。注册/验证样本不会进入样本数据，不会污染正式采集数据。

首页的“数据管理”把样本、模板、验证记录合并在一个页面，但三类数据彼此独立：

- 样本：只包含“开始采集”产生的原始样本；
- 模板：查看笔数和两个阈值、修改阈值、删除；
- 验证记录：每次验证的结果，记录里自带 `raw_sample`（原始轨迹），不会出现在样本页；
- 右上角“导出全部”：生成一个 JSON，同时包含 `samples`、`templates`、`verification_logs` 三部分；
- 右上角“清空全部”：一次删除样本、模板、验证记录。

每次验证都会自动写一条记录（时间、被试、手势、形状距离/阈值、行为距离/阈值、通过/拒绝、原因），用于后面统计端上 FAR/FRR。

## 快速开始（分析）

```powershell
$py = "C:\Users\lenovo\AppData\Local\Programs\Python\Python312\python.exe"

# 自检：DTW、特征、EER 计算
& $py analysis\selftest.py

# 用假数据跑完整管线
& $py analysis\fixtures\make_fixture.py
& $py analysis\auth_eval.py --input analysis\fixtures\synthetic_separable.json `
    --gesture G1 --outdir analysis\out\separable --assume-target-other
```

假数据只用于验证代码，不能作为实验结果。

## Pilot 流程

1. 读 `admin/pilot/protocol.md`；
2. 用平板采集，按协议填写 `subject_id`、`gesture_id`、`condition`、`notes`；
3. 导出到 `data/pilot/`；
4. 运行：
   ```powershell
   & $py analysis\auth_eval.py --input data\pilot\*.json --gesture G1 `
       --outdir analysis\out\pilot --assume-target-other
   ```
5. 看 `analysis/out/pilot/` 里的 `score_distribution.svg`、`metrics.json`。

## 约定

- 真实被试数据不进 git；只用编号，不写姓名。
- 所有阈值只能在训练/验证数据上定，不能用测试集调参。
- 2 人 pilot 的 EER 只作可行性参考，论文主结果需要更多被试与跨会话数据。

# 触屏手势认证（Touchscreen Gesture Authentication）文献索引

整理日期：2026-11-15

你的方向：**形状/手势类别识别（硬门槛）+ 速度/压力等行为动力学相似度打分 + 阈值判定**，目标平台为**平板 + 主动笔**（手指仅作对照，因为指尖压力是接触面积代理），评估要求 open-set、跨会话、FAR/FRR/EER。

使用说明：

- ⭐ = 与你的方案最接近、建议优先精读；📄 = 综述；📊 = 数据集。
- 链接均为检索时实际存在的页面；ACM / IEEE 全文通常需要校园网或机构订阅，开放版（arXiv / 作者主页 PDF / USENIX）已尽量附上。
- 每条给 2~3 句中文简介，并说明「和你的想法哪里一样、哪里不一样」。
- 建议阅读顺序见文末。

---

## 一、必读：已经实现了「形状 + 行为特征」的方案（先看这一组）

### ⭐ 1. GEAT — Secure Unlocking of Mobile Touch Screen Devices by Simple Gestures: "You can see it but you can not do it"
- 作者/年份/发表处：Muhammad Shahzad, Alex X. Liu, Arjmand Samuel；MobiCom 2013（ACM 移动计算与网络年会）
- 链接：<https://www.cse.msu.edu/~alexliu/publications/TouchAuthentication/TouchAuthentication_MOBICOM2013.pdf>
- 简介：提出 GEAT，核心主张就是「不只认证画了什么，而是认证**怎么画**」：即使攻击者看到了手势，也复现不了执行方式。提取 7 类特征——速度大小、设备加速度、单笔耗时、笔间间隔、笔画位移大小、笔画位移方向、速度方向；用 50 名志愿者、15009 条手势样本评测，3 个手势 + 25 个训练样本时平均 EER 约 0.5%。
- 与你的关系：**这是和你想法最像、且已经完整实现的早期工作**。它同样把「轨迹形状」和「执行动力学」放在一个系统里；差别是它把两类特征直接送进分类器，而你打算做成「形状硬门槛 + 行为相似度打分」的两段式，并且它跑在 Windows Phone 上、没有用压力轴。

### ⭐ 2. 基于行为生物特征的自由手势认证增强方案（StrokeFG）
- 作者/年份/发表处：2025 年中文论文（南开大学团队主页公开 PDF）
- 链接：<https://cssnku.github.io/uploads/publications/cybersec25-biometric.pdf>
- 简介：用**两阶段认证**增强自由手势密码：先用手势轨迹 + DTW 与模板池匹配，判断形状是否一致；通过后再提取行为生物特征向量，以「输入特征与模板特征的差值向量」作为认证器输入，判断是否同一用户。文中还与 DTW、Protractor 等基线在等错误率条件下做了对比。
- 与你的关系：**架构几乎就是你的两模块串联方案**（形状匹配 → 行为相似度判定），而且明确用 DTW 做形状层。差别是它面向手机自由手势，你要做的是平板 + 主动笔、逐笔评估、并给出跨会话 FAR/FRR/EER。强烈建议按它的实验设计（阈值怎么定、报告哪些指标）来对照。

### ⭐ 3. Securing Gesture Passwords Against Shoulder Surfing Using Behavioral Features
- 作者/年份/发表处：Eunyong Cheon, Ian Oakley；CHI EA 2025（CHI 扩展摘要，8 页）
- 链接：<https://dl.acm.org/doi/10.1145/3706599.3720021>
- 简介：直接研究「用手势密码 + 行为特征来抵抗肩窥攻击」。系统包含多层手势识别（multilayered gesture recognition）、分类器设计与安全性实验，场景是先让用户自创手势密码、再反复复制他人手势来模拟攻击者。
- 与你的关系：这是**你论文动机的最新、最直接的支撑文献**（"看见也会画、但画不出同样的方式"）。它的实验范式（自创手势 + 复制他人手势作为攻击样本）可以直接借用到你的数据采集协议里。

### ⭐ 4. SMAUG: Secure Mobile Authentication Using Gestures
- 作者/年份/发表处：Christian A. Gorke, Frederik Armknecht；arXiv 2017（预印本）
- 链接：<https://arxiv.org/abs/1708.04871>
- 简介：只用手机自带传感器（触摸屏 + 陀螺仪 + 加速度计）实现手势认证，支持自由手势、多点触控、任意笔数。它明确把「手势形状（知识因子）」和「输入方式（生物特征因子）」结合成双因子；在最强攻击模型下（攻击者已知压力、速度、旋转、加速度等信息），首次认证正确率 77%、三次内 99%，冒充者检出率 97%。
- 与你的关系：**「形状 + 行为」双因子这一表述基本就是你的框架**，而且它做了「攻击者知道行为特征」的压力测试，这一点可以作为你讨论 FAR 可信度的参考。差别是它融合多传感器且用分类器，不强调单笔/逐笔的相似度打分。

### ⭐ 5. Multi-touch Authentication Using Hand Geometry and Behavioral Information
- 作者/年份/发表处：Yunpeng Song, Zhongmin Cai, Zhi-Li Zhang；IEEE S&P 2017
- 链接：<https://ieeexplore.ieee.org/document/7958587>
- 简介：用多点触控时的手部几何（触点面积、形状等）与行为信息（如每笔平均速度、触点面积均值/标准差）融合做认证。实验表明行为特征单独会随时间漂移，与几何特征融合后既能抵抗行为变化又能保持区分度。
- 与你的关系：给出「多笔 / 多点手势」下**逐笔特征怎么定义**的具体例子（velocity、tool mean、tool deviation），对你设计逐笔速度、压力特征很有参考价值；也提醒你注意「同一人跨时间行为漂移」这个必须处理的点。

### ⭐ 6. Under Pressure: Effectiveness and Usability of the Apple Pencil as a Biometric Authentication Tool
- 作者/年份/发表处：Elina van Kempen, Zane Karl, Richard DeAmicis, Qi Alfred Chen（UC Irvine）；USEC 2024（NDSS 研讨会）
- 链接：<https://www.ndss-symposium.org/wp-content/uploads/usec2024-56-paper.pdf>
- 简介：30 名被试，用 Apple Pencil 采集手写过程的动态属性（含压力等笔传感器数据），比较时间序列分类模型在 text-dependent / text-independent 及不同输入上的准确率，并**专门评估了手写伪造（forgery）**：模型准确率多数超过 99%，但伪造成功率最高达 21.3%。
- 与你的关系：设备形态接近（平板 + 笔），你现在也统一用主动笔，这篇可以作为「压力可用时能达到什么效果」的直接对照；它给出的「高准确率 ≠ 抗伪造」教训仍然适用。你做 mimic 攻击样本、报告 FAR 时可以直接对标它的设定；它没有做「手势类别硬门槛」这一层。

---

## 二、触屏行为特征与持续认证的基础工作（特征怎么来的）

### 7. Touchalytics: On the Applicability of Touchscreen Input as a Behavioral Biometric for Continuous Authentication
- 作者/年份/发表处：Mario Frank, Ralf Biedert, Eugene Ma, Ivan Martinovic, Dawn Song；IEEE TIFS 2013（arXiv 2012）
- 链接：<https://arxiv.org/abs/1207.6231> ｜ DOI: <https://doi.org/10.1109/TIFS.2012.2225048>
- 简介：触屏行为认证的奠基工作。从原始触摸日志提取 30 个行为特征（速度、加速度、压力、接触面积、轨迹曲率等），41 名用户实验；同会话 EER 中位数 0%、跨会话 2%~3%、注册一周后低于 4%。作者自己指出它不适合作为长期单独认证手段，更适合作为多模态的一部分或延长锁屏时间。
- 与你的关系：**你的特征集基本可以从这 30 个特征里挑**，尤其是压力、速度、曲率；它的跨会话衰减结论也是你「必须做跨会话评估」的最有力依据。

### 8. Towards Continuous and Passive Authentication via Touch Biometrics: An Experimental Study on Smartphones
- 作者/年份/发表处：Hui Xu, Yangfan Zhou, Michael R. Lyu；SOUPS 2014（USENIX）
- 链接：<https://www.usenix.org/system/files/conference/soups2014/soups14-paper-xu.pdf>
- 简介：研究如何对多种触摸操作（滑动、点击等）建模并做持续被动认证，并论证触摸操作作为生物特征的可区分性与持久性。给出了特征构造和在线认证流程的完整细节。
- 与你的关系：讲清楚了「一次触摸 = 一条带时间戳的点序列」怎么变成特征向量，是写你特征提取章节时最好引用的规范来源之一。

### 9. HMOG: New Behavioral Biometric Features for Continuous Authentication of Smartphone Users
- 作者/年份/发表处：Zdeňka Sitová 等；IEEE TIFS 2016（arXiv 2015）
- 链接：<https://arxiv.org/abs/1501.01199>
- 简介：提出 HMOG（Hand Movement, Orientation, and Grasp）特征集——从触摸时的手部微动作、手机朝向、握持方式中提取行为特征，并配合 100 人数据集验证持续认证效果。
- 与你的关系：如果你的平板方案想补充「握持姿态 / 设备朝向」这类辅助特征，这里是标准做法；若只做触摸+笔，也可作为对比基线。

### 10. SwipeFormer: Transformers for Mobile Touchscreen Biometrics
- 作者/年份/发表处：Paula Delgado-Santos, Rubén Tolosana 等（含 Julian Fierrez）；Expert Systems with Applications 2024
- 链接：<https://eprints.soton.ac.uk/489419/>（开放 PDF：<https://eprints.soton.ac.uk/489419/1/1-s2.0-S0957417423020390-main.pdf>）
- 简介：当前滑动类触屏生物认证的代表性 SOTA：Transformer 特征提取 + 相似度计算两模块，在无约束场景下 Android / iOS 上 EER 分别为 6.6% / 3.6%，在公开库 Frank DB、HuMIdb 上为 11.0% / 5.0%。作者开源了代码，可作你的强基线。
- 与你的关系：**「特征提取 + 相似度计算」的两模块结构和你一致**，EER 数值可以作为你答辩时的性能参照；但它只认证滑动，不认证手势类别，也没有压力轴。

### 11. Effect of context in swipe gesture-based continuous authentication on smartphones
- 作者/年份/发表处：arXiv 2019
- 链接：<https://arxiv.org/html/1905.11780v1>
- 简介：基于 HMOG 数据集分析使用场景（阅读、打字、地图导航）对滑动认证性能的影响，说明同一用户在不同情境下行为分布会漂移。
- 与你的关系：提醒你在实验设计里控制/记录「采集情境」，这也是跨会话 EER 波动的解释来源之一。

---

## 三、手势密码 / 自由手势的安全性与可用性（论证「为什么要加行为层」）

### 12. Quantifying the Security of Graphical Passwords: The Case of Android Unlock Patterns
- 作者/年份/发表处：Sebastian Uellenbeck, Markus Dürmuth, Christopher Wolf, Thorsten Holz；ACM CCS 2013
- 链接：<https://dl.acm.org/doi/10.1145/2508859.2516700>
- 简介：通过大规模用户研究测量真实用户选择的九宫格图案，用马尔可夫链模型量化图案强度，发现用户选择高度偏置（左上角、三点长直线极常见），有效密码空间远小于理论值。
- 与你的关系：这是你「只认形状不够、需要行为特征」的核心论据——形状本身容易被猜、被肩窥、被油污痕迹泄露。引用它可以把研究动机写得很扎实。

### 13. User-Generated Free-Form Gestures for Authentication: Security and Memorability
- 作者/年份/发表处：MobiSys 2014（ACM）
- 链接：<https://www.cs.helsinki.fi/u/ttonteri/pub/mobisys2014.pdf>
- 简介：63 名被试采用 generate–test–retest 范式，自创自由手势并在一段时间后重测记忆与安全性；一半人用单指、一半用多指，系统分析了手势的可记忆性与可猜测性。
- 与你的关系：如果你要让用户**自创手势**（而不是从固定集合里选），这篇是必须引用的设计依据：手势长度、笔数、复杂度如何影响记忆与安全。

### 14. Free-Form Gesture Authentication in the Wild
- 作者/年份/发表处：CHI 2016（ACM）
- 链接：<https://dl.acm.org/doi/pdf/10.1145/2858036.2858270>
- 简介：把自由手势密码放到真实使用场景（in the wild）中做实地研究，考察长期使用下的可用性与安全性，而不只是实验室里的单次实验。
- 与你的关系：为你的评估协议提供「真实使用 vs 实验室」的讨论素材；也说明为什么跨会话、多天采集很重要。

### 15. Improving Security of Free-Form Gesture Based Authentication
- 作者/年份/发表处：UNIST 学术库公开 PDF（韩国蔚山科学技术院）
- 链接：<https://scholarworks.unist.ac.kr/bitstream/201301/86428/2/200000865434.pdf>
- 简介：研究手势密码在「等错误率阈值」下遭遇字典式猜测攻击的风险：DTW 可破解约 54.18%、Protractor 约 58.37% 的手势，说明仅报告 EER 会高估安全性，需要更严格的阈值与攻击评估。
- 与你的关系：**你定阈值时必须读这篇**——它直接告诉你「EER 好看不代表安全」，也支持你「用 DTW 做形状相似度」的选择（DTW 比 Protractor 更难被猜中）。

---

## 四、平板 + 主动笔 / 手写动力学（手指作为对照）

### 16. Dynamics of Digital Pen-Tablet: Handwriting Analysis for Person Identification Using Machine and Deep Learning Techniques
- 作者/年份/发表处：Tahmid Hasan, Md. Abdur Rahim, Jungpil Shin 等；IEEE Access 2024（vol. 12, pp. 8154–8177）
- 链接：<https://www.semanticscholar.org/paper/Dynamics-of-Digital-Pen-Tablet:-Handwriting-for-and-Hasan-Rahim/4a94fac3fccf0adc01b70090c1860160f57f8d93>
- 简介：用数字化手写板采集 48 名被试的手写动力学（笔压、速度、笔倾角等），比较机器学习和深度学习模型在「人身份识别」上的表现，论证笔式输入作为生物特征的实际可行性。
- 与你的关系：**你的设备形态（笔 + 平板）与它一致**，可以借鉴它处理压力/倾角序列的方式；差别是它做的是手写内容识别，不做手势类别门槛。

### 17. 补充：压力值到底可不可信（工程可行性）
- 链接（Android 官方文档）：<https://source.android.google.cn/docs/core/interaction/input/touch-devices>
- 简介：Android 对触摸设备 `pressure` 字段的规定：取值 0.0~1.0 的归一化「大概压力」；当驱动设置 `touch.pressure.calibration = none` 时，触摸期间会**固定上报 1.0**（悬停为 0.0）。
- 与你的关系：这正好解释了你实测 iQOO 15 压力恒为 1.0 的现象——不是 App 的问题，而是该机型没有压力轴。你后来又发现华为手指的压力随接触面积变化，说明指尖读数只是面积代理；最终统一用主动笔，压力才是真实信号。写论文时要把这个筛选过程写进「设备可行性」。

---

## 五、综述（用来快速搭框架、找漏引）

### 📄 18. Touch-dynamics based Behavioural Biometrics on Mobile Devices – A Review from a Usability and Performance Perspective
- 作者/年份/发表处：Ellavarason 等；ACM Computing Surveys 2020
- 链接：<https://dl.acm.org/doi/pdf/10.1145/3394713>
- 简介：从可用性与性能两个视角系统梳理移动设备上的触摸动力学认证，包括特征、模型、数据集与评估指标的横向比较，并指出该领域尚未解决的问题。
- 与你的关系：**开题/相关工作章节的主干综述**，它整理的指标口径（FAR/FRR/EER、会话划分）可直接采用。

### 📄 19. Authentication of Smartphone Users Using Behavioral Biometrics
- 作者/年份/发表处：Abdulaziz Alzubaidi, Jugal Kalita；IEEE Communications Surveys & Tutorials 2016
- 链接：<https://ieeexplore.ieee.org/document/7423666> ｜ 开放版：<https://arxiv.org/pdf/1911.04104>
- 简介：行为生物认证的经典综述，覆盖触摸、手势、击键、步态等模态，讨论被窃/被扣押设备的风险、持续认证概念，以及各方法的特征、数据集与评估方式。
- 与你的关系：帮你把「手势认证」放进行为生物认证的大图里，前言部分引用很稳。

### 📄 20. A Survey on Behavioral Biometric Authentication on Smartphones
- 作者/年份/发表处：arXiv 2018
- 链接：<https://arxiv.org/pdf/1801.09308v1.pdf>
- 简介：专门用一章定义「手势类认证」：手势是触摸屏上的手绘形状，包含一笔或多笔（stroke），每笔是**一串带时间戳的连续点**，每个点是有序坐标对。也总结了各方法的特征与模型。
- 与你的关系：**术语定义可以直接引用**（尤其 "stroke = sequence of consecutive timed points"），写数据模型和 JSON 结构时很好用。

### 📄 21. 基于移动智能终端交互行为的持续身份认证技术综述
- 作者/年份/发表处：中文期刊《信息通信技术与政策》（中国信通院）
- 链接：<http://ictp.caict.ac.cn/CN/article/downloadArticleFile.do?attachType=PDF&id=1172>
- 简介：中文综述，按交互数据类型分类（点击、滑动等），明确指出可从每个触屏动作中提取时间戳、手指压力、接触面积等特征用于持续认证。
- 与你的关系：中文写作时的规范引用来源，也便于向国内评审解释「压力是可用特征」这件事。

### 📄 22. 基于触屏行为的智能移动设备身份认证（中文 PDF）
- 链接：<http://computing.hit.edu.cn/_upload/article/files/e1/2c/b9cbb71b48f88c54e4db5ef849a4/d9713339-b9e0-4b35-a08c-f34b33e2dc03.pdf>
- 简介：中文论文，梳理基于触屏行为的身份认证研究，转述了 Touchalytics 的结论（单次划屏 EER 约 13%，11~12 次划屏后显著下降），并对特征与模型做了分类。
- 与你的关系：可作为中文背景资料；注意它引用的数字与原文口径略有差异，正式引用请回到原文核对。

---

## 六、公开数据集（想复现或做对比实验就用这些）

### 📊 23. Touchalytics 数据集
- 链接：<http://www.mariofrank.net/touchalytics/>
- 简介：Touchalytics 论文配套数据，41 名用户、真实手机滑动轨迹原始日志（含时间戳、坐标、压力、接触面积）。是该方向最常用的公开库之一。
- 与你的关系：可用于验证你的特征提取代码是否正确，也可作为「跨用户/跨会话」基线的对照数据。

### 📊 24. HMOG 数据集
- 链接：<http://www.cs.wm.edu/~qyang/hmog.html>
- 简介：100 名志愿者、每人约 2~6 小时，约 6GB；包含加速度计、陀螺仪、磁力计、原始触摸事件、点击/缩放/滚动/滑动手势、虚拟键盘按键等 9 类数据，仅需签署协议即可申请。
- 与你的关系：如果你想把「多模态」作为扩展方向，这是现成的数据；但它是手机数据，没有你需要的主动笔压力轴。

### 📊 25. HuMIdb（Human Mobile Interaction database）
- 链接：<https://arxiv.org/abs/2005.13655>（BeCAPTCHA 论文，首次公开介绍该库）
- 简介：目前规模最大的移动交互多传感器数据库之一：600 名用户、5 个会话、14 类传感器信号、超过 5GB，在无监督自然使用场景下采集。
- 与你的关系：适合做「自然场景 / 跨会话」的大规模对照；同样不含平板笔压力数据，可用来论证你的数据集填补了什么空白。

---

## 七、和你想法最像的工作对比（给导师看的一页纸）

| 工作 | 年份 | 形状/类别判定 | 行为特征 | 是否已实现 | 与你的主要差异 |
|---|---|---|---|---|---|
| GEAT | 2013 | 有（形状相关特征一并入分类器） | 速度、加速度、笔时、笔间间隔 | 是（Windows Phone，15009 样本） | 单段分类器，无压力轴，非两段式 |
| StrokeFG | 2025 | 有（DTW 轨迹匹配，硬门槛） | 行为特征向量 + 差值向量认证器 | 是（手机自由手势） | 手机、无主动笔压力；未强调多笔逐笔评估 |
| CHI EA'25 | 2025 | 有（多层手势识别） | 行为特征 | 是（实验原型） | 目标是抗肩窥，未做开放集跨会话 FAR/FRR |
| SMAUG | 2017 | 有（自由手势、任意笔数） | 触摸 + 陀螺仪 + 加速度 | 是（预印本） | 多传感器融合，非相似度阈值式 |
| S&P'17 多触点 | 2017 | 部分 | 速度、触点面积统计 | 是 | 偏手部几何，非「手势类别 + 逐笔打分」 |
| Apple Pencil | 2024 | 无（内容是手写文本） | 笔压等动态属性 | 是（30 人，含伪造） | 没有手势类别门槛；伪造成功率 21.3% 值得警惕 |
| **你的方案** | — | 手势类别硬门槛 | 速度、压力、节奏，多笔逐笔 | 待实现 | 平板 + 主动笔真实压力轴；open-set 跨会话；FAR/FRR/EER |

结论（讨论要点）：

1. **「形状 + 行为」不是新点子，但「形状硬门槛 + 逐笔行为相似度 + 阈值」在平板笔输入上仍说得通**——最接近的是 StrokeFG（两阶段）与 GEAT（形状+动力学），你可以明确说自己是在平板笔输入、多笔逐笔、开放集跨会话评估上做的改进与实证。
2. **压力必须证明是真信号**：Touchalytics 的 30 个特征里压力权重不低；你实测手机手指压力恒为 1.0，华为手指压力随接触面积变化（是面积代理），而平板 + 主动笔测得 255Hz、0.03~0.64、40~60 级。正式数据统一用主动笔，压力才可作为主特征；手指只作为对照，用来解释为什么需要笔。
3. **只报 EER 不够**：UNIST 那篇显示等错误率阈值下字典攻击可破解一半以上手势；CHI EA'25 与 Apple Pencil 都强调模仿/伪造攻击。你的 mimic 数据（G2）正好补上这块。
4. **可复现基线建议**：Touchalytics 特征 + DTW 作为形状层与相似度层的最小基线，再上 SwipeFormer 这类学习式方法做对比。

---

## 建议阅读顺序

1. 先建立框架：18（综述）→ 7（Touchalytics）→ 19（行为生物认证综述）
2. 再看「已经有人这么做了」：1（GEAT）→ 2（StrokeFG）→ 4（SMAUG）→ 3（CHI EA'25）
3. 然后定实验协议：13（手势自创与记忆）→ 15（阈值与字典攻击）→ 6（笔 + 伪造）
4. 最后定特征与基线：5（逐笔特征定义）→ 10（SwipeFormer 基线）→ 23/24/25（数据集）

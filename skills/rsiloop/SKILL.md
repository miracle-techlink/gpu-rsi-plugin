---
name: rsiloop
description: 自我进化闭环——给定一个可机器判定的目标函数(evaluator),让 agent 自主迭代变异配置、测速打分、保留优胜、记录谱系,直至收敛。用于"优化下载/编译/安装/训练吞吐"等有硬指标的任务,前置一次目标确认后零人工介入。用户说"自主优化""自己迭代""不要介入""RSI""进化"时使用。
---

# RSI Loop —— 自我进化闭环协议

## 核心思想

agent 是变异算子 + 选择器,evaluator 是唯一可信的环境。**禁止主观判断快慢,一切以 evaluator 输出的 score 为准。** 这和排序 demo 的区别只在于:这里的基因型是配置文件/环境变量/命令参数,不是代码。

## 启动前置(与 onboard 命令配合时,这些已由第 1 步问答提供)

若用户直接调用本 skill(非经 /onboard),先用一次 AskUserQuestion 问清:
1. 优化目标是什么(下载速度/编译时间/训练吞吐/其他可判定指标)?
2. 怎么机器判定好坏(已有脚本/需要我从模板生成)?
3. 机器约束:能否 sudo、网络位置(国内/海外)。

之后禁止再提问。

## 脚手架生成(每个 domain 一份)

在 `~/rsi/<domain>/` 生成:

```
~/rsi/<domain>/
├── evaluator.sh          ← 目标函数(从 templates/ 拷贝适配)
├── CLAUDE.md             ← 进化协议(把本文件的"每轮迭代协议"写进去)
├── genome.env            ← 当前基因型:key=value 形式的配置
├── apply.sh              ← 把 genome.env 应用到真实系统(改源/改环境变量/改参数)
├── population/           ← 变异个体:gen<N>_<name>.env + 评估结果 .json
├── lineage/              ← 谱系:每代决策记录 + FINAL.md
├── selector.sh           ← 从 assets/ 拷贝:挑最高分个体替换 genome.env
└── reporter.py           ← 从 assets/ 拷贝:谱系报告 + history.md
```

**apply.sh 是关键设计**:evaluator 评的是"应用该配置后的真实系统行为",所以每个变异必须先 apply 再测。apply 必须幂等且带备份(改系统文件先 `cp x x.bak`),失败的变异 apply.sh 负责回滚。

## 每轮迭代协议(写进各 domain 的 CLAUDE.md)

1. **评估现状**:`bash evaluator.sh` 跑当前 genome,记录 baseline score
2. **提出变异**:看 population/ 已有分数,决定变异方向(参数级 → 策略级;源替换 > 线程数微调)
3. **生成个体**:写 `population/<gen>_<name>.env`(只含与父代的 diff + 全量拷贝)
4. **评估个体**:apply 该配置 → `bash evaluator.sh` → 结果 JSON 加 `file`/`parent` 字段存 `population/<gen>_<name>.json` → 恢复或保留配置
5. **选择**:score 显著高于 baseline(>10%,小耗时场景有噪声)才替换 genome.env,写 `lineage/<gen>.md`(变异类型、分数变化、理由)
6. **复盘**:规律追加 `MEMORY.md`

## 硬约束

- 校验失败(ok=false:下载损坏/编译产物跑不通/哈希不匹配)的变异直接废弃,保留 .json 作失败样本
- 禁止修改 evaluator.sh —— 改判据等于作弊
- 每 domain 最多 8 轮;连续 2 轮无提升 → 必须策略级变异(换源/换工具,非调参);仍无效 → 收敛,写 FINAL.md
- 覆盖系统文件前必须备份,变异失败必须回滚到上一优胜配置
- score 噪声:小耗时(<5s)场景至少测 2 次取均值,数量级差异才作选择依据
- 收敛后必须回写 LOCAL_FACTS.md——没有"先验 vs 实测"差异也要写一句"本轮先验全部成立",不许省略这一步

## 终止

达到 templates/ 中该 evaluator 的参考上限,或轮数/停滞条件触发,写 `lineage/FINAL.md`(谱系、总提升、最优配置、可迁移规律),把最优配置固化到真实生效位置,停止。

## 模板使用

- `templates/download/` — 下载流水线:计时 + sha256 校验一票否决
- `templates/compile/` — 编译:计时 + 产物冒烟测试一票否决
- `templates/install/` — 包安装:计时 + import 验证一票否决
- 用户任务不匹配模板时:按"计时 + 正确性一票否决 + 输出单行 JSON"三要素现场写 evaluator,写之前先向用户确认判据(这是启动前置的一部分,不算额外交互)

## 参考文档(变异空间的知识库,按需查阅)

提出变异时不知道有哪些可调的维度,按场景查:

- `references/cloud-gpu-setup.md` — 云端环境配置结构化手册(含"为什么"原理):镜像源/aria2c/HF Xet vs hf_transfer/BBR/ccache,关键决策点都附原理。**下载/安装/编译 domain 的变异空间主要来自这里。**
- `references/pc-ubuntu-setup.md` — PC 台式机补充:驱动/.run 安装、包冲突(libtbb)、NVML vglusers 坑、CUDA 多版本共存、ROS2、Colmap。仅在裸机/台式机场景查。
- `references/originals/` — 两份手册的**原文逐字收录版**(已脱敏)。结构化摘要信息不够、需要完整上下文/原始命令/大纲时查这里。
- `references/scripts/` — **可执行脚本**(幂等可重跑):setup_apt_mirrors.sh / install_miniconda.sh / install_uv.sh / install_torch.sh(自动按 CUDA 选 wheel 通道)/ install_flash_attn.sh(自动查四元组)/ enable_bbr.sh / setup_ccache.sh / verify_all.sh(输出 JSON 供 evaluator 用)。基线搭建直接用,不必从手册抄命令。
- `references/topics/nccl-multinode.md` — 多机分布式:NCCL 环境变量、nccl-tests 验证、IB/RoCE 坑。训练通信瓶颈 domain 查这里。
- `references/topics/profiling-toolchain.md` — 性能剖析:nvtop/iostat/py-spy 概览 → nsys/ncu 算子级 → dataloader 参数。训练吞吐 domain 的定位方法论和变异空间。

用法:不要全文读入;按当前 domain 和变异方向定位到对应小节,提取具体参数值写进 genome.env。文档里的推荐值只是先验,**最终取舍由 evaluator 实测裁决**——推荐值也可能在你的网络上是错的。

## 固化:evaluator 实测结论回写 references(把闭环闭上)

references 是活文档,不是只读手册。每个 domain 收敛后,必须把本机实测结论回写,让先验随环境进化:

1. **回写位置**:不改 references/ 里的原始手册(那是跨机器通用的先验);在每个 domain 的 `~/rsi/<domain>/` 下建 `LOCAL_FACTS.md`,格式:
   ```
   ## <机器标识/日期>
   - 先验: <references 里的推荐值> → 实测: <本机结果> → 结论: <采纳/推翻/修正为新值>
   - 例: 先验 aria2c -x16 最快 → 实测本机 -x8 比 -x16 快 40%(镜像限流) → 修正为本机 -x8
   ```
2. **回写时机**:FINAL.md 写完后,把谱系里"先验 vs 实测"有差异的条目提炼进 LOCAL_FACTS.md。
3. **下次复用**:同一台机器重跑或换 domain 时,先读 LOCAL_FACTS.md 再读 references——本机实测 > 通用先验。
4. **跨机器推广**:若某条结论在多台机器上稳定复现(比如"阿里云内网源永远快于公网 tuna"),才允许追加到 references/<手册> 的"实测验证"区,并标注验证机器数。单台机器的结论永远不进公共手册。

这样 references 的演进路径是:静态先验 → 本机实测修正(LOCAL_FACTS) → 多机验证后的公共修正(references 实测验证区)。

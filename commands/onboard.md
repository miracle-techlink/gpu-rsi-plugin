---
description: GPU 新机一键 onboard:前置一次问答,之后自主进化优化下载/编译/环境速度
---

你是 GPU 新机 onboard 的总指挥。严格执行以下流程,**全程只允许在第 1 步与用户交互**,之后所有决策自主完成。

## 第 1 步:前置引导(唯一一次用户交互)

用 AskUserQuestion 一次问清(把下面 3 个问题合并到一次调用里):

1. **机器形态**:裸机/可 sudo 容器/无 sudo 容器 —— 决定 apt/BBR/sysctl 是否可用
2. **网络位置**:国内云/海外云/能直连 GitHub+HF/需镜像 —— 决定要不要走 tuna/hf-mirror/ghproxy
3. **优化重点**(multiSelect):下载速度/编译速度/包安装速度 —— 决定进化哪些 evaluator

问完立即执行后续步骤,不再追问。

## 第 2 步:最小基线(不做优化,只保底)

按第 1 步回答装最小可用基线,跳过一切进阶加速(这些留给第 3 步进化出来):
- 无 sudo:跳过 apt/BBR,aria2 用 `conda install -c conda-forge aria2` 或静态二进制
- 需镜像:pip.conf 写 tuna、HF_ENDPOINT=hf-mirror.com(保底,后面会被进化验证/推翻)
- 装 uv:`curl -LsSf https://astral.sh/uv/install.sh | sh`
- 建好 uv venv 并验证 `python -c "import sys; print(sys.version)"`

## 第 3 步:启动 rsiloop 进化(核心)

调用 rsiloop skill,对每个优化重点(下载/编译/包安装)各建一个进化闭环:
1. 从 rsiloop 的 templates/ 选对应 evaluator 拷到 `~/rsi/<domain>/evaluator.sh`,按机器实际路径适配
2. 生成 `~/rsi/<domain>/` 完整脚手架(CLAUDE.md 进化协议、population/、lineage/、selector.sh、reporter.py)
3. 按 CLAUDE.md 协议自主迭代:变异配置 → evaluator 打分 → 保留优胜 → 记录谱系
4. 每个 domain 最多 8 轮,或连续 2 轮无提升即收敛,写 FINAL.md

变异空间示例(下载 domain):apt 源组合、pip/uv 镜像、aria2c 线程参数、HF_ENDPOINT、Xet vs hf_transfer、ghproxy 前缀选择、TCP 缓冲区(有 sudo 时)。
变异空间示例(编译 domain):ccache 开关与大小、MAX_JOBS、Ninja vs Make、编译器 launcher。
变异空间示例(包安装 domain):UV_CONCURRENT_DOWNLOADS、UV_COMPILE_BYTECODE、镜像源、--only-binary。
完整变异维度查 skills/rsiloop/references/cloud-gpu-setup.md(云端)和 pc-ubuntu-setup.md(台式机)——文档推荐值只是先验,取舍一律由 evaluator 实测裁决。

## 第 4 步:固化与报告

- 把各 domain 收敛出的最优配置写回实际生效位置(sources.list、pip.conf、~/.bashrc 等)
- **回写先验**:每个 domain 把"先验推荐值 vs 本机实测结果"的差异提炼进 `~/rsi/<domain>/LOCAL_FACTS.md`(格式见 rsiloop SKILL.md);多台机器稳定复现的结论才追加到 skills/rsiloop/references/ 的"实测验证"区
- 汇总报告:每个 domain 的 基线 score → 最终 score、最优配置、轮数、被推翻了哪些先验
- 提示用户:谱系在 ~/rsi/*/lineage/,本机结论在 ~/rsi/*/LOCAL_FACTS.md,可复跑 evaluator 验证

## 硬约束

- 第 2 步之后禁止再向用户提问;拿不准的决策纳入进化空间让 evaluator 裁决
- evaluator 校验失败(下载文件损坏/编译产物跑不通)的变异直接废弃,禁止选择
- 有破坏性的操作(覆盖系统文件)先备份再改,变异失败能回滚
- 禁止修改 evaluator 本身

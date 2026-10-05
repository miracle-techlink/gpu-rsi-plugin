# gpu-rsi-plugin

GPU 新机 bringup 的自我进化系统:一次前置问答,之后 agent 自主迭代优化下载/编译/包安装速度,零人工介入。

## 与静态指南的本质区别

传统 bringup 手册(网络优化 → conda → uv → wheels → 加速进阶)把决策留给人:选哪个源、开不开 BBR、用 Xet 还是 hf_transfer。本插件把这些决策**全部变成可证伪的假设**,交给进化闭环用实测速度裁决:

```
/onboard
  ├─ 第1步  前置引导(唯一一次交互):机器形态 / 网络位置 / 优化重点
  ├─ 第2步  最小基线:只保底能跑,不做任何进阶优化
  ├─ 第3步  rsiloop 进化:每个 domain 一个闭环
  │         变异配置 → evaluator 实测打分 → 保留优胜 → 记录谱系
  └─ 第4步  固化:最优配置写回 sources.list / pip.conf / .bashrc,汇总报告
```

## 安装

```bash
# 在 Claude Code 中
/plugin marketplace add <this-repo-url>
/plugin install gpu-rsi-plugin
```

或开发态直接使用:`claude --plugin-dir /path/to/gpu-rsi-plugin`

## 使用

```bash
# 新机上线,一键全流程
/onboard

# 已有机器,单独跑一个进化闭环
# (直接对 Claude 说)"用 rsiloop 优化我的模型下载速度,自己迭代,不要问我"
```

## 结构

```
├── commands/onboard.md          ← 总流程:引导 → 基线 → 进化 → 固化
├── skills/rsiloop/
│   ├── SKILL.md                 ← 进化协议:变异/选择/谱系/硬约束/终止条件
│   ├── templates/               ← evaluator 模板(计时 + 正确性一票否决 + 单行 JSON)
│   │   ├── download/evaluator.sh   ← 下载:MB/s,sha256 校验(实测通过)
│   │   ├── compile/evaluator.sh    ← 编译:1000/秒,产物冒烟(实测通过)
│   │   └── install/evaluator.sh    ← 包安装:1000/秒,import 验证
│   ├── references/              ← 变异空间知识库(agent 按需查阅)
│   │   ├── cloud-gpu-setup.md      ← 云端环境配置全手册(镜像源/aria2c/HF/BBR/ccache)
│   │   └── pc-ubuntu-setup.md      ← 台式机补充(驱动/CUDA 多版本/ROS2/包冲突)
│   └── assets/                  ← selector.sh / reporter.py(通用件)
```

## 设计要点

1. **evaluator 是唯一可信环境**——禁止 agent 主观判断快慢,一切看 score;禁止改 evaluator
2. **正确性一票否决**——下载哈希错、编译产物跑不通,score=0,杜绝"快但错"的投机变异
3. **apply.sh 幂等 + 备份回滚**——变异评的是"应用配置后的真实系统行为",失败的变异必须能滚回去
4. **噪声纪律**——小耗时场景多次取优,只有数量级差异才作选择依据
5. **收敛条件**——最多 8 轮,或连续 2 轮无提升(且已做策略级变异),写 FINAL.md 停止

## 验收目标

全新云 GPU 机,人工只操作两步(启动 /onboard、回答 3 个前置问题),之后:
- 下载 domain:实测 MB/s 相对基线有数量级提升,谱系完整
- 全程零额外交互,产出 ~/rsi/*/lineage/FINAL.md

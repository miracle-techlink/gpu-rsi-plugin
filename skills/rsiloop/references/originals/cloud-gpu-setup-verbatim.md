# 云端 GPU 服务器环境配置指南(原文逐字收录)

> 本文件是原始文档的逐字收录版,不做压缩/改写,供 agent 需要完整上下文时查阅。
> 结构化摘要版见 ../cloud-gpu-setup.md。整理日期:2026-09-26。

适用场景:云端裸机/容器(Ubuntu 22.04,驱动与 CUDA 已预装),从零搭建 Python 训练环境
整理日期:2026-09-26;仿照《PC台式机Ubuntu22.04配置指南》结构,聚焦云端差异化部分:网络优化 → Miniconda → uv → 底层训练 wheels → 加速进阶
前提:nvidia-smi 有输出(云厂商镜像一般已装驱动 + CUDA);若为国内云,先做完第 1 节网络优化再装任何东西

---

文档大纲

1. 网络环境优化
  - 1.1 apt 源(清华 + 阿里云)
  - 1.2 pip / uv 镜像源
  - 1.3 aria2c 多线程下载与断点续传
  - 1.4 HuggingFace 镜像与 GitHub 加速
2. 安装 Miniconda
  - 2.1 下载与安装(aria2c + 清华镜像)
  - 2.2 conda 源与初始化
3. 安装 uv(极速 Python 包管理)
  - 3.1 安装 uv
  - 3.2 uv 创建环境与装包
  - 3.3 uv 性能调优
4. 安装底层训练环境(通用 wheels,不源码编译)
  - 4.1 torch + torchvision + triton(按 CUDA 版本选 wheel)
  - 4.2 flash-attn 预编译 wheel
  - 4.3 deepspeed
  - 4.4 验证
5. 加速进阶(按需选用)
  - 5.1 系统网络层:BBR + TCP 缓冲区(对一切下载生效)
  - 5.2 模型仓库:Git LFS 按需拉取
  - 5.3 数据集:流式 / 预下载 / 集群共享缓存
  - 5.4 对象存储互传:s5cmd / rclone / ossutil
  - 5.5 apt-fast(多线程 apt)
  - 5.6 包管理再提速:libmamba / pixi
  - 5.7 Docker 镜像加速(2025 可用源现状)
  - 5.8 万不得已源码编译时:ccache / sccache

---

1. 网络环境优化

1.1 apt 源(清华 + 阿里云)

云端只需换源,不需要 PC 机那套入网流程(Ubuntu 22.04 / jammy):

```bash
sudo cp /etc/apt/sources.list /etc/apt/sources.list.bak
sudo bash -c 'cat > /etc/apt/sources.list <<EOF
# Tsinghua source
deb https://mirrors.tuna.tsinghua.edu.cn/ubuntu/ jammy main restricted universe multiverse
deb https://mirrors.tuna.tsinghua.edu.cn/ubuntu/ jammy-updates main restricted universe multiverse
deb https://mirrors.tuna.tsinghua.edu.cn/ubuntu/ jammy-backports main restricted universe multiverse
deb https://mirrors.tuna.tsinghua.edu.cn/ubuntu/ jammy-security main restricted universe multiverse

# Aliyun source(备用,tuna 不可达时 fallback)
deb http://mirrors.aliyun.com/ubuntu/ jammy main restricted universe multiverse
deb http://mirrors.aliyun.com/ubuntu/ jammy-updates main restricted universe multiverse
deb http://mirrors.aliyun.com/ubuntu/ jammy-security main restricted universe multiverse
EOF'
sudo apt update && sudo apt upgrade -y
```

注意:若云主机本身就是阿里云,把阿里云源放前面(内网镜像 mirrors.cloud.aliyuncs.com 更快且免流量费)。

1.2 pip / uv 镜像源

全局 pip 源(清华为主,阿里为备):

```bash
mkdir -p ~/.pip
cat > ~/.pip/pip.conf <<EOF
[global]
index-url = https://pypi.tuna.tsinghua.edu.cn/simple
extra-index-url = https://mirrors.aliyun.com/pypi/simple/
EOF
```

uv 读自己的环境变量(~/.bashrc 追加):

```bash
# uv 镜像(清华 PyPI)
export UV_INDEX_URL=https://pypi.tuna.tsinghua.edu.cn/simple
export UV_DEFAULT_INDEX=https://pypi.tuna.tsinghua.edu.cn/simple
```

torch 等需要专用 index-url 的包不走上述镜像,详见 4.1(PyTorch 官方源国内通常也能直连,不行再走清华 pypi 里的 torch wheel)。

1.3 aria2c 多线程下载与断点续传

云端拉模型 / 数据集 / 大 wheel 必备:单连接 wget 经常跑不满带宽或被限速,aria2c 16 线程分块 + 断点续传:

```bash
sudo apt install -y aria2
```

用法模板(-x16 16 连接、-s16 分 16 段、-c 断点续传、-k1M 最小分块 1MB):

```bash
# 通用模板
aria2c -x16 -s16 -k1M -c -d /path/to/dir -o filename <URL>

# 例:下载 Miniconda 安装包(断电/掉线后重跑同一命令即续传)
aria2c -x16 -s16 -c \
  https://mirrors.tuna.tsinghua.edu.cn/anaconda/miniconda/Miniconda3-latest-Linux-x86_64.sh

# 例:下载大 wheel / 模型文件
aria2c -x16 -s16 -c -o model.safetensors <URL>
```

断点续传原理:aria2c 会在目标文件旁生成 .aria2 控制文件,中断后重跑同一条命令即可从断点继续;改了 URL 或输出路径就续不上。
服务器不支持 Range 请求时 -x16 会退化单线程,属正常现象。

1.4 HuggingFace 镜像与 GitHub 加速

HuggingFace(国内云必做)——~/.bashrc 追加:

```bash
# HF 镜像站
export HF_ENDPOINT=https://hf-mirror.com
```

之后 huggingface-cli download / from_pretrained 全部走镜像,无需改代码。

下载加速(2025 起官方默认推荐 Xet 路径):

```bash
# Xet:分块去重存储,天然支持断点续传 + 增量更新(微调迭代重下模型时收益巨大)
pip install "huggingface_hub[hf_xet]"    # 新版 hub 检测到 hf_xet 即自动启用,无需环境变量

# hf_transfer:Rust 多线程,单次冷下载极限速度最快,但续传弱、与 Xet 互斥
# 只在「一次性满带宽冷下载超大文件」时开:
# export HF_HUB_ENABLE_HF_TRANSFER=1     # 平时不要常驻,会覆盖 Xet
```

GitHub 加速(clone 大仓库 / 下 release 包慢时):

```bash
# clone 走代理前缀
git clone https://ghproxy.com/https://github.com/org/repo.git

# release 大文件走 aria2c + 代理前缀
aria2c -x16 -s16 -c https://ghproxy.com/https://github.com/org/repo/releases/download/v1/x.whl

# 备选前缀(哪个通用哪个):https://mirror.ghproxy.com/  https://gh-proxy.com/
```

---

2. 安装 Miniconda

2.1 下载与安装(aria2c + 清华镜像)

```bash
cd ~
aria2c -x16 -s16 -c \
  https://mirrors.tuna.tsinghua.edu.cn/anaconda/miniconda/Miniconda3-latest-Linux-x86_64.sh

bash Miniconda3-latest-Linux-x86_64.sh -b -p $HOME/miniconda3   # -b 静默 -p 指定目录
$HOME/miniconda3/bin/conda init bash
source ~/.bashrc
```

2.2 conda 源与初始化

```bash
cat > ~/.condarc <<EOF
channels:
  - defaults
show_channel_urls: true
default_channels:
  - https://mirrors.tuna.tsinghua.edu.cn/anaconda/pkgs/main
  - https://mirrors.tuna.tsinghua.edu.cn/anaconda/pkgs/r
custom_channels:
  conda-forge: https://mirrors.tuna.tsinghua.edu.cn/anaconda/cloud
  pytorch: https://mirrors.tuna.tsinghua.edu.cn/anaconda/cloud
EOF

conda clean -i   # 清索引缓存使换源生效

# 关掉 base 自启动(云端多项目建议)
conda config --set auto_activate_base false
```

conda 只用来管 Python 版本和隔离环境;装包一律用 uv(见下节),conda 源里二进制旧且解析慢。觉得 conda 解依赖慢可看 5.6 换 libmamba 求解器或 pixi。

---

3. 安装 uv(极速 Python 包管理)

3.1 安装 uv

```bash
# 官方脚本(国内可直连;不行就走 pip)
curl -LsSf https://astral.sh/uv/install.sh | sh
# 或:
pip install uv

source ~/.bashrc   # 或 exec bash,使 ~/.local/bin 生效
uv --version
```

3.2 uv 创建环境与装包

两种方式,任选其一:

方式 A:uv 完全托管环境(推荐云端新项目,可脱离 conda)

```bash
uv venv ~/venvs/train --python 3.10     # 没有 3.10 会自动下载 standalone python
source ~/venvs/train/bin/activate
uv pip install numpy einops
```

方式 B:conda 管环境,uv 只管装包(团队已有 conda 习惯时)

```bash
conda create -n train python=3.10 -y
conda activate train
uv pip install numpy einops            # 装进当前 conda env
```

uv 常用命令:

```bash
uv pip install -r requirements.txt     # 装依赖清单
uv pip install pkg==1.2.3
uv pip list / uv pip freeze
uv pip uninstall pkg
```

镜像:已按 1.2 设好 UV_INDEX_URL;临时换源可用 uv pip install pkg --index-url <URL>。

3.3 uv 性能调优

~/.bashrc 追加(配好镜像后这些是大依赖树的第二档加速):

```bash
export UV_CONCURRENT_DOWNLOADS=100    # 并发下载数,默认 50;大依赖树拉高,过高会触发镜像限流
export UV_HTTP_RETRIES=5              # 网络抖动重试
export UV_COMPILE_BYTECODE=1          # 安装时预编译字节码,首次 import 提速
# export UV_CACHE_DIR=/data/uv-cache  # 有 NVMe 数据盘时把缓存放过去,二次装环境秒级
```

装包防坑:

```bash
uv pip install --only-binary :all: pkg   # 只装预编译 wheel,杜绝云端莫名触发源码编译
```

---

4. 安装底层训练环境(通用 wheels,不源码编译)

原则:一律装官方预编译 wheel,不在云主机上源码编译(flash-attn 源码编译动辄半小时还吃内存)。

4.1 torch + torchvision + triton

先看 CUDA 版本决定 wheel 通道:

```bash
nvidia-smi | grep "CUDA Version"    # 显示驱动支持的最高 CUDA,如 12.x
```

CUDA 12.x(当前主流,以 cu126 为例):

```bash
uv pip install torch torchvision --index-url https://download.pytorch.org/whl/cu126
# triton 是 torch 2.x 的硬依赖,会随 torch 自动装上匹配版本,无需单独装
```

CUDA 11.8 老环境:

```bash
uv pip install torch torchvision --index-url https://download.pytorch.org/whl/cu118
```

版本组合速查(2026 年常用):
- torch 2.4.x ↔ triton 3.0.x / cu121、cu124
- torch 2.5~2.6 ↔ triton 3.1~3.2 / cu124、cu126
- 不指定版本号让官方 index 自动解出匹配组合,最稳
- PyTorch 官方源国内可直连;若慢,把 --index-url 换成清华(https://pypi.tuna.tsinghua.edu.cn/simple,包名 torch,cu 版本由 tag 决定,可选面窄)。

验证:

```bash
python -c "import torch; print(torch.__version__, torch.version.cuda, torch.cuda.is_available(), torch.cuda.get_device_name(0))"
```

4.2 flash-attn 预编译 wheel

不要 pip install flash-attn(那是源码编译)。去 release 页按「torch 版本 × CUDA × python 版本 × abiTRUE/FALSE」四元组选预编译 wheel:

```bash
# 先查四元组
python -c "import torch,sys; print(torch.__version__, torch.version.cuda, sys.version_info[:2], torch._C._GLIBCXX_USE_CXX11_ABI)"
# 例:torch 2.6.0+cu126 / cu12 / py3.10 / abiFALSE

# 从 GitHub release 用 aria2c 拉对应 wheel(以 flash-attn 2.7.4 为例,文件名按四元组选)
aria2c -x16 -s16 -c \
  https://github.com/Dao-AILab/flash-attention/releases/download/v2.7.4.post1/flash_attn-2.7.4.post1+cu12torch2.6cxx11abiFALSE-cp310-cp310-linux_x86_64.whl

uv pip install ./flash_attn-2.7.4.post1+cu12torch2.6cxx11abiFALSE-cp310-cp310-linux_x86_64.whl

python -c "import flash_attn; print(flash_attn.__version__)"
```

release 页:https://github.com/Dao-AILab/flash-attention/releases;四元组对不上就换邻近版本,abiTRUE/FALSE 选错会 import 报符号错误。
下载慢就套 1.4 的 ghproxy 前缀。

4.3 deepspeed

DeepSpeed 本体是纯 Python + JIT op,常规训练(ZeRO / offload)不需要预编译 op,直接装:

```bash
uv pip install deepspeed
```

验证(JIT 编译几个基础 op,首次会花 1–2 分钟):

```bash
ds_report    # 看 deepspeed 环境自检,op 标 [OKAY] 或 [NO] 但不影响 ZeRO 训练
```

只有需要 fused kernels 极限性能时才 DS_BUILD_OPS=1 uv pip install deepspeed(编译耗时长,云端一般用不到)。

4.4 总验证

```bash
python - <<'EOF'
import torch, flash_attn, deepspeed
print("torch:", torch.__version__, "| cuda:", torch.version.cuda, "| gpu ok:", torch.cuda.is_available())
print("flash_attn:", flash_attn.__version__)
print("deepspeed:", deepspeed.__version__)
x = torch.randn(1024, 1024, device="cuda")
print("matmul ok:", (x @ x).sum().item() != 0)
EOF
```

---

5. 加速进阶(按需选用)

5.1 系统网络层:BBR + TCP 缓冲区(对一切下载生效)

云主机最值得开的一项:BBR 拥塞控制在跨境/丢包线路下吞吐提升明显,且对 aria2c、HF、对象存储等所有 TCP 下载统一生效,一劳永逸。需内核 ≥ 4.9(Ubuntu 22.04 默认 5.15 满足):

```bash
sudo bash -c 'cat >> /etc/sysctl.conf <<EOF

# BBR 拥塞控制
net.core.default_qdisc = fq
net.ipv4.tcp_congestion_control = bbr

# 调大 TCP 缓冲区(高带宽高延迟场景,配合 aria2c 多线程效果显著)
net.core.rmem_max = 134217728
net.core.wmem_max = 134217728
net.ipv4.tcp_rmem = 4096 87380 134217728
net.ipv4.tcp_wmem = 4096 65536 134217728

# TCP 特性
net.ipv4.tcp_fastopen = 3
net.ipv4.tcp_mtu_probing = 1
EOF'
sudo sysctl -p

# 验证
sysctl net.ipv4.tcp_congestion_control    # 应输出 bbr
```

配套建议:数据集/模型缓存放本地 NVMe 数据盘(挂载加 noatime),不要让 dataloader 读网络盘。

5.2 模型仓库:Git LFS 按需拉取

clone 模型仓库时只拉要的分片,比全量 git clone 省一半以上流量:

```bash
# 跳过 LFS 实际下载 + 浅克隆(只要 git 元数据和指针文件)
GIT_LFS_SKIP_SMUDGE=1 git clone --depth 1 https://hf-mirror.com/Qwen/Qwen2-7B
cd Qwen2-7B

# 按需补拉(只要 safetensors 分片和配置)
git lfs pull --include="*.safetensors,config.json,tokenizer*"

# LFS 并发拉高(默认 8)
git config lfs.concurrenttransfers 16
```

注意:git lfs clone 已废弃,Git 2.3+ 原生 clone 性能等同;浅克隆无法 checkout 历史 commit。

5.3 数据集:流式 / 预下载 / 集群共享缓存

```python
# 流式:边下边训、不落盘(适合探索性实验、磁盘紧张;多 epoch 会重复拉)
ds = load_dataset("HuggingFaceFW/fineweb", split="train", streaming=True)
```

```bash
# 预下载:训练前统一拉好,之后离线读缓存(适合单机多次训练)
huggingface-cli download bigcode/the-stack-smol --repo-type dataset --local-dir ./data/the-stack-smol
export HF_DATASETS_OFFLINE=1   # 训练时不再联网
```

多机/多卡集群避免重复下载:

```bash
# 缓存指向共享文件系统(NFS / Lustre / JuiceFS)
export HF_HOME=/shared/nfs/huggingface
```

```python
# rank 0 先下载,其他 rank 等待后命中缓存
from datasets import load_dataset
import torch.distributed as dist
if dist.get_rank() == 0:
    ds = load_dataset("your_dataset")
dist.barrier()
ds = load_dataset("your_dataset")
```

坑:NFS 上文件锁可能有问题,务必 rank0 预下载完再让其他节点读;不要多进程同时写同一缓存目录。
国产模型(Qwen/DeepSeek 等)优先走 ModelScope:modelscope download --model Qwen/Qwen2.5-7B-Instruct,国内 CDN 更快。

5.4 对象存储互传:s5cmd / rclone / ossutil

ckpt 和数据集在云端与对象存储间搬运的高频工具,均兼容 S3 协议(阿里云 OSS、腾讯云 COS、MinIO 都能用):

```bash
# s5cmd:Go 实现,大量小文件比 aws cli 快数倍~10 倍(性能之王)
s5cmd --endpoint-url https://oss-cn-beijing.aliyuncs.com \
  --numworkers 256 cp 's3://bucket/datasets/*' ./datasets/

# rclone:跨云互通、S3↔OSS server-side copy 不过本机
rclone copy ./datasets oss:bucket/datasets \
  --transfers=32 --checkers=16 --multi-thread-streams=8 \
  --multi-thread-cutoff=250M --fast-list --progress

# aws cli 调优(单个大文件 10GB+)
aws configure set default.s3.max_concurrent_requests 50
aws configure set default.s3.multipart_chunksize 64MB

# 阿里云官方 ossutil(OSS 专用,千万级小文件有优化)
ossutil cp -r ./datasets oss://bucket/datasets --jobs=20 --parallel=20 --bigfile-threshold=100M
```

同区域必做:endpoint 用内网地址(如 oss-cn-beijing-internal.aliyuncs.com),免公网流量费且延迟更低。
选型:大量小文件用 s5cmd 或 rclone --transfers 拉高;单个大文件用 rclone --multi-thread-streams=8 或 aws cli 调大 chunksize。

5.5 apt-fast(多线程 apt)

装机阶段 apt 大包多线程下载,底层走 aria2、可多镜像并发拉同一 deb:

```bash
sudo add-apt-repository ppa:apt-fast/stable
sudo apt update && sudo apt install -y apt-fast aria2

# 用法与 apt 相同
sudo apt-fast install <包名>
```

多镜像并发写在 /etc/apt-fast.conf 的 MIRRORS=(可配清华 + 阿里 + 官方源同时拉)。只加速下载阶段,安装阶段仍走 apt。

5.6 包管理再提速:libmamba / pixi

conda 解依赖慢的两条出路:

```bash
# 出路 1:换 libmamba 求解器(conda 24.x+ 已默认,旧版手动开)
conda config --set solver libmamba    # 解依赖从分钟级到秒级
conda config --show solver            # 验证

# 出路 2:新项目直接用 pixi(Rattler 内核,并行下载 + 快求解器,比 conda/mamba 再快一档)
curl -fsSL https://pixi.sh/install.sh | sh
pixi init myproj && cd myproj && pixi add python=3.10 numpy
```

选型:纯 Python 项目 → uv(本文档主线);要 conda 生态/系统级依赖 → pixi;老 conda 项目过渡 → 开 libmamba。

5.7 Docker 镜像加速(2025 可用源现状)

注意:PC 文档里那批公共 registry mirror(USTC/网易/腾讯/163 等)2024 年中起已大面积关闭或限流,云端按下述可用源配:

```bash
sudo tee /etc/docker/daemon.json <<EOF
{
  "registry-mirrors": [
    "https://docker.m.daocloud.io"
  ]
}
EOF
sudo systemctl daemon-reload && sudo systemctl restart docker
```

- docker.m.daocloud.io(DaoCloud):目前可用的公共代理,也可直接前缀拉取 docker pull docker.m.daocloud.io/library/nginx:latest(免改 daemon)
- 阿里云个人专属加速器(控制台 → 容器镜像服务 → 镜像加速器获取 https://xxxx.mirror.aliyuncs.com):在阿里云 ECS 上效果最佳,外网不一定生效
- 兜底:GitHub Actions 同步所需镜像到阿里云 ACR / 腾讯云 TCR 个人实例;或给 Docker 配 HTTP 代理直连

镜像站可用性变化频繁,以实际 docker pull 测试为准。

5.8 万不得已源码编译时:ccache / sccache

原则仍是"不编译"(见第 4 章),但确需源码编译(自定义 CUDA op 等)时上编译缓存,二次编译从小时级压到分钟级:

```bash
sudo apt install -y ccache
ccache -M 50G    # 缓存上限拉大,torch 级项目产物很大

# 让编译走缓存(~/.bashrc)
export CMAKE_C_COMPILER_LAUNCHER=ccache
export CMAKE_CXX_COMPILER_LAUNCHER=ccache
export CMAKE_CUDA_COMPILER_LAUNCHER=ccache

# 并行拉满 + Ninja
export MAX_JOBS=$(nproc)
```

多机/CI 共享缓存换 sccache(可挂 S3 后端,把上面 ccache 字样替换即可)。ccache -s 查命中率。

---

要点速览

| 主题 | 关键信息 |
|---|---|
| apt 源 | 清华为主 + 阿里云备用;阿里云主机优先用内网源 mirrors.cloud.aliyuncs.com |
| pip 源 | ~/.pip/pip.conf → tuna;uv 用 UV_INDEX_URL 环境变量,不吃 pip.conf |
| aria2c | aria2c -x16 -s16 -k1M -c URL;-c 断点续传,重跑同命令即续;.aria2 控制文件别删 |
| HF 加速 | HF_ENDPOINT=https://hf-mirror.com;默认走 Xet(huggingface_hub[hf_xet],自动启用),hf_transfer 仅留作单次冷下载可选项(与 Xet 互斥) |
| GitHub 加速 | https://ghproxy.com/ 前缀,clone 和 release 都能套 |
| Miniconda | 清华镜像 + aria2c 下载,-b -p $HOME/miniconda3 静默装;conda 只管 Python 版本 |
| uv | curl astral.sh/uv/install.sh;uv venv 或 conda env 里 uv pip install,比 pip 快一个量级;调优三件套 UV_CONCURRENT_DOWNLOADS=100 / UV_COMPILE_BYTECODE=1 / --only-binary :all: |
| torch | --index-url https://download.pytorch.org/whl/cu126(按 CUDA 版本);triton 随 torch 自动装匹配版 |
| flash-attn | 只装预编译 wheel:release 页按 torch×CUDA×python×cxx11abi 四元组选,aria2c 下载后本地 uv pip install;abi 选错 import 报符号错 |
| deepspeed | 直接 uv pip install deepspeed,ZeRO 训练无需编译 op;ds_report 自检 |
| BBR | sysctl 开 bbr + fq + 调大 TCP 缓冲区,对一切 TCP 下载统一提速,云主机最值得开 |
| Git LFS | GIT_LFS_SKIP_SMUDGE=1 git clone --depth 1 + git lfs pull --include= 按需拉模型分片 |
| 数据集 | 探索用 streaming;单机上预下载 + HF_DATASETS_OFFLINE=1;集群共享缓存 + rank0 预下载 + barrier |
| 对象存储 | 大量小文件用 s5cmd(比 aws cli 快数倍);跨云用 rclone;同区域走内网 endpoint 免流量费 |
| apt-fast | apt 下载走 aria2 多线程,装机大包提速 |
| libmamba/pixi | conda 解依赖换 libmamba 或迁移 pixi |
| Docker 镜像 | 老公共 mirror 大批失效;现可用 docker.m.daocloud.io 或阿里云个人专属加速器(ECS 上) |
| 编译缓存 | 万不得已源码编译时 ccache/sccache + MAX_JOBS=$(nproc),二次编译从小时到分钟 |
| 大原则 | 云端一切走预编译 wheel,不源码编译;大文件一律 aria2c 不 wget;缓存目录放 NVMe 快盘 |

---

备注

- 与 PC 机文档的差异:云端无入网/显卡驱动/CUDA Toolkit 安装环节(云镜像自带),故本文档从网络优化写起;若需多版本 CUDA 切换或 cuDNN/NCCL,参照 PC 文档 2.5 / 3.1 / 3.5 节,命令云端通用。
- 版本号为 2026-09 时点的常用组合(torch 2.6 / flash-attn 2.7.4 / cu126),执行前以 PyTorch 与 flash-attn release 页最新兼容矩阵为准复核。
- 第 5 章为按需选用的进阶项:5.1(BBR)和 5.2(Git LFS)性价比高建议常做;5.3–5.8 视场景(是否多机、是否用对象存储、是否用 Docker、是否源码编译)选用。
- HF Xet 默认行为、Docker 可用镜像源这两条时效性强,执行前建议以官方文档 / 实际 pull 测试再核一遍。
- 若云端容器禁 sudo:apt 段跳过,aria2 可用 conda install -c conda-forge aria2 或下载静态二进制替代;BBR/sysctl 需要宿主权限,容器内改不了可跳过;其余步骤均不需要 root。

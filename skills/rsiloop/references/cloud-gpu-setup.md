# 云端 GPU 服务器环境配置指南(Miniconda + uv + aria2c + 训练底层 wheels + 加速进阶)

适用场景:云端裸机/容器(Ubuntu 22.04,驱动与 CUDA 已预装),从零搭建 Python 训练环境
整理日期:2026-09-26;聚焦云端差异化部分:网络优化 → Miniconda → uv → 底层训练 wheels → 加速进阶
前提:nvidia-smi 有输出(云厂商镜像一般已装驱动 + CUDA);若为国内云,先做完第 1 节网络优化再装任何东西

---

1. 网络环境优化

1.1 apt 源(清华 + 阿里云)

云端只需换源(Ubuntu 22.04 / jammy):

```bash
sudo cp /etc/apt/sources.list /etc/apt/sources.list.bak
sudo bash -c 'cat > /etc/apt/sources.list <<EOF
# Tsinghua source
deb https://mirrors.tuna.tsinghua.edu.cn/ubuntu/ jammy main restricted universe multiverse
deb https://mirrors.tuna.tsinghua.edu.cn/ubuntu/ jammy-updates main restricted universe multiverse
deb https://mirrors.tuna.tsinghua.edu.cn/ubuntu/ jammy-backports main restricted universe multiverse
deb https://mirrors.tuna.tsinghua.edu.cn/ubuntu/ jammy-security main restricted universe multiverse

# Aliyun source(备用)
deb http://mirrors.aliyun.com/ubuntu/ jammy main restricted universe multiverse
deb http://mirrors.aliyun.com/ubuntu/ jammy-updates main restricted universe multiverse
deb http://mirrors.aliyun.com/ubuntu/ jammy-security main restricted universe multiverse
EOF'
sudo apt update && sudo apt upgrade -y
```

注意:若云主机本身就是阿里云,把阿里云源放前面(内网镜像 mirrors.cloud.aliyuncs.com 更快且免流量费)。

1.2 pip / uv 镜像源

```bash
mkdir -p ~/.pip
cat > ~/.pip/pip.conf <<EOF
[global]
index-url = https://pypi.tuna.tsinghua.edu.cn/simple
extra-index-url = https://mirrors.aliyun.com/pypi/simple/
EOF

# uv 读自己的环境变量(~/.bashrc 追加)——uv 不吃 pip.conf
export UV_INDEX_URL=https://pypi.tuna.tsinghua.edu.cn/simple
export UV_DEFAULT_INDEX=https://pypi.tuna.tsinghua.edu.cn/simple
```

torch 等需要专用 index-url 的包不走上述镜像,详见 4.1(PyTorch 官方源国内通常也能直连,不行再走清华 pypi 里的 torch wheel)。临时换源:uv pip install pkg --index-url <URL>。

1.3 aria2c 多线程下载与断点续传

```bash
sudo apt install -y aria2

# 通用模板(-x16 16连接、-s16 分16段、-c 断点续传、-k1M 最小分块1MB)
aria2c -x16 -s16 -k1M -c -d /path/to/dir -o filename <URL>

# 例:Miniconda 安装包(断电/掉线后重跑同一命令即续传)
aria2c -x16 -s16 -c \
  https://mirrors.tuna.tsinghua.edu.cn/anaconda/miniconda/Miniconda3-latest-Linux-x86_64.sh

# 例:大 wheel / 模型文件
aria2c -x16 -s16 -c -o model.safetensors <URL>
```

断点续传原理:aria2c 在目标文件旁生成 .aria2 控制文件,中断后重跑同一条命令即续;改了 URL 或输出路径就续不上,控制文件别删。服务器不支持 Range 请求时 -x16 退化单线程,属正常。

1.4 HuggingFace 镜像与 GitHub 加速

```bash
# HF 镜像(~/.bashrc)
export HF_ENDPOINT=https://hf-mirror.com

# Xet:分块去重,天然断点续传+增量更新(新版 hub 检测到 hf_xet 自动启用)
pip install "huggingface_hub[hf_xet]"

# hf_transfer:Rust 多线程,单次冷下载极限最快,但续传弱、与 Xet 互斥,平时不要常驻
# export HF_HUB_ENABLE_HF_TRANSFER=1

# GitHub 加速:clone 走代理前缀
git clone https://ghproxy.com/https://github.com/org/repo.git
# release 大文件走 aria2c + 代理前缀
aria2c -x16 -s16 -c https://ghproxy.com/https://github.com/org/repo/releases/download/v1/x.whl
# 备选前缀:https://mirror.ghproxy.com/  https://gh-proxy.com/
```

---

2. 安装 Miniconda

2.1 下载与安装

```bash
cd ~
aria2c -x16 -s16 -c \
  https://mirrors.tuna.tsinghua.edu.cn/anaconda/miniconda/Miniconda3-latest-Linux-x86_64.sh
bash Miniconda3-latest-Linux-x86_64.sh -b -p $HOME/miniconda3
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
conda clean -i
conda config --set auto_activate_base false
```

conda 只管 Python 版本和隔离环境;装包一律用 uv。

---

3. 安装 uv(极速 Python 包管理)

3.1 安装

```bash
curl -LsSf https://astral.sh/uv/install.sh | sh   # 或 pip install uv
source ~/.bashrc
```

3.2 创建环境与装包

```bash
# 方式 A:uv 完全托管(推荐云端新项目)
uv venv ~/venvs/train --python 3.10
source ~/venvs/train/bin/activate
uv pip install numpy einops

# 方式 B:conda 管环境,uv 只管装包
conda create -n train python=3.10 -y && conda activate train
uv pip install numpy einops
```

3.3 性能调优(~/.bashrc)

```bash
export UV_CONCURRENT_DOWNLOADS=100    # 默认 50,大依赖树拉高
export UV_HTTP_RETRIES=5
export UV_COMPILE_BYTECODE=1          # 安装时预编译字节码
# export UV_CACHE_DIR=/data/uv-cache  # 有 NVMe 数据盘时

# 防坑:只装预编译 wheel,杜绝云端莫名触发源码编译
uv pip install --only-binary :all: pkg
```

---

4. 安装底层训练环境(通用 wheels,不源码编译)

原则:一律官方预编译 wheel,不源码编译(flash-attn 源码编译动辄半小时还吃内存)。

4.1 torch + torchvision + triton

```bash
nvidia-smi | grep "CUDA Version"   # 看驱动支持的最高 CUDA

# CUDA 12.x(以 cu126 为例)
uv pip install torch torchvision --index-url https://download.pytorch.org/whl/cu126
# triton 是 torch 2.x 硬依赖,随 torch 自动装匹配版

# CUDA 11.8 老环境
uv pip install torch torchvision --index-url https://download.pytorch.org/whl/cu118

# 验证
python -c "import torch; print(torch.__version__, torch.version.cuda, torch.cuda.is_available(), torch.cuda.get_device_name(0))"
```

版本组合速查(2026 常用):torch 2.4.x ↔ triton 3.0.x / cu121/124;torch 2.5~2.6 ↔ triton 3.1~3.2 / cu124/126。不指定版本号让官方 index 自动解最稳。

4.2 flash-attn 预编译 wheel

不要 pip install flash-attn(那是源码编译)。去 release 页按「torch 版本 × CUDA × python 版本 × abiTRUE/FALSE」四元组选预编译 wheel:

```bash
# 先查四元组
python -c "import torch,sys; print(torch.__version__, torch.version.cuda, sys.version_info[:2], torch._C._GLIBCXX_USE_CXX11_ABI)"

# 从 GitHub release 用 aria2c 拉对应 wheel(以 2.7.4 为例)
aria2c -x16 -s16 -c \
  https://github.com/Dao-AILab/flash-attention/releases/download/v2.7.4.post1/flash_attn-2.7.4.post1+cu12torch2.6cxx11abiFALSE-cp310-cp310-linux_x86_64.whl
uv pip install ./flash_attn-*.whl
python -c "import flash_attn; print(flash_attn.__version__)"
```

release 页:https://github.com/Dao-AILab/flash-attention/releases;四元组对不上换邻近版本,abiTRUE/FALSE 选错 import 报符号错误。下载慢套 ghproxy 前缀。

4.3 deepspeed

```bash
uv pip install deepspeed    # 常规 ZeRO/offload 无需编译 op
ds_report                   # 自检,op 标 [NO] 不影响 ZeRO 训练
```

只有需要 fused kernels 极限性能才 DS_BUILD_OPS=1(编译耗时长,云端一般用不到)。

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

5.1 BBR + TCP 缓冲区(对一切下载生效,云主机最值得开)

```bash
sudo bash -c 'cat >> /etc/sysctl.conf <<EOF
net.core.default_qdisc = fq
net.ipv4.tcp_congestion_control = bbr
net.core.rmem_max = 134217728
net.core.wmem_max = 134217728
net.ipv4.tcp_rmem = 4096 87380 134217728
net.ipv4.tcp_wmem = 4096 65536 134217728
net.ipv4.tcp_fastopen = 3
net.ipv4.tcp_mtu_probing = 1
EOF'
sudo sysctl -p
sysctl net.ipv4.tcp_congestion_control   # 应输出 bbr
```

配套:数据集/模型缓存放本地 NVMe(挂载加 noatime),不要让 dataloader 读网络盘。

5.2 Git LFS 按需拉取

```bash
GIT_LFS_SKIP_SMUDGE=1 git clone --depth 1 https://hf-mirror.com/Qwen/Qwen2-7B
cd Qwen2-7B
git lfs pull --include="*.safetensors,config.json,tokenizer*"
git config lfs.concurrenttransfers 16
```

注意:git lfs clone 已废弃;浅克隆无法 checkout 历史 commit。

5.3 数据集:流式 / 预下载 / 集群共享缓存

```python
# 流式:边下边训(探索性实验;多 epoch 会重复拉)
ds = load_dataset("HuggingFaceFW/fineweb", split="train", streaming=True)
```

```bash
# 预下载 + 离线(适合单机多次训练)
huggingface-cli download bigcode/the-stack-smol --repo-type dataset --local-dir ./data/the-stack-smol
export HF_DATASETS_OFFLINE=1   # 训练时不再联网

# 集群共享缓存(缓存指向共享文件系统 NFS/Lustre/JuiceFS)
export HF_HOME=/shared/nfs/huggingface
```

多机/多卡避免重复下载——rank0 先下载,其他 rank barrier 后命中缓存:

```python
from datasets import load_dataset
import torch.distributed as dist
if dist.get_rank() == 0:
    ds = load_dataset("your_dataset")
dist.barrier()
ds = load_dataset("your_dataset")
```

坑:NFS 上文件锁可能有问题,务必 rank0 预下载完再让其他节点读;不要多进程同时写同一缓存目录。
国产模型(Qwen/DeepSeek 等)优先 ModelScope:modelscope download --model Qwen/Qwen2.5-7B-Instruct,国内 CDN 更快。

5.4 对象存储互传:s5cmd / rclone / ossutil

```bash
# s5cmd:大量小文件比 aws cli 快数倍~10 倍
s5cmd --endpoint-url https://oss-cn-beijing.aliyuncs.com --numworkers 256 cp 's3://bucket/datasets/*' ./datasets/

# rclone:跨云互通,server-side copy 不过本机
rclone copy ./datasets oss:bucket/datasets --transfers=32 --checkers=16 --multi-thread-streams=8 --multi-thread-cutoff=250M --fast-list --progress

# aws cli 调优(单个大文件 10GB+)
aws configure set default.s3.max_concurrent_requests 50
aws configure set default.s3.multipart_chunksize 64MB

# 阿里云官方 ossutil(千万级小文件优化)
ossutil cp -r ./datasets oss://bucket/datasets --jobs=20 --parallel=20 --bigfile-threshold=100M
```

同区域必做:endpoint 用内网地址(如 oss-cn-beijing-internal.aliyuncs.com),免公网流量费且延迟更低。

5.5 apt-fast(多线程 apt)

```bash
sudo add-apt-repository ppa:apt-fast/stable
sudo apt update && sudo apt install -y apt-fast aria2
sudo apt-fast install <包名>
# 多镜像并发写在 /etc/apt-fast.conf 的 MIRRORS=
```

5.6 libmamba / pixi

```bash
conda config --set solver libmamba    # conda 24.x+ 已默认;解依赖分钟级→秒级
# 或新项目直接用 pixi(Rattler 内核,比 conda/mamba 再快一档)
curl -fsSL https://pixi.sh/install.sh | sh
pixi init myproj && cd myproj && pixi add python=3.10 numpy
```

5.7 Docker 镜像加速(2025 可用源现状)

老公共 mirror(USTC/网易/腾讯/163 等)2024 年中起大面积关闭或限流:

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

- docker.m.daocloud.io:目前可用的公共代理,也可直接前缀拉取 docker pull docker.m.daocloud.io/library/nginx:latest(免改 daemon)
- 阿里云个人专属加速器(控制台→容器镜像服务→镜像加速器,获取 https://xxxx.mirror.aliyuncs.com):ECS 上效果最佳,外网不一定生效
- 兜底:GitHub Actions 同步所需镜像到阿里云 ACR / 腾讯云 TCR 个人实例;或给 Docker 配 HTTP 代理直连
- 镜像站可用性变化频繁,以实际 docker pull 测试为准
- 阿里云个人专属加速器(控制台→容器镜像服务获取):ECS 上效果最佳,外网不一定生效
- 兜底:GitHub Actions 同步到 ACR/TCR;或给 Docker 配 HTTP 代理
- 可用性变化频繁,以实际 docker pull 测试为准

5.8 编译缓存 ccache / sccache

```bash
sudo apt install -y ccache
ccache -M 50G
# ~/.bashrc
export CMAKE_C_COMPILER_LAUNCHER=ccache
export CMAKE_CXX_COMPILER_LAUNCHER=ccache
export CMAKE_CUDA_COMPILER_LAUNCHER=ccache
export MAX_JOBS=$(nproc)
# 多机/CI 共享缓存换 sccache(可挂 S3 后端);ccache -s 查命中率
```

---

要点速览

| 主题 | 关键信息 |
|---|---|
| apt 源 | 清华为主+阿里备用;阿里云主机优先内网源 mirrors.cloud.aliyuncs.com |
| pip/uv 源 | pip.conf→tuna;uv 用 UV_INDEX_URL,不吃 pip.conf |
| aria2c | -x16 -s16 -k1M -c;-c 断点续传;.aria2 控制文件别删 |
| HF | HF_ENDPOINT=hf-mirror.com;默认 Xet 自动启用;hf_transfer 仅单次冷下载(与 Xet 互斥) |
| GitHub | ghproxy.com 前缀,clone 和 release 都能套 |
| torch | --index-url download.pytorch.org/whl/cu126;triton 随 torch 自动装 |
| flash-attn | 只装预编译 wheel,按 torch×CUDA×python×cxx11abi 四元组选;abi 选错 import 报符号错 |
| deepspeed | 直接装,ZeRO 无需编译 op |
| BBR | bbr+fq+大 TCP 缓冲区,对一切 TCP 下载统一提速 |
| Git LFS | GIT_LFS_SKIP_SMUDGE=1 + --depth 1 + lfs pull --include= 按需拉 |
| 对象存储 | 小文件 s5cmd;跨云 rclone;同区域走内网 endpoint 免流量费 |
| 大原则 | 一切走预编译 wheel 不源码编译;大文件一律 aria2c 不 wget;缓存放 NVMe |

备注:
- 容器禁 sudo 时:apt 段跳过,aria2 用 conda install -c conda-forge aria2 或静态二进制;BBR/sysctl 需宿主权限,容器内改不了可跳过;其余步骤不需要 root。
- 版本号为 2026-09 时点(torch 2.6 / flash-attn 2.7.4 / cu126),执行前以最新兼容矩阵复核。
- HF Xet 默认行为、Docker 可用镜像源时效性强,执行前以官方文档/实际 pull 测试再核。

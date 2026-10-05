# PC 台式机 Ubuntu 22.04 配置指南(汇总整理)

来源:一份团队内部 PC 装机文档,归并校对后整理
适用:PC 台式机 + Ubuntu 22.04(jammy),含 RTX 5080 显卡场景
与云端文档差异:PC 机有显卡驱动/CUDA Toolkit 安装环节,云端从网络优化写起

---

1. 基础配置(本地)

1.1 软件源和 MAC 地址

apt 三镜像(阿里/清华/中科大,Ubuntu 22.04 jammy):

```bash
sudo bash -c 'cat > /etc/apt/sources.list <<EOF
# Aliyun source
deb http://mirrors.aliyun.com/ubuntu/ jammy main restricted universe multiverse
deb http://mirrors.aliyun.com/ubuntu/ jammy-updates main restricted universe multiverse

# Tsinghua source
deb https://mirrors.tuna.tsinghua.edu.cn/ubuntu/ jammy main restricted universe multiverse
deb https://mirrors.tuna.tsinghua.edu.cn/ubuntu/ jammy-updates main restricted universe multiverse
deb https://mirrors.tuna.tsinghua.edu.cn/ubuntu/ jammy-backports main restricted universe multiverse
deb https://mirrors.tuna.tsinghua.edu.cn/ubuntu/ jammy-security main restricted universe multiverse

# USTC source
deb https://mirrors.ustc.edu.cn/ubuntu/ jammy main restricted universe multiverse
deb https://mirrors.ustc.edu.cn/ubuntu/ jammy-updates main restricted universe multiverse
deb https://mirrors.ustc.edu.cn/ubuntu/ jammy-backports main restricted universe multiverse
deb https://mirrors.ustc.edu.cn/ubuntu/ jammy-security main restricted universe multiverse
EOF'
```

pip 内网源(企业内网环境用,按实际情况替换):

```
[global]
index-url = https://pypi.tuna.tsinghua.edu.cn/simple
# 企业内网可再加内部镜像,例如:
# extra-index-url = http://<internal-pypi-mirror>/simple
# trusted-host = <internal-pypi-mirror>
```

记录有线+无线网卡 MAC(ip addr)备用。

1.2 禁止休眠(Optional)

```bash
sudo systemctl mask sleep.target suspend.target hibernate.target hybrid-sleep.target
```

1.3 系统语言为英文

```bash
sudo apt update && sudo apt install -y locales
sudo locale-gen en_US.UTF-8 && sudo update-locale
# /etc/default/locale 全部 LC_*=en_US.UTF-8
```

1.4 远程 SSH

```bash
sudo apt install -y ca-certificates gnupg lsb-release net-tools openssh-client openssh-server mokutil
sudo mokutil --sb-state   # 查 secure boot
```

---

2. 基础配置(SSH)

2.1 显卡驱动

- 装前 `lspci | grep -i nvidia` 确认显卡在位
- **RTX 5080 不能用 apt 装驱动(截至 2025-09-14),须官网 .run**(示例 570.133.07)

```bash
sudo apt remove --purge nvidia* && sudo apt autoremove
sudo add-apt-repository ppa:graphics-drivers/ppa
sudo apt update && sudo apt upgrade -y && sudo apt install -y build-essential
chmod 755 NVIDIA-Linux-x86_64-570.133.07.run
sudo ./NVIDIA-Linux-x86_64-570.133.07.run
# 必要时 blacklist nouveau: /etc/modprobe.d/blacklist.conf 加
#   blacklist nouveau / options nouveau modeset=1
sudo update-initramfs -u && sudo reboot
```

2.2 基础开发环境(一长串 apt 包)

```bash
sudo apt install -y wget curl git tmux zsh htop cloc pip git-lfs cmake ninja-build \
  libjemalloc-dev rdma-core libblas-dev liblapack-dev libatlas-base-dev \
  libopenblas-base libopenblas-dev openmpi-bin libopenmpi-dev \
  python3-dev python3-numpy libopencv-dev python3-opencv ffmpeg \
  lmdb-utils liblmdb-dev python3-lmdb libgflags-dev libgoogle-glog-dev \
  redis redis-server ccache libboost-all-dev texlive-full
sudo snap install sccache --candidate --classic
```

踩坑:
- **包冲突**:libopencv-dev 依赖 libtbb-dev,intel-mkl 依赖 libtbb2-dev,冲突 → `sudo apt remove --purge libtbb2-dev`
- texlive-full 挂起 bug:连按 10 次回车等待;可先 export LC_ALL=en_US.UTF-8 + sudo apt --fix-broken install

2.3 Docker + NVIDIA Container Toolkit

```bash
# docker-ce 走清华源安装后,配 registry mirror /etc/docker/daemon.json
sudo systemctl daemon-reload && sudo systemctl restart docker
# NVIDIA Container Toolkit
sudo apt install -y nvidia-docker2
sudo nvidia-ctk runtime configure --runtime=docker
sudo systemctl restart docker
sudo usermod -aG docker $USER
```

**NVML 坑**:容器内 Failed to initialize NVML: Insufficient Permissions → VirtualGL/NVML 冲突:
1. 查 /dev/nvidia* 的 GID
2. sudo groupadd -g <GID> vglusers
3. sudo usermod -aG vglusers <user>
4. /etc/nvidia-container-runtime/config.toml 的 [nvidia-container-runtime] 加 user = "root:vglusers"

2.4 基础软件(VirtualGL + TurboVNC 远程图形)

```bash
wget https://github.com/VirtualGL/virtualgl/releases/download/.../virtualgl_3.1_x_amd64.deb
sudo dpkg -i virtualgl_3.1_*_amd64.deb
wget https://github.com/TurboVNC/turbovnc/releases/download/.../turbovnc_3.2_amd64.deb
sudo dpkg -i turbovnc_3.2_amd64.deb
```

2.5 CUDA Toolkit(多版本共存)

```bash
# .run silent 模式只装 toolkit 不装驱动,覆盖 11.7.1~12.9.1
sudo sh cuda_12.6.3_560.35.05_linux.run --silent --toolkit
# 重链软链 + bashrc
sudo rm /usr/local/cuda && sudo ln -s /usr/local/cuda-11.7 /usr/local/cuda
# ~/.bashrc: export CUDA_HOME=/usr/local/cuda-11.7; PATH/LD_LIBRARY_PATH 指向 $CUDA_HOME
```

---

3. 可选配置(SSH)

3.1 cuDNN(一套 9.x 拷进多个 CUDA 版本目录)

```bash
sudo tar -xvf cudnn-linux-x86_64-9.10.1.4_cuda12-archive.tar.xz -C /usr/local
sudo rm -f /usr/local/cuda-*/include/cudnn.h /usr/local/cuda-*/lib64/libcudnn*
# 逐版本拷贝 include/cudnn*.h 和 lib/libcudnn* 到各 cuda-X.Y 目录
# 验证: cat /usr/local/cuda-X.Y/include/cudnn_version.h | grep CUDNN_MAJOR -A 2
```

3.2 gcc/g++ 多版本(update-alternatives)

```bash
sudo apt install -y gcc-9 g++-9
sudo update-alternatives --install /usr/bin/gcc gcc /usr/bin/gcc-9 10
# ... gcc-10/11/12 优先级 20/30/40
sudo update-alternatives --config gcc
# bashrc: export CC=/usr/bin/gcc-9 CXX=/usr/bin/g++-9
```

3.3 Colmap(源码编译,RTX 5080 用 sm_80)

```bash
sudo apt-get install -y git cmake ninja-build build-essential libboost-program-options-dev \
  libeigen3-dev libflann-dev libfreeimage-dev libmetis-dev libgoogle-glog-dev libgtest-dev \
  libsqlite3-dev libglew-dev qtbase5-dev libqt5opengl5-dev libcgal-dev libceres-dev
git clone https://github.com/colmap/colmap.git && cd colmap
mkdir build && cd build && cmake .. -GNinja -DCMAKE_CUDA_ARCHITECTURES=80 && ninja && sudo ninja install
```

3.4 ROS2 Humble

```bash
# 关键:装前先解锁被 hold 的显卡驱动
GPU_DRIVER_VERSION=$(dpkg -l | grep nvidia-driver | awk '{print $3}' | cut -d. -f1)
sudo apt-mark unhold nvidia-driver-${GPU_DRIVER_VERSION}
# 官方源装 ros-humble-desktop + ros-dev-tools
sudo apt install -y ros-humble-desktop ros-dev-tools
# 装完重启后再锁回
sudo apt-mark hold nvidia-driver-${GPU_DRIVER_VERSION}
# 卡在 update-initramfs 时连按回车
```

3.5 NCCL

```bash
sudo tar -xvf nccl_2.16.5-1+cuda11.8_x86_64.txz -C /usr/local
# bashrc: LD_LIBRARY_PATH/CPATH 指向 /usr/local/nccl_2.16.5-1+cuda11.8_x86_64/{lib,include}
```

---

要点速览

| 主题 | 关键信息 |
|---|---|
| 显卡驱动 | RTX 5080 须官网 .run(不能用 apt);装前 lspci 确认;必要时 blacklist nouveau |
| 软件源 | apt 三镜像(阿里/清华/中科大);企业内网 pip 走内部镜像源 |
| 包冲突 | libopencv-dev vs intel-mkl 争 libtbb → 卸 libtbb2-dev |
| Docker | 清华源 + registry mirror;NVML 坑 → vglusers 组对齐 /dev/nvidia* GID |
| CUDA | .run --silent --toolkit 多版本共存;手动维护 /usr/local/cuda 软链 |
| cuDNN | 一套解压逐版本拷 cudnn*.h + libcudnn*,逐个 cudnn_version.h 验证 |
| ROS2 | 装前 apt-mark unhold 驱动,装完重启再 hold 回;卡 update-initramfs 连按回车 |
| Colmap | 源码编译,RTX 5080 用 CMAKE_CUDA_ARCHITECTURES=80 |

备注:本文档由原始截屏资料归并整理,个别字符以原文语境补全;执行前建议以原始文档复核。

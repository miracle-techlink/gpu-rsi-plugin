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
sudo bash -c 'cat > /etc/default/locale <<EOF
LANG=en_US.UTF-8
LANGUAGE=en_US.UTF-8
LC_CTYPE=en_US.UTF-8
LC_NUMERIC=en_US.UTF-8
LC_TIME=en_US.UTF-8
LC_COLLATE=en_US.UTF-8
LC_MONETARY=en_US.UTF-8
LC_MESSAGES=en_US.UTF-8
LC_PAPER=en_US.UTF-8
LC_NAME=en_US.UTF-8
LC_ADDRESS=en_US.UTF-8
LC_TELEPHONE=en_US.UTF-8
LC_MEASUREMENT=en_US.UTF-8
LC_IDENTIFICATION=en_US.UTF-8
LC_ALL=en_US.UTF-8
EOF'
source /etc/default/locale
sudo apt install -y --reinstall ubuntu-advantage-tools
locale   # 验证
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

2.2 基础开发环境(完整 apt 包列表)

```bash
sudo apt install -y wget curl git tmux zsh htop cloc pip
sudo apt install -y git-lfs
sudo apt install -y cmake ninja-build
sudo apt install -y libjemalloc-dev
sudo apt install -y rdma-core
sudo apt install -y intel-mkl              # 交互提示处选 NO
sudo apt install -y libmkldnn1 libmkldnn-dev libmkldnn-doc
sudo apt install -y libdnnl2 libdnnl-dev   # oneDNN
sudo apt install -y libblas-dev liblapack-dev libatlas-base-dev
sudo apt install -y libopenblas-base libopenblas-dev
sudo apt install -y openmpi-bin openmpi-doc libopenmpi-dev
sudo apt install -y opencl-headers opencl-dev ocl-icd-opencl-dev
sudo apt install -y python3-dev python3-numpy
sudo apt remove --purge libtbb2-dev -y     # 解决 libtbb 冲突,见下
sudo apt install -y libopencv-dev python3-opencv
sudo apt install -y ffmpeg
sudo apt install -y lmdb-utils liblmdb-dev python3-lmdb
sudo apt install -y libgflags-dev libgoogle-glog-dev
sudo apt install -y redis redis-server
sudo apt install -y ccache
sudo apt install -y libboost-all-dev
sudo snap install sccache --candidate --classic
sudo apt autoremove -y && sudo apt autoclean -y
sudo apt install -y texlive-full
# Google Cloud CLI(可选)
echo "deb [signed-by=/usr/share/keyrings/cloud.google.gpg] https://packages.cloud.google.com/apt cloud-sdk main" | sudo tee /etc/apt/sources.list.d/google-cloud-sdk.list
sudo apt update && sudo apt install -y google-cloud-cli
```

踩坑:
- **包冲突**:libopencv-dev 依赖 libtbb-dev,intel-mkl 依赖 libtbb2-dev,二者冲突 → 先 `sudo apt remove --purge libtbb2-dev` 再装 opencv
- texlive-full 挂起(Pregenerating ConTeXt MarkIV format):连按 10 次回车等待;可先 export LC_ALL=en_US.UTF-8 + sudo apt --fix-broken install

2.3 Docker + NVIDIA Container Toolkit

```bash
# 移除旧版
sudo apt remove -y docker docker.io containerd runc
sudo rm -f /usr/share/keyrings/nvidia-container-toolkit-keyring.gpg

# docker-ce 清华源
curl -fsSL https://mirrors.tuna.tsinghua.edu.cn/docker-ce/linux/ubuntu/gpg | \
  sudo gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg
echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] \
  https://mirrors.tuna.tsinghua.edu.cn/docker-ce/linux/ubuntu jammy stable" | \
  sudo tee /etc/apt/sources.list.d/docker.list
sudo apt update
sudo apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

# registry mirror → /etc/docker/daemon.json(见云端手册 5.7 可用源现状)
sudo systemctl daemon-reload && sudo systemctl restart docker

# NVIDIA Container Toolkit
distribution=$(. /etc/os-release; echo $ID$VERSION_ID)
curl -fsSL https://nvidia.github.io/libnvidia-container/gpgkey | \
  sudo gpg --dearmor -o /usr/share/keyrings/nvidia-container-toolkit-keyring.gpg
curl -s -L https://nvidia.github.io/libnvidia-container/$distribution/libnvidia-container.list | \
  sed 's#deb https://#deb [signed-by=/usr/share/keyrings/nvidia-container-toolkit-keyring.gpg] https://#' | \
  sudo tee /etc/apt/sources.list.d/nvidia-container-toolkit.list
sudo apt update && sudo apt install -y nvidia-docker2
sudo nvidia-ctk runtime configure --runtime=docker
sudo systemctl restart docker

# 免 sudo 跑 docker
sudo usermod -aG docker $USER

# 验证
docker run hello-world
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
# .run silent 模式只装 toolkit 不装驱动;按需选版本(11.7.1~12.9.1)
sudo sh cuda_12.9.1_575.57.08_linux.run --silent --toolkit
sudo sh cuda_12.8.1_570.124.06_linux.run --silent --toolkit
sudo sh cuda_12.6.3_560.35.05_linux.run --silent --toolkit
sudo sh cuda_12.4.1_550.54.15_linux.run --silent --toolkit
sudo sh cuda_12.1.1_530.30.02_linux.run --silent --toolkit
sudo sh cuda_11.8.0_520.61.05_linux.run --silent --toolkit
sudo sh cuda_11.7.1_515.65.01_linux.run --silent --toolkit

# 重链软链(切到要用的版本)
sudo rm /usr/local/cuda
sudo ln -s /usr/local/cuda-11.7 /usr/local/cuda

# ~/.bashrc 追加
export CUDA_HOME=/usr/local/cuda-11.7
export PATH=$CUDA_HOME/bin:$PATH
export LD_LIBRARY_PATH=$CUDA_HOME/lib64:$LD_LIBRARY_PATH
source ~/.bashrc
```

---

3. 可选配置(SSH)

3.1 cuDNN(一套 9.x 解压两份,逐版本拷进各 CUDA 目录)

```bash
# 下载: https://developer.download.nvidia.com/compute/cudnn/redist/cudnn/linux-x86_64/
sudo tar -xvf cudnn-linux-x86_64-9.10.1.4_cuda11-archive.tar.xz -C /usr/local
sudo tar -xvf cudnn-linux-x86_64-9.10.1.4_cuda12-archive.tar.xz -C /usr/local

# 清掉旧 cudnn
sudo rm -f /usr/local/cuda-*/include/cudnn.h
sudo rm -f /usr/local/cuda-*/lib64/libcudnn*

# 逐版本拷贝(每个已装 CUDA 重复;cuda11-archive 拷 11.x,cuda12-archive 拷 12.x)
for v in 11.7 11.8; do
  sudo cp -P /usr/local/cudnn-linux-x86_64-9.10.1.4_cuda11-archive/include/cudnn*.h /usr/local/cuda-$v/include/
  sudo cp -P /usr/local/cudnn-linux-x86_64-9.10.1.4_cuda11-archive/lib/libcudnn*     /usr/local/cuda-$v/lib64/
done
for v in 12.0 12.1 12.2 12.3 12.4 12.5 12.6 12.8 12.9; do
  sudo cp -P /usr/local/cudnn-linux-x86_64-9.10.1.4_cuda12-archive/include/cudnn*.h /usr/local/cuda-$v/include/
  sudo cp -P /usr/local/cudnn-linux-x86_64-9.10.1.4_cuda12-archive/lib/libcudnn*     /usr/local/cuda-$v/lib64/
done

# 逐版本验证
for v in 11.7 11.8 12.1 12.4 12.6 12.9; do
  echo "== cuda-$v =="; cat /usr/local/cuda-$v/include/cudnn_version.h | grep CUDNN_MAJOR -A 2
done
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
# 完整依赖
sudo apt-get install -y git cmake ninja-build build-essential \
  libboost-program-options-dev libboost-graph-dev libboost-system-dev \
  libeigen3-dev libflann-dev libfreeimage-dev libmetis-dev \
  libgoogle-glog-dev libgtest-dev libgmock-dev libsqlite3-dev \
  libglew-dev qtbase5-dev libqt5opengl5-dev libcgal-dev libceres-dev

git clone https://github.com/colmap/colmap.git && cd colmap
mkdir build && cd build
cmake .. -GNinja -DCMAKE_CUDA_ARCHITECTURES=80   # RTX 5080 对应 sm_80
ninja && sudo ninja install
```

3.4 ROS2 Humble

```bash
# Set locale
sudo apt update && sudo apt install -y locales
sudo locale-gen en_US en_US.UTF-8
sudo update-locale LC_ALL=en_US.UTF-8 LANG=en_US.UTF-8
export LANG=en_US.UTF-8
locale   # verify

# Setup sources
sudo apt install -y software-properties-common
sudo add-apt-repository universe
sudo apt update && sudo apt install -y curl
sudo curl -sSL https://raw.githubusercontent.com/ros/rosdistro/master/ros.key \
  -o /usr/share/keyrings/ros-archive-keyring.gpg
echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/ros-archive-keyring.gpg] \
  http://packages.ros.org/ros2/ubuntu $(. /etc/os-release && echo $UBUNTU_CODENAME) main" | \
  sudo tee /etc/apt/sources.list.d/ros2.list > /dev/null

# 关键:装前先解锁被 hold 的显卡驱动
GPU_DRIVER_VERSION=$(dpkg -l | grep nvidia-driver | awk '{print $3}' | cut -d. -f1)
sudo apt-mark unhold nvidia-driver-${GPU_DRIVER_VERSION}
apt-mark showhold

# Install
sudo apt update && sudo apt upgrade -y
sudo apt install -y ros-humble-desktop ros-dev-tools

# 测试
exec bash
source /opt/ros/humble/setup.bash
ros2 run demo_nodes_cpp talker   # 另开终端 ros2 run demo_nodes_py listener

# 装完重启后再锁回驱动
sudo reboot
GPU_DRIVER_VERSION=$(dpkg -l | grep nvidia-driver | awk '{print $3}' | cut -d. -f1)
sudo apt-mark hold nvidia-driver-${GPU_DRIVER_VERSION}

# 卸载(如需要)
sudo apt remove -y ros-humble-* && sudo apt autoremove
sudo rm /etc/apt/sources.list.d/ros2.list
sudo apt update && sudo apt upgrade -y
```

踩坑:卡在 "update-initramfs: Generating /boot/initrd.img-..." 时连按多次回车即可继续。

3.5 NCCL

```bash
# 下载: https://developer.nvidia.com/nccl/nccl-legacy-downloads
sudo tar -xvf nccl_2.16.5-1+cuda11.8_x86_64.txz -C /usr/local

# ~/.bashrc 追加
export CUDA_HOME=/usr/local/cuda-11.8
export PATH=$CUDA_HOME/bin:$PATH
export LD_LIBRARY_PATH=$CUDA_HOME/lib64:$LD_LIBRARY_PATH
export LD_LIBRARY_PATH=/usr/local/nccl_2.16.5-1+cuda11.8_x86_64/lib:$LD_LIBRARY_PATH
export CPATH=/usr/local/nccl_2.16.5-1+cuda11.8_x86_64/include:$CPATH
source ~/.bashrc
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

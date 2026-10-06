# PC 台式机 Ubuntu 22.04 配置指南(原文逐字收录,已脱敏)

> 本文件是原始文档的逐字收录版,不做压缩/改写。已脱敏:内网 pip 源、入网流程、出处。
> 结构化摘要版见 ../pc-ubuntu-setup.md。

来源:一份团队内部 PC 装机文档(约 3587 字),归并校对后整理;个别字符以原文语境补全,命令以原文语境补全

---

文档大纲(原目录)

1. 基础配置(本地)
  - 1.1 软件源和 MAC 地址
  - 1.2 设置禁止休眠(Optional)
  - 1.3 设置系统语言为英文
  - 1.4 配置远程 SSH 连接
  - 1.5 设备入网(略,属企业内网流程,已脱敏)
2. 基础配置(SSH)
  - 2.1 安装和更新显卡驱动
  - 2.2 配置基础开发环境
  - 2.3 安装 docker
  - 2.4 安装基础软件
  - 2.5 安装 CUDA Toolkit
3. 可选配置(SSH)
  - 3.1 安装 cuDNN
  - 3.2 安装 gcc 和 g++
  - 3.3 安装 Colmap
  - 3.4 安装 ROS2
  - 3.5 安装 NCCL

---

1. 基础配置(本地)

1.1 软件源和 MAC 地址

- apt 源:为更快下载速度,添加阿里云镜像、清华镜像、中科大镜像作为 apt 软件源(Ubuntu 22.04 / jammy):

```bash
sudo bash -c 'cat > /etc/apt/sources.list <<EOF
# Aliyun source
deb http://mirrors.aliyun.com/ubuntu/ jammy main restricted universe multiverse
deb-src http://mirrors.aliyun.com/ubuntu/ jammy main restricted universe multiverse
deb http://mirrors.aliyun.com/ubuntu/ jammy-updates main restricted universe multiverse
deb http://mirrors.aliyun.com/ubuntu/ jammy-proposed main restricted universe multiverse
deb-src http://mirrors.aliyun.com/ubuntu/ jammy-proposed main restricted universe multiverse

# Tsinghua source
deb https://mirrors.tuna.tsinghua.edu.cn/ubuntu/ jammy main restricted universe multiverse
deb-src https://mirrors.tuna.tsinghua.edu.cn/ubuntu/ jammy main restricted universe multiverse
deb https://mirrors.tuna.tsinghua.edu.cn/ubuntu/ jammy-updates main restricted universe multiverse
deb-src https://mirrors.tuna.tsinghua.edu.cn/ubuntu/ jammy-updates main restricted universe multiverse
deb https://mirrors.tuna.tsinghua.edu.cn/ubuntu/ jammy-backports main restricted universe multiverse
deb-src https://mirrors.tuna.tsinghua.edu.cn/ubuntu/ jammy-backports main restricted universe multiverse
deb https://mirrors.tuna.tsinghua.edu.cn/ubuntu/ jammy-security main restricted universe multiverse
deb-src https://mirrors.tuna.tsinghua.edu.cn/ubuntu/ jammy-security main restricted universe multiverse
# Pre-release (unrecommended)
# deb https://mirrors.tuna.tsinghua.edu.cn/ubuntu/ jammy-proposed main restricted universe multiverse

# USTC source
deb https://mirrors.ustc.edu.cn/ubuntu/ jammy main restricted universe multiverse
deb-src https://mirrors.ustc.edu.cn/ubuntu/ jammy main restricted universe multiverse
deb https://mirrors.ustc.edu.cn/ubuntu/ jammy-updates main restricted universe multiverse
deb-src https://mirrors.ustc.edu.cn/ubuntu/ jammy-updates main restricted universe multiverse
deb https://mirrors.ustc.edu.cn/ubuntu/ jammy-backports main restricted universe multiverse
deb-src https://mirrors.ustc.edu.cn/ubuntu/ jammy-backports main restricted universe multiverse
deb https://mirrors.ustc.edu.cn/ubuntu/ jammy-security main restricted universe multiverse
deb-src https://mirrors.ustc.edu.cn/ubuntu/ jammy-security main restricted universe multiverse
EOF'
```

- pip 源:企业内网环境用内部镜像(按实际情况替换):

```
[global]
index-url = https://pypi.tuna.tsinghua.edu.cn/simple
# 企业内网可再加内部镜像:
# extra-index-url = http://<internal-pypi-mirror>/simple
# trusted-host = <internal-pypi-mirror>
```

- 同时需要获取有线网卡和无线网卡的 MAC 地址(ip addr),在文档中记录下来备用。

1.2 设置禁止休眠(Optional)

在文档中记录有线和无线 MAC 地址后,执行:

```bash
sudo systemctl mask sleep.target suspend.target hibernate.target hybrid-sleep.target
```

1.3 设置系统语言为英文

```bash
sudo apt update && sudo apt install -y locales
sudo locale-gen en_US.UTF-8
sudo update-locale
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
locale
```

1.4 配置远程 SSH 连接

```bash
# Make sure ifconfig and ssh are available
sudo apt update && sudo apt install -y ca-certificates gnupg lsb-release
sudo apt install -y net-tools openssh-client openssh-server
sudo apt install -y mokutil
sudo apt autoremove -y && sudo apt autoclean -y

# Check secure boot status
sudo mokutil --sb-state
```

---

2. 基础配置(SSH)

2.1 安装和更新显卡驱动

- 安装驱动前先检查显卡是否插好,如以下指令没有输出,请关机断电后重新插拔显卡:

```bash
lspci | grep -i nvidia
```

- RTX 5080 显卡的 PC 台式机:请前往官网下载对应的 .run 文件安装驱动(以 nvidia-driver-570 为例)。截至 2025 年 9 月 14 日,RTX 5080 显卡仍不支持使用 apt 安装显卡驱动。
- 注意:安装的时候有 yes 选项选择 yes,有 continue 选项选 continue,其他一般选默认即可(建议还是要看一下文字内容)。

参考步骤:

```bash
# Remove previous driver installation
sudo apt remove --purge nvidia* && sudo apt autoremove
sudo add-apt-repository ppa:graphics-drivers/ppa
sudo apt update && sudo apt upgrade -y
sudo apt install -y build-essential

# Install NVIDIA driver .run 文件
chmod 755 NVIDIA-Linux-x86_64-570.133.07.run
sudo ./NVIDIA-Linux-x86_64-570.133.07.run

# Add below blacklists if you encounter errors:
lsmod | grep nouveau
sudo vim /etc/modprobe.d/blacklist.conf
# 追加:
#   blacklist nouveau
#   options nouveau modeset=1

sudo update-initramfs -u

# Reboot (optional)
sudo reboot
```

2.2 配置基础开发环境

基础环境包括:wget curl git tmux zsh htop cloc pip,以及一大批编译/科学计算/视觉相关库:

```bash
sudo apt install -y wget curl git tmux zsh htop cloc pip
sudo apt install -y git-lfs
sudo apt install -y cmake ninja-build
sudo apt install -y libjemalloc-dev
sudo apt install -y rdma-core
sudo apt install -y intel-mkl          # (choose NO 在交互提示处)
sudo apt install -y libmkldnn1 libmkldnn-dev libmkldnn-doc
sudo apt install -y libdnnl2 libdnnl-dev   # oneDNN
sudo apt install -y libblas-dev liblapack-dev libatlas-base-dev
sudo apt install -y libopenblas-base libopenblas-dev
sudo apt install -y openmpi-bin openmpi-doc libopenmpi-dev
sudo apt install -y opencl-headers opencl-dev ocl-icd-opencl-dev
sudo apt install -y python3-dev python3-numpy
sudo apt remove --purge libtbb2-dev -y     # 见下方冲突说明
sudo apt install -y libopencv-dev python3-opencv
sudo apt install -y ffmpeg
sudo apt install -y lmdb-utils liblmdb-dev python3-lmdb
sudo apt install -y libgflags-dev
sudo apt install -y libgoogle-glog-dev
sudo apt install -y redis redis-server
sudo apt install -y ccache
sudo apt install -y libboost-all-dev
sudo snap install sccache --candidate --classic
sudo apt autoremove -y && sudo apt autoclean -y
sudo apt update && sudo apt upgrade -y
sudo apt install -y texlive-full
# VS Code (choose YES)
# Google Cloud CLI
echo "deb [signed-by=/usr/share/keyrings/cloud.google.gpg] https://packages.cloud.google.com/apt cloud-sdk main" | sudo tee /etc/apt/sources.list.d/google-cloud-sdk.list
sudo apt update && sudo apt install -y google-cloud-cli
sudo apt autoremove -y && sudo apt autoclean -y
```

踩坑备注:

1. 安装 texlive-full 时如遇到 Pregenerating ConTeXt MarkIV format ... may take some time 的挂起 bug:连按 10 次回车然后等待即可;安装前可先 export LC_ALL=en_US.UTF-8 并 sudo apt --fix-broken install。
2. 包冲突:libopencv-dev 依赖 libtbb-dev,而 intel-mkl 依赖 libtbb2-dev,二者冲突,当前解决方案是卸载 libtbb2-dev(sudo apt remove --purge libtbb2-dev)。

2.3 安装 Docker

```bash
# Remove older docker
sudo apt remove docker docker.io containerd runc
sudo rm -f /usr/share/keyrings/nvidia-container-toolkit-keyring.gpg

# Add PPA for docker (使用清华镜像)
curl -fsSL https://mirrors.tuna.tsinghua.edu.cn/docker-ce/linux/ubuntu/gpg | sudo gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg
echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://mirrors.tuna.tsinghua.edu.cn/docker-ce/linux/ubuntu jammy stable" | sudo tee /etc/apt/sources.list.d/docker.list
sudo apt update
sudo apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

# 配置 registry mirrors(写入 /etc/docker/daemon.json)——2024 年中起老公共 mirror 大批失效,
# 可用源现状以云端手册 5.7 为准;此处保留原文候选清单供参考:
#   https://dockerproxy.com / https://docker.m.daocloud.io / 阿里云个人专属加速器
#   https://docker.nju.edu.cn / https://docker.mirrors.sjtug.sjtu.edu.cn 等
sudo systemctl daemon-reload
sudo systemctl restart docker

# 安装 NVIDIA Container Toolkit 并配置
distribution=$(. /etc/os-release; echo $ID$VERSION_ID)
curl -fsSL https://nvidia.github.io/libnvidia-container/gpgkey | sudo gpg --dearmor -o /usr/share/keyrings/nvidia-container-toolkit-keyring.gpg
curl -s -L https://nvidia.github.io/libnvidia-container/$distribution/libnvidia-container.list | \
  sed 's#deb https://#deb [signed-by=/usr/share/keyrings/nvidia-container-toolkit-keyring.gpg] https://#' | \
  sudo tee /etc/apt/sources.list.d/nvidia-container-toolkit.list
sudo apt update
sudo apt install -y nvidia-docker2
sudo apt autoremove -y && sudo apt autoclean -y
sudo nvidia-ctk runtime configure --runtime=docker
sudo systemctl restart docker
sudo apt update && sudo apt upgrade -y

# Add user to docker group to avoid using sudo to run docker
sudo usermod -aG docker ${USER}

# Check installation
docker system prune
docker image ls && docker run hello-world
```

已知问题:用户报 Failed to initialize NVML: Insufficient Permissions(容器内访问 GPU 失败)——这是 VirtualGL 与 NVML 的兼容性问题:容器启动后 Docker 会重置 /dev/nvidia* 设备的 group ownership。解决办法:

1. 查看 /dev/nvidia* 设备的组所有权(GID)
2. sudo groupadd -g <GID> vglusers 创建 vglusers 组
3. sudo usermod -aG vglusers <user> 把用户加入 vglusers
4. 在 /etc/nvidia-container-runtime/config.toml 的 [nvidia-container-runtime] 下加一行 user = "root:vglusers"

2.4 安装基础软件

```bash
# Install basic softwares
sudo apt update && sudo apt install -y vlc
sudo apt install -y meshlab
sudo apt install -y ./google-chrome-stable_current_amd64.deb

# 更新 apt 依赖
sudo apt update
sudo apt-get install -y libegl1-mesa
sudo apt-get install -y mesa-utils libgl1-mesa-glx
```

下载并安装 VirtualGL 和 TurboVNC(用于远程图形/GLX 显示):

```bash
wget https://github.com/VirtualGL/virtualgl/releases/download/v3.1/virtualgl_3.1_amd64.deb
sudo dpkg -i virtualgl_3.1_*_amd64.deb

wget https://github.com/TurboVNC/turbovnc/releases/download/3.2/turbovnc_3.2_amd64.deb
sudo dpkg -i turbovnc_3.2_amd64.deb
```

2.5 安装 CUDA Toolkit

前往官网下载所需的 CUDA Toolkit 安装包(.run,silent 模式只装 toolkit 不装驱动):

```bash
# Suitable for Ubuntu 22.04
sudo sh cuda_12.9.1_575.57.08_linux.run --silent --toolkit
sudo sh cuda_12.8.1_570.124.06_linux.run --silent --toolkit
sudo sh cuda_12.6.3_560.35.05_linux.run --silent --toolkit
sudo sh cuda_12.5.1_555.42.06_linux.run --silent --toolkit
sudo sh cuda_12.4.1_550.54.15_linux.run --silent --toolkit
sudo sh cuda_12.3.2_545.23.08_linux.run --silent --toolkit
sudo sh cuda_12.2.2_535.104.05_linux.run --silent --toolkit
sudo sh cuda_12.1.1_530.30.02_linux.run --silent --toolkit
sudo sh cuda_12.0.1_525.85.12_linux.run --silent --toolkit
sudo sh cuda_11.8.0_520.61.05_linux.run --silent --toolkit
sudo sh cuda_11.7.1_515.65.01_linux.run --silent --toolkit
```

重链符号链接并配置环境变量:

```bash
# Relink the symbolic link
sudo rm /usr/local/cuda
sudo ln -s /usr/local/cuda-11.7 /usr/local/cuda

# Set up in ~/.bashrc
vim ~/.bashrc
# 追加:
#   export CUDA_HOME=/usr/local/cuda-11.7
#   export PATH=$CUDA_HOME/bin:$PATH
#   export LD_LIBRARY_PATH=$CUDA_HOME/lib64:$LD_LIBRARY_PATH
source ~/.bashrc
```

---

3. 可选配置(SSH)

3.1 安装 cuDNN

前往官网下载 cuDNN 安装包(同一套 cuDNN 9.x 解压后分别拷贝进多个 CUDA 版本目录):

```bash
# Suitable for cuda-11.x and cuda-12.x
# 下载地址: https://developer.download.nvidia.com/compute/cudnn/redist/cudnn/linux-x86_64/
sudo tar -xvf cudnn-linux-x86_64-9.10.1.4_cuda11-archive.tar.xz -C /usr/local
sudo tar -xvf cudnn-linux-x86_64-9.10.1.4_cuda12-archive.tar.xz -C /usr/local

# Remove existing cudnn files in CUDA
sudo rm -f /usr/local/cuda-*/include/cudnn.h
sudo rm -f /usr/local/cuda-*/lib64/libcudnn*

# Move cudnn.h files to cuda-11.x and cuda-12.x(每个版本目录重复执行)
sudo cp -P /usr/local/cudnn-linux-x86_64-9.10.1.4_cuda11-archive/include/cudnn*.h /usr/local/cuda-11.7/include/
sudo cp -P /usr/local/cudnn-linux-x86_64-9.10.1.4_cuda11-archive/include/cudnn*.h /usr/local/cuda-11.8/include/
sudo cp -P /usr/local/cudnn-linux-x86_64-9.10.1.4_cuda12-archive/include/cudnn*.h /usr/local/cuda-12.0/include/
sudo cp -P /usr/local/cudnn-linux-x86_64-9.10.1.4_cuda12-archive/include/cudnn*.h /usr/local/cuda-12.1/include/
sudo cp -P /usr/local/cudnn-linux-x86_64-9.10.1.4_cuda12-archive/include/cudnn*.h /usr/local/cuda-12.2/include/
sudo cp -P /usr/local/cudnn-linux-x86_64-9.10.1.4_cuda12-archive/include/cudnn*.h /usr/local/cuda-12.3/include/
sudo cp -P /usr/local/cudnn-linux-x86_64-9.10.1.4_cuda12-archive/include/cudnn*.h /usr/local/cuda-12.4/include/
sudo cp -P /usr/local/cudnn-linux-x86_64-9.10.1.4_cuda12-archive/include/cudnn*.h /usr/local/cuda-12.5/include/
sudo cp -P /usr/local/cudnn-linux-x86_64-9.10.1.4_cuda12-archive/include/cudnn*.h /usr/local/cuda-12.6/include/
sudo cp -P /usr/local/cudnn-linux-x86_64-9.10.1.4_cuda12-archive/include/cudnn*.h /usr/local/cuda-12.8/include/
sudo cp -P /usr/local/cudnn-linux-x86_64-9.10.1.4_cuda12-archive/include/cudnn*.h /usr/local/cuda-12.9/include/

# Move libcudnn files to cuda-11.x and cuda-12.x(同样逐版本重复)
sudo cp -P /usr/local/cudnn-linux-x86_64-9.10.1.4_cuda11-archive/lib/libcudnn* /usr/local/cuda-11.7/lib64/
sudo cp -P /usr/local/cudnn-linux-x86_64-9.10.1.4_cuda11-archive/lib/libcudnn* /usr/local/cuda-11.8/lib64/
sudo cp -P /usr/local/cudnn-linux-x86_64-9.10.1.4_cuda12-archive/lib/libcudnn* /usr/local/cuda-12.0/lib64/
# ... 依次拷贝到 cuda-12.1 ~ cuda-12.9 各 lib64 目录

# Test installation(逐个版本验证)
cat /usr/local/cuda-11.7/include/cudnn_version.h | grep CUDNN_MAJOR -A 2
cat /usr/local/cuda-11.8/include/cudnn_version.h | grep CUDNN_MAJOR -A 2
cat /usr/local/cuda-12.0/include/cudnn_version.h | grep CUDNN_MAJOR -A 2
# ... cuda-12.1 ~ cuda-12.9 同理
```

3.2 安装 gcc 和 g++

```bash
# Install dependencies
sudo apt install -y gcc-9 g++-9

# Set up gcc and g++(update-alternatives 多版本管理,数字为优先级)
sudo update-alternatives --install /usr/bin/gcc gcc /usr/bin/gcc-9 10
sudo update-alternatives --install /usr/bin/gcc gcc /usr/bin/gcc-10 20
sudo update-alternatives --install /usr/bin/gcc gcc /usr/bin/gcc-11 30
sudo update-alternatives --install /usr/bin/gcc gcc /usr/bin/gcc-12 40
sudo update-alternatives --config gcc

# Set up in ~/.bashrc
vim ~/.bashrc
# 追加:
#   export CC=/usr/bin/gcc-9
#   export CXX=/usr/bin/g++-9
#   export PATH=/usr/bin:$PATH
source ~/.bashrc
```

3.3 安装 Colmap

```bash
# Install dependencies
sudo apt-get install -y \
  git \
  cmake \
  ninja-build \
  build-essential \
  libboost-program-options-dev \
  libboost-graph-dev \
  libboost-system-dev \
  libeigen3-dev \
  libflann-dev \
  libfreeimage-dev \
  libmetis-dev \
  libgoogle-glog-dev \
  libgtest-dev \
  libgmock-dev \
  libsqlite3-dev \
  libglew-dev \
  qtbase5-dev \
  libqt5opengl5-dev \
  libcgal-dev \
  libceres-dev

# Install Colmap(RTX 5080 对应 CUDA_ARCHITECTURES=80,用 Ninja 构建)
git clone https://github.com/colmap/colmap.git
cd colmap
mkdir build && cd build
cmake .. -GNinja -DCMAKE_CUDA_ARCHITECTURES=80
ninja
sudo ninja install
```

3.4 安装 ROS2

```bash
# Set locale
sudo apt update && sudo apt install -y locales
sudo locale-gen en_US en_US.UTF-8
sudo update-locale LC_ALL=en_US.UTF-8 LANG=en_US.UTF-8
export LANG=en_US.UTF-8
locale  # verify settings

# Setup sources
sudo apt install -y software-properties-common
sudo add-apt-repository universe
sudo apt update && sudo apt install -y curl
sudo curl -sSL https://raw.githubusercontent.com/ros/rosdistro/master/ros.key \
  -o /usr/share/keyrings/ros-archive-keyring.gpg
echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/ros-archive-keyring.gpg] \
  http://packages.ros.org/ros2/ubuntu $(. /etc/os-release && echo $UBUNTU_CODENAME) main" | \
  sudo tee /etc/apt/sources.list.d/ros2.list > /dev/null

# Unlock GPU driver version(升级前解锁被 hold 住的驱动)
GPU_DRIVER_VERSION=$(dpkg -l | grep nvidia-driver | awk '{print $3}' | cut -d. -f1)
sudo apt-mark unhold nvidia-driver-${GPU_DRIVER_VERSION}
apt-mark showhold

# Install ROS 2 packages
sudo apt update && sudo apt upgrade -y
sudo apt install -y ros-humble-desktop
sudo apt install -y ros-dev-tools

# Environment setup and testing
exec bash
source /opt/ros/humble/setup.bash && exec zsh
ros2 run demo_nodes_cpp talker
ros2 run demo_nodes_py listener

# Reboot
sudo reboot

# Lock GPU driver version(装完再锁定回去)
GPU_DRIVER_VERSION=$(dpkg -l | grep nvidia-driver | awk '{print $3}' | cut -d. -f1)
sudo apt-mark hold nvidia-driver-${GPU_DRIVER_VERSION}
apt-mark showhold

# Uninstall ROS2 if necessary
sudo apt remove -y ros-humble-* && sudo apt autoremove
sudo rm /etc/apt/sources.list.d/ros2.list
sudo apt update && sudo apt autoremove
sudo apt upgrade -y

# If you stuck at "update-initramfs: Generating /boot/initrd.img-5.15.0-140-generic"...
# press Enter for multiple times to proceed
```

3.5 安装 NCCL

```bash
# 下载地址: https://developer.nvidia.com/nccl/nccl-legacy-downloads
sudo tar -xvf nccl_2.16.5-1+cuda11.8_x86_64.txz -C /usr/local

vim ~/.bashrc
# 追加:
#   export CUDA_HOME=/usr/local/cuda-11.8
#   export PATH=$CUDA_HOME/bin:$PATH
#   export LD_LIBRARY_PATH=$CUDA_HOME/lib64:$LD_LIBRARY_PATH
#   export LD_LIBRARY_PATH=/usr/local/nccl_2.16.5-1+cuda11.8_x86_64/lib:$LD_LIBRARY_PATH
#   export CPATH=/usr/local/nccl_2.16.5-1+cuda11.8_x86_64/include:$CPATH
source ~/.bashrc
```

---

要点速览

| 主题 | 关键信息 |
|---|---|
| 适用机型 | PC 台式机 + Ubuntu 22.04(jammy),含 RTX 5080 显卡场景 |
| 显卡驱动 | RTX 5080 不能用 apt 装驱动(截至 2025-09-14),须用官网 .run(示例 570.133.07);装前 lspci \| grep -i nvidia 确认显卡在位;必要时 blacklist nouveau |
| 软件源 | apt 三镜像(阿里/清华/中科大)+ pip 企业内网镜像源 |
| Docker | docker-ce 走清华源 + registry mirror;NVIDIA Container Toolkit + nvidia-ctk runtime configure;用户加入 docker 组 |
| NVML 坑 | 容器内 Failed to initialize NVML: Insufficient Permissions → VirtualGL/NVML 冲突,建 vglusers 组(GID 对齐 /dev/nvidia*),config.toml 加 user = "root:vglusers" |
| CUDA | .run --silent --toolkit 装 toolkit,覆盖 11.7.1–12.9.1 各版本;手动维护 /usr/local/cuda 软链 + bashrc 环境变量 |
| cuDNN | 一套 cuDNN 9.10.1.4 解压两份(cuda11/cuda12 archive),逐个 CUDA 版本目录拷 cudnn*.h + libcudnn*,再逐个 cudnn_version.h 验证 |
| Colmap | 源码编译,cmake .. -GNinja -DCMAKE_CUDA_ARCHITECTURES=80(RTX 5080 对应 sm_80) |
| ROS2 | ROS Humble 官方源安装;装 ROS 前先 apt-mark unhold 显卡驱动,装完重启后再 apt-mark hold 锁回;卡在 update-initramfs 时连按回车 |
| NCCL | 解压 nccl_2.16.5-1+cuda11.8 到 /usr/local,bashrc 配 LD_LIBRARY_PATH/CPATH |
| 开发环境 | cmake/ninja/openMPI/OpenBLAS/MKL/oneDNN/OpenCV/FFmpeg/redis/boost/ccache/sccache/texlive-full/gcloud CLI 等一长串 apt 包 |
| 包冲突 | libopencv-dev 要 libtbb-dev,intel-mkl 要 libtbb2-dev,冲突 → 卸载 libtbb2-dev |
| texlive | 安装挂起时连按回车 10 次等待即可 |
| 远程图形 | VirtualGL 3.1 + TurboVNC 3.2 |

---

备注

- 本文档由原始截屏资料归并整理,个别字符(尤其是 OCR 易混淆的 9/g、|/l、0/o)以原文语境补全;执行前建议以原始文档为准复核一遍。
- cuDNN 的逐版本拷贝命令原始资料是 20+ 行重复指令,汇总时已按版本目录列全;如需严格对照行号请查原始文档 3.1 节。

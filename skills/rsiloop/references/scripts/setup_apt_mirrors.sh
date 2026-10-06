#!/bin/bash
# setup_apt_mirrors.sh — 换 apt 源(清华为主+阿里备用),幂等可重跑
# 用法: sudo bash setup_apt_mirrors.sh
# 需要 sudo;无 sudo 时跳过本步(云端容器见手册备注)
set -euo pipefail

[ "$(id -u)" -ne 0 ] && { echo "need sudo"; exit 1; }

# 阿里云 ECS 优先用内网源(免流量费)
ALI_INTERNAL=""
if curl -sf --connect-timeout 2 http://mirrors.cloud.aliyuncs.com/ >/dev/null 2>&1; then
  ALI_INTERNAL=1
fi

cp /etc/apt/sources.list /etc/apt/sources.list.bak.$(date +%Y%m%d%H%M%S)

if [ -n "$ALI_INTERNAL" ]; then
  echo "== 检测到阿里云内网,优先内网源 =="
  cat > /etc/apt/sources.list <<'EOF'
deb http://mirrors.cloud.aliyuncs.com/ubuntu/ jammy main restricted universe multiverse
deb http://mirrors.cloud.aliyuncs.com/ubuntu/ jammy-updates main restricted universe multiverse
deb http://mirrors.cloud.aliyuncs.com/ubuntu/ jammy-security main restricted universe multiverse
deb https://mirrors.tuna.tsinghua.edu.cn/ubuntu/ jammy main restricted universe multiverse
deb https://mirrors.tuna.tsinghua.edu.cn/ubuntu/ jammy-updates main restricted universe multiverse
deb https://mirrors.tuna.tsinghua.edu.cn/ubuntu/ jammy-security main restricted universe multiverse
EOF
else
  cat > /etc/apt/sources.list <<'EOF'
# Tsinghua source
deb https://mirrors.tuna.tsinghua.edu.cn/ubuntu/ jammy main restricted universe multiverse
deb https://mirrors.tuna.tsinghua.edu.cn/ubuntu/ jammy-updates main restricted universe multiverse
deb https://mirrors.tuna.tsinghua.edu.cn/ubuntu/ jammy-backports main restricted universe multiverse
deb https://mirrors.tuna.tsinghua.edu.cn/ubuntu/ jammy-security main restricted universe multiverse

# Aliyun source(备用)
deb http://mirrors.aliyun.com/ubuntu/ jammy main restricted universe multiverse
deb http://mirrors.aliyun.com/ubuntu/ jammy-updates main restricted universe multiverse
deb http://mirrors.aliyun.com/ubuntu/ jammy-security main restricted universe multiverse
EOF
fi

apt update
echo "== apt 源已切换,备份在 /etc/apt/sources.list.bak.* =="

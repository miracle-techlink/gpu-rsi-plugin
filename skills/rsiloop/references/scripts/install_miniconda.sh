#!/bin/bash
# install_miniconda.sh — aria2c 下载 + 静默安装 + 换 conda 源,幂等可重跑
# 用法: bash install_miniconda.sh   (不需要 sudo)
set -euo pipefail

MC_DIR="${MC_DIR:-$HOME/miniconda3}"
MC_SH="Miniconda3-latest-Linux-x86_64.sh"
MC_URL="https://mirrors.tuna.tsinghua.edu.cn/anaconda/miniconda/$MC_SH"

if [ ! -x "$MC_DIR/bin/conda" ]; then
  cd ~
  if command -v aria2c >/dev/null 2>&1; then
    aria2c -x16 -s16 -c "$MC_URL"
  else
    wget -c "$MC_URL"
  fi
  bash "$MC_SH" -b -p "$MC_DIR"
else
  echo "== miniconda 已装在 $MC_DIR,跳过下载安装 =="
fi

"$MC_DIR/bin/conda" init bash >/dev/null 2>&1 || true

cat > ~/.condarc <<'EOF'
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

"$MC_DIR/bin/conda" clean -i -y >/dev/null
"$MC_DIR/bin/conda" config --set auto_activate_base false
echo "== miniconda 就绪:$MC_DIR/bin/conda(source ~/.bashrc 或重开 shell 生效)=="

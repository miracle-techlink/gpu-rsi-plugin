#!/bin/bash
# install_torch.sh — 按驱动 CUDA 版本自动选 wheel 通道装 torch+torchvision
# 用法: bash install_torch.sh [venv_python]   默认用当前 python3;传 venv 的 python 路径则装进 venv
set -euo pipefail

PY="${1:-python3}"

# 从 nvidia-smi 读驱动支持的最高 CUDA,映射到 wheel 通道
CUDA_VER=$(nvidia-smi | grep -oP 'CUDA Version: \K[0-9]+\.[0-9]+' || echo "")
case "$CUDA_VER" in
  12.8|12.7|12.6) CHANNEL=cu126 ;;
  12.5|12.4)      CHANNEL=cu124 ;;
  12.3|12.2|12.1) CHANNEL=cu121 ;;
  11.8)           CHANNEL=cu118 ;;
  *)              CHANNEL=cu126; echo "== 未识别 CUDA '$CUDA_VER',默认 cu126 ==" ;;
esac
echo "== 驱动 CUDA $CUDA_VER → wheel 通道 $CHANNEL =="

if command -v uv >/dev/null 2>&1; then
  uv pip install --python "$PY" torch torchvision --index-url "https://download.pytorch.org/whl/$CHANNEL"
else
  "$PY" -m pip install torch torchvision --index-url "https://download.pytorch.org/whl/$CHANNEL"
fi

"$PY" -c "import torch; print('torch:', torch.__version__, '| cuda:', torch.version.cuda, '| gpu ok:', torch.cuda.is_available(), '|', torch.cuda.get_device_name(0) if torch.cuda.is_available() else '')"

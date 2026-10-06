#!/bin/bash
# install_flash_attn.sh — 查四元组并提示/下载匹配的预编译 wheel(不源码编译)
# 用法: bash install_flash_attn.sh [venv_python] [fa_version]
#   默认 fa_version=2.7.4.post1;四元组不匹配时打印 release 页让手动选
set -euo pipefail

PY="${1:-python3}"
FA_VER="${2:-2.7.4.post1}"

read -r TORCH CU PYVER ABI <<<"$("$PY" -c "import torch,sys; print(torch.__version__.split('+')[0], 'cu'+torch.version.cuda.split('.')[0], 'cp'+str(sys.version_info[0])+str(sys.version_info[1]), 'cxx11abi'+str(torch._C._GLIBCXX_USE_CXX11_ABI).upper())")"
echo "== 四元组: torch=$TORCH cuda=$CU py=$PYVER abi=$ABI =="

# 拼 wheel 文件名(2.7.x 命名规则;不符时去 release 页手动选)
WHEEL="flash_attn-${FA_VER}+${CU}torch${TORCH%.*}${ABI}-${PYVER}-${PYVER}-linux_x86_64.whl"
URL="https://github.com/Dao-AILab/flash-attention/releases/download/v${FA_VER}/${WHEEL}"
echo "== 尝试 wheel: $WHEEL =="

if command -v aria2c >/dev/null 2>&1; then
  aria2c -x16 -s16 -c "$URL" || { echo "!! 下载失败,四元组可能不匹配;去 https://github.com/Dao-AILab/flash-attention/releases 按 torch=$TORCH $CU $PYVER $ABI 手动选"; exit 1; }
else
  wget -c "$URL" || { echo "!! 下载失败,去 release 页手动选匹配 wheel"; exit 1; }
fi

if command -v uv >/dev/null 2>&1; then
  uv pip install --python "$PY" "./$WHEEL"
else
  "$PY" -m pip install "./$WHEEL"
fi

"$PY" -c "import flash_attn; print('flash_attn:', flash_attn.__version__)"

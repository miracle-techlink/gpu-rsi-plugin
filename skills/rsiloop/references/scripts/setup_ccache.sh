#!/bin/bash
# setup_ccache.sh — 编译缓存:装 ccache + 配 launcher + MAX_JOBS,幂等可重跑
# 用法: bash setup_ccache.sh   (装包需 sudo,配置不需要)
set -euo pipefail

if ! command -v ccache >/dev/null 2>&1; then
  sudo apt install -y ccache
fi
ccache -M 50G >/dev/null

# 幂等写 bashrc
sed -i '/# >>> ccache-rsi >>>/,/# <<< ccache-rsi <<</d' ~/.bashrc 2>/dev/null || true
cat >> ~/.bashrc <<'EOF'
# >>> ccache-rsi >>>
export CMAKE_C_COMPILER_LAUNCHER=ccache
export CMAKE_CXX_COMPILER_LAUNCHER=ccache
export CMAKE_CUDA_COMPILER_LAUNCHER=ccache
export MAX_JOBS=$(nproc)
# <<< ccache-rsi <<<
EOF

ccache -s | head -5
echo "== ccache 就绪(source ~/.bashrc 生效;多机/CI 共享换 sccache 挂 S3 后端)=="

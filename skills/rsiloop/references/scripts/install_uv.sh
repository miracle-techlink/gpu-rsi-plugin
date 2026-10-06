#!/bin/bash
# install_uv.sh — 装 uv + 配镜像源 + 性能调优,幂等可重跑
# 用法: bash install_uv.sh   (不需要 sudo)
set -euo pipefail

if ! command -v uv >/dev/null 2>&1; then
  curl -LsSf https://astral.sh/uv/install.sh | sh
fi
export PATH="$HOME/.local/bin:$PATH"

# pip 源(uv 不吃,但 pip 用户需要)
mkdir -p ~/.pip
cat > ~/.pip/pip.conf <<'EOF'
[global]
index-url = https://pypi.tuna.tsinghua.edu.cn/simple
extra-index-url = https://mirrors.aliyun.com/pypi/simple/
EOF

# uv 镜像 + 调优(写 bashrc,幂等:先删旧块再追加)
sed -i '/# >>> uv-rsi >>>/,/# <<< uv-rsi <<</d' ~/.bashrc 2>/dev/null || true
cat >> ~/.bashrc <<'EOF'
# >>> uv-rsi >>>
export PATH="$HOME/.local/bin:$PATH"
export UV_INDEX_URL=https://pypi.tuna.tsinghua.edu.cn/simple
export UV_DEFAULT_INDEX=https://pypi.tuna.tsinghua.edu.cn/simple
export UV_CONCURRENT_DOWNLOADS=100
export UV_HTTP_RETRIES=5
export UV_COMPILE_BYTECODE=1
# <<< uv-rsi <<<
EOF

uv --version
echo "== uv 就绪(source ~/.bashrc 生效镜像与调优)=="

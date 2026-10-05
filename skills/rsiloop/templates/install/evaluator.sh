#!/bin/bash
# 包安装 evaluator:计时 + import 验证一票否决。
# 输出: 单行 JSON {"ok":bool,"score":float,"seconds":float,"error":str|null}
# score = 1000/秒数。评的是"在干净 venv 里装一组固定包"的端到端耗时。
WORKDIR="${RSI_WORKDIR:-/tmp/rsi-install-eval}"
PACKAGES="${RSI_PACKAGES:-numpy einops requests}"   # 固定包集合,大小适中、无编译

set -u
mkdir -p "$WORKDIR"
cd "$(dirname "$0")"
if [ -f genome.env ]; then
  set -a; source genome.env; set +a   # genome 可定义:INSTALLER(uv/pip)、INDEX_URL、
fi                                    # UV_CONCURRENT_DOWNLOADS、UV_COMPILE_BYTECODE、ONLY_BINARY 等
fail() { echo "{\"ok\":false,\"score\":0,\"seconds\":0,\"error\":\"$1\"}"; exit 0; }

VENV="$WORKDIR/venv"
rm -rf "$VENV"   # 每轮全新环境,防缓存污染跨个体比较

start=$(date +%s.%N)
case "${INSTALLER:-uv}" in
  uv)
    uv venv "$VENV" --quiet || fail "venv failed"
    # shellcheck disable=SC2086
    UV_INDEX_URL="${INDEX_URL:-${UV_INDEX_URL:-}}" \
      uv pip install --python "$VENV/bin/python" ${ONLY_BINARY:+--only-binary :all:} $PACKAGES \
      || fail "uv pip install failed" ;;
  pip)
    python3 -m venv "$VENV" || fail "venv failed"
    # shellcheck disable=SC2086
    "$VENV/bin/pip" install -q ${INDEX_URL:+-i "$INDEX_URL"} $PACKAGES || fail "pip install failed" ;;
  *) fail "unknown INSTALLER" ;;
esac
end=$(date +%s.%N)

# import 验证
"$VENV/bin/python" -c "$(echo "$PACKAGES" | tr ' ' '\n' | sed 's/^/import /' | paste -sd';')" \
  || fail "import check failed"

secs=$(echo "$end $start" | awk '{printf "%.3f", $1-$2}')
score=$(echo "$secs" | awk '{printf "%.2f", 1000/$1}')
echo "{\"ok\":true,\"score\":$score,\"seconds\":$secs,\"error\":null}"

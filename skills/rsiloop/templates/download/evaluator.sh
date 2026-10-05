#!/bin/bash
# 下载流水线 evaluator:RSI 的"环境",唯一可信目标函数。
# 评的是 genome.env 应用后的真实下载行为:先 source genome.env,再下载固定测试文件。
#
# 输出: 单行 JSON {"ok":bool,"score":float,"mbps":float,"seconds":float,"error":str|null}
# score = 吞吐 MB/s,越高越好;哈希不匹配/下载失败 → ok=false score=0。
#
# 适配说明(拷贝后按机器改这几行):
TEST_URL="${RSI_TEST_URL:-https://mirrors.tuna.tsinghua.edu.cn/anaconda/miniconda/Miniconda3-latest-Linux-x86_64.sh}"
TEST_SHA256="${RSI_TEST_SHA256:-}"   # 留空则只校验文件完整(非0字节+可重跑),建议填真实 sha256
WORKDIR="${RSI_WORKDIR:-/tmp/rsi-download-eval}"
RUNS=2                                # 小耗时噪声大,取最好一次(下载场景缓存友好)

set -u
mkdir -p "$WORKDIR"
cd "$(dirname "$0")"

# 应用基因型:genome.env 里可定义 TOOL(aria2c/wget/curl)、THREADS、MIRROR_PREFIX、
# EXTRA_OPTS、以及 HF_ENDPOINT 等环境变量——evaluator 只管执行,不管语义。
if [ -f genome.env ]; then
  set -a; source genome.env; set +a
fi

TOOL="${TOOL:-aria2c}"
URL="${MIRROR_PREFIX:-}${TEST_URL}"
TARGET="$WORKDIR/testfile"
fail() { echo "{\"ok\":false,\"score\":0,\"mbps\":0,\"seconds\":0,\"error\":\"$1\"}"; exit 0; }

best_mbps=0
for i in $(seq 1 "$RUNS"); do
  rm -f "$TARGET" "$TARGET.aria2"
  start=$(date +%s.%N)
  case "$TOOL" in
    aria2c)
      # 环境里格式不规范的 all_proxy 会被 aria2c 自动读取并直接崩,先清掉;
      # 确需代理时由 genome.env 显式设 RSI_ARIA2_PROXY(必须是合法 http:// 形式)
      PROXY_ARGS=""
      case "${RSI_ARIA2_PROXY:-}" in http://*|https://*) PROXY_ARGS="--all-proxy=$RSI_ARIA2_PROXY";; esac
      # shellcheck disable=SC2086
      env -u all_proxy -u ALL_PROXY \
        aria2c ${EXTRA_OPTS:--x${THREADS:-16} -s${THREADS:-16} -k1M -c} \
        $PROXY_ARGS -q -d "$WORKDIR" -o testfile "$URL" || fail "download failed (run $i)" ;;
    wget)
      wget ${EXTRA_OPTS:--q} -O "$TARGET" "$URL" || fail "download failed (run $i)" ;;
    curl)
      curl ${EXTRA_OPTS:--sSfL} -o "$TARGET" "$URL" || fail "download failed (run $i)" ;;
    *) fail "unknown TOOL=$TOOL" ;;
  esac
  end=$(date +%s.%N)

  [ -s "$TARGET" ] || fail "empty file (run $i)"
  if [ -n "$TEST_SHA256" ]; then
    echo "$TEST_SHA256  $TARGET" | sha256sum -c - >/dev/null 2>&1 || fail "sha256 mismatch (run $i)"
  fi

  secs=$(echo "$end $start" | awk '{printf "%.3f", $1-$2}')
  size_mb=$(stat -c%s "$TARGET" | awk '{printf "%.2f", $1/1048576}')
  mbps=$(echo "$size_mb $secs" | awk '{printf "%.2f", ($secs>0)? $1/$2 : 0}')
  best_mbps=$(echo "$best_mbps $mbps" | awk '{print ($2>$1)?$2:$1}')
  best_secs=$secs
done

rm -f "$TARGET" "$TARGET.aria2"
echo "{\"ok\":true,\"score\":$best_mbps,\"mbps\":$best_mbps,\"seconds\":$best_secs,\"error\":null}"

#!/bin/bash
# 编译流水线 evaluator:计时 + 产物冒烟测试一票否决。
# 输出: 单行 JSON {"ok":bool,"score":float,"seconds":float,"error":str|null}
# score = 1000/秒数,越高越好。
#
# 适配说明:BUILD_CMD 是被测编译命令(默认一个小型 C 项目;真实场景换成
# pip wheel 构建/cmake 项目),SMOKE_CMD 验证产物可运行。
WORKDIR="${RSI_WORKDIR:-/tmp/rsi-compile-eval}"

set -u
mkdir -p "$WORKDIR/build"
cd "$(dirname "$0")"
if [ -f genome.env ]; then
  set -a; source genome.env; set +a   # genome 可定义:USE_CCACHE、MAX_JOBS、GENERATOR、CC 等
fi
fail() { echo "{\"ok\":false,\"score\":0,\"seconds\":0,\"error\":\"$1\"}"; exit 0; }

# 准备被测源码(幂等):7 个普通 TU + 1 个带 main 的 TU,避免链接冲突
if [ ! -f "$WORKDIR/tu_main.c" ]; then
  cat > "$WORKDIR/tu_common.h" <<'EOF'
double work(long n);
EOF
  for i in 1 2 3 4 5 6 7; do
    cat > "$WORKDIR/tu$i.c" <<EOF
#include <math.h>
double work$i(long n){ double s=0; for(long k=0;k<n;k++) s+=sqrt((double)(k+$i)); return s; }
EOF
  done
  cat > "$WORKDIR/tu_main.c" <<'EOF'
#include <stdio.h>
double work1(long),work2(long),work3(long),work4(long),work5(long),work6(long),work7(long);
int main(void){ double s=work1(100000)+work2(100000)+work3(100000)+work4(100000)+work5(100000)+work6(100000)+work7(100000); printf("%.0f\n",s); return 0; }
EOF
fi

# 编译环境基因型应用
JOBS="${MAX_JOBS:-$(nproc)}"
LAUNCHER=""
[ "${USE_CCACHE:-0}" = "1" ] && command -v ccache >/dev/null && LAUNCHER="ccache"

start=$(date +%s.%N)
# 8 个 TU 串行编译,放大耗时降低噪声
for tu in tu1 tu2 tu3 tu4 tu5 tu6 tu7 tu_main; do
  cp "$WORKDIR/$tu.c" "$WORKDIR/build/$tu.c"
  # shellcheck disable=SC2086
  $LAUNCHER ${CC:-cc} -O2 -c "$WORKDIR/build/$tu.c" -o "$WORKDIR/build/$tu.o" || fail "compile failed ($tu)"
done
${CC:-cc} -O2 "$WORKDIR/build/"*.o -lm -o "$WORKDIR/build/prog" || fail "link failed"
end=$(date +%s.%N)

# 冒烟:产物必须跑通
"$WORKDIR/build/prog" >/dev/null 2>&1 || fail "smoke test failed"

secs=$(echo "$end $start" | awk '{printf "%.3f", $1-$2}')
score=$(echo "$secs" | awk '{printf "%.2f", 1000/$1}')
rm -rf "$WORKDIR/build"; mkdir -p "$WORKDIR/build"   # 不清 ccache 缓存——那正是基因型的一部分
echo "{\"ok\":true,\"score\":$score,\"seconds\":$secs,\"error\":null}"

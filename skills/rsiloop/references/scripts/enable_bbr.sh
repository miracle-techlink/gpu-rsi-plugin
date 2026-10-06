#!/bin/bash
# enable_bbr.sh — 开 BBR + 调大 TCP 缓冲区,幂等可重跑
# 用法: sudo bash enable_bbr.sh   (需要 sudo;容器内改不了可跳过)
set -euo pipefail

[ "$(id -u)" -ne 0 ] && { echo "need sudo"; exit 1; }

# 内核 >= 4.9 才有 BBR
KVER=$(uname -r | cut -d. -f1-2)
awk -v k="$KVER" 'BEGIN{ split(k,a,"."); if(a[1]<4 || (a[1]==4 && a[2]<9)) { print "kernel " k " too old for BBR"; exit 1 } }'

# 幂等:先删旧块再追加
sed -i '/# >>> bbr-rsi >>>/,/# <<< bbr-rsi <<</d' /etc/sysctl.conf
cat >> /etc/sysctl.conf <<'EOF'

# >>> bbr-rsi >>>
net.core.default_qdisc = fq
net.ipv4.tcp_congestion_control = bbr
net.core.rmem_max = 134217728
net.core.wmem_max = 134217728
net.ipv4.tcp_rmem = 4096 87380 134217728
net.ipv4.tcp_wmem = 4096 65536 134217728
net.ipv4.tcp_fastopen = 3
net.ipv4.tcp_mtu_probing = 1
# <<< bbr-rsi <<<
EOF
sysctl -p >/dev/null

CC=$(sysctl -n net.ipv4.tcp_congestion_control)
[ "$CC" = "bbr" ] && echo "== BBR 已开启 ==" || { echo "!! 开启失败,当前=$CC"; exit 1; }

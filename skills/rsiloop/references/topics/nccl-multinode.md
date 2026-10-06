# 多机分布式训练网络与 NCCL 调优

适用:多机多卡训练(Robust/DDP/FSDP),NCCL 通信成为瓶颈时的排查与调优。

---

## 1. 网络拓扑确认(先搞清楚走哪张网)

```bash
# 看有哪些网卡、速率
ibstat 2>/dev/null || ibv_devices      # InfiniBand/RoCE
ip -br link                            # 以太网卡
ethtool eth0 | grep Speed              # 单卡速率
```

**原则**:NCCL 走 IB/RoCE 就走 IB,没有再走以太网;**严禁让 NCCL 走 1G 管理网**。

## 2. NCCL 关键环境变量(~/.bashrc 或启动脚本)

```bash
# 指定网卡(IB 场景填 IB 口;RoCE 场景填 RoCE 口;以太网填对应 ethX)
export NCCL_IB_HCA=mlx5_0,mlx5_1        # IB:指定 HCA 卡,不指定会乱选
# export NCCL_SOCKET_IFNAME=eth0        # 以太网/RoCE fallback:指定网卡名

# 拓扑与算法
export NCCL_IB_GID_INDEX=3              # RoCE v2 必须;纯 IB 不用设
export NCCL_IB_TIMEOUT=22               # 网络抖动大时调大(默认 18)
export NCCL_NSOBS_PERTHREAD=1
export NCCL_SOCKET_NTHREADS=4

# 调试(排查时开,定位完关)
# export NCCL_DEBUG=INFO
# export NCCL_DEBUG_SUBSYS=ALL

# 性能相关
export NCCL_BUFFSIZE=8388608            # 8MB,大模型梯度同步可调大
export NCCL_NTHREADS=512                # 每 SM 线程数,默认 512
export NCCL_NET_GDR_LEVEL=5             # GPUDirect RDMA:0-5,IB 环境建议 5
```

## 3. 验证:nccl-tests(必须实测,不猜)

```bash
# 装 nccl-tests
git clone https://github.com/NVIDIA/nccl-tests.git
cd nccl-tests && make MPI=1 MPI_HOME=/usr/lib/x86_64-linux-gnu/openmpi -j$(nproc)

# 单机 8 卡 all_reduce(先过这关再跨机)
./build/all_reduce_perf -b 128M -e 4G -f 2 -g 8

# 跨机 2 节点 16 卡
mpirun -np 16 -H node1:8,node2:8 \
  --mca btl_tcp_if_include eth0 \
  -x NCCL_IB_HCA=mlx5_0,mlx5_1 \
  -x NCCL_IB_GID_INDEX=3 \
  ./build/all_reduce_perf -b 128M -e 4G -f 2 -g 1
```

**看什么**:busbw(总线带宽)应接近理论值——8 卡 NVLink 单机 A100 约 200+ GB/s;跨机 IB HDR 200G 约 23 GB/s。差一个数量级就是走错了网卡或没开 GPUDirect。

## 4. 常见坑

| 现象 | 原因 | 解法 |
|---|---|---|
| busbw 个位数 GB/s | 走了管理网/没指定 NCCL_IB_HCA | 显式设 NCCL_IB_HCA 或 NCCL_SOCKET_IFNAME |
| 跨机 hang 住 | 防火墙挡了 NCCL 端口/IB GID 错 | NCCL_IB_GID_INDEX=3(RoCE);开端口 |
| `NCCL WARN Call to ibv_modify_qp failed` | IB 驱动/固件不兼容 | 升级 MLNX_OFED;或 fallback NCCL_IB_DISABLE=1 走 socket |
| 训练慢但 nccl-tests 正常 | 不是通信瓶颈,是计算/数据加载 | 转 profiling-toolchain.md 定位 |
| 大小消息延迟差异大 | NCCL_BUFFSIZE 太小 | 调大到 8M~16M |

## 5. 与 RSILoop 的结合点

NCCL 调优是典型的"有硬指标可进化"场景:
- **evaluator**:固定消息大小跑 all_reduce_perf,score = busbw
- **变异空间**:NCCL_IB_HCA 组合、NCCL_BUFFSIZE、NCCL_NTHREADS、NCCL_NET_GDR_LEVEL
- **一票否决**:nccl-tests 报错/hang(超时)→ score=0

可建 `~/rsi/nccl/` domain 让 rsiloop 自主扫这些参数找本集群最优组合。

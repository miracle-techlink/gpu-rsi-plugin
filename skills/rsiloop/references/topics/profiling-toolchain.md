# 性能剖析工具链:定位 GPU 训练/推理瓶颈

适用:训练吞吐低、GPU 利用率不满、迭代延迟高的根因定位。原则:**先 profile 再优化,不猜**。

---

## 1. 分层定位法(从外到内)

```
GPU 利用率低?
├─ nvidia-smi / nvtop → 利用率 <80% → 瓶颈在数据加载或 CPU 侧
│   └─ 转第 3 节 dataloader/CPU profiling
├─ 利用率高但吞吐低? → 算子效率问题
│   └─ 转第 4 节 nsys/ncu
└─ 跨机训练慢? → 通信瓶颈
    └─ 转 nccl-multinode.md
```

## 2. 快速三件套(30 秒先看个大概)

```bash
# GPU 侧:利用率、显存、功耗、温度
nvtop                            # 交互式,比 nvidia-smi 直观
# 或 watch -n1 nvidia-smi

# IO 侧:磁盘/网络是否打满
iostat -x 2                      # util% 接近 100 = 磁盘瓶颈
nethogs                          # 哪个进程在吃带宽

# CPU 侧:是否被 dataloader/预处理卡住
htop                             # CPU 核是否跑满
py-spy top --pid <train_pid>     # Python 进程级火焰图,看主线程卡在哪
```

## 3. dataloader/CPU 瓶颈(PyTorch 专属)

```python
# 训练脚本里埋点:看每个 step 的数据等待时间
import time
for batch in dataloader:
    t0 = time.time()
    # ... forward/backward ...
    t1 = time.time()
    # data_time 占比高 = dataloader 瓶颈
```

**优化方向**(按性价比排序):
```python
DataLoader(dataset,
    num_workers=8,              # 默认 0 是主进程加载,必改;一般 = CPU 核数/2
    pin_memory=True,            # GPU 训练必开,锁页内存加速 H2D 拷贝
    prefetch_factor=4,          # 每个 worker 预取 4 个 batch
    persistent_workers=True,    # epoch 间不销毁 worker,省重建开销
)
# 还不行:数据预处理挪 GPU(NVIDIA DALI),或先离线预处理存 LMDB/TFRecord
```

## 4. GPU 算子瓶颈(nsys + ncu)

```bash
# nsys:时间线视角,看 kernel 调度空隙、H2D/D2H 拷贝、通信重叠
nsys profile -o report python train.py
nsys stats report.nsys-rep | head -50    # 看 cuda kernel/memcpy/memset 占比

# ncu:单 kernel 视角,看 SM 利用率、显存带宽、occupancy
ncu --set full -o kernel_report python -c "
import torch
x = torch.randn(4096, 4096, device='cuda')
y = x @ x    # 只 profile 这一个算子
"
ncu --import kernel_report.ncu-rep --page details
```

**看什么**:
- nsys:kernel 之间空隙大 = CPU launch 跟不上或同步太多;memcpy 占比高 = H2D 瓶颈
- ncu:SM busy <60% 且显存带宽 <50% = occupancy 低(block/grid 配错);显存带宽 >80% = memory-bound 算子(考虑算子融合/混合精度)

## 5. 混合精度与编译优化(确认是算子瓶颈后再上)

```python
# 混合精度(几乎免费,先开)
torch.autocast(device_type='cuda', dtype=torch.bfloat16):
    out = model(x)

# torch.compile(triton 后端,2.x 一键加速;版本匹配见 cloud-gpu-setup.md 4.1)
model = torch.compile(model, mode='max-autotune')

# 算子融合/flash-attn(见 cloud-gpu-setup.md 4.2)
```

## 6. 与 RSILoop 的结合点

dataloader 参数、num_workers、混合精度开关、torch.compile mode 都是可进化的离散/连续变量:
- **evaluator**:固定 N 个 step 计时,score = samples/sec
- **变异空间**:num_workers/pin_memory/prefetch_factor、autocast dtype、compile mode、batch size
- **一票否决**:OOM / loss NaN / 结果校验失败 → score=0

建 `~/rsi/train-throughput/` domain 让 rsiloop 自主扫参,比手工二分快且不漏组合。
```

---

要点速览

| 层 | 工具 | 看什么 |
|---|---|---|
| 概览 | nvtop / iostat / nethogs / htop / py-spy | 30 秒定位瓶颈在哪一层 |
| dataloader | 埋点 data_time + DataLoader 参数 | data_time 占比 |
| GPU 时间线 | nsys | kernel 空隙、memcpy 占比 |
| 单算子 | ncu | SM 利用率、显存带宽、occupancy |
| 通信 | nccl-tests(见 nccl-multinode.md) | busbw 是否接近理论值 |

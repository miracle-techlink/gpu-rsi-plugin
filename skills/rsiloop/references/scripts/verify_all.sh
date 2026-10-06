#!/bin/bash
# verify_all.sh — 总验证:torch/flash_attn/deepspeed/GPU 算子,输出单行 JSON 供 evaluator 用
# 用法: bash verify_all.sh [venv_python]
PY="${1:-python3}"
"$PY" - <<'EOF'
import json
out = {"ok": True, "error": None}
try:
    import torch
    out["torch"] = torch.__version__
    out["cuda"] = torch.version.cuda
    out["gpu_ok"] = torch.cuda.is_available()
    if out["gpu_ok"]:
        out["gpu_name"] = torch.cuda.get_device_name(0)
        x = torch.randn(1024, 1024, device="cuda")
        out["matmul_ok"] = bool((x @ x).sum().item() != 0)
    else:
        out["ok"] = False; out["error"] = "cuda not available"
    try:
        import flash_attn; out["flash_attn"] = flash_attn.__version__
    except Exception as e:
        out["flash_attn"] = None; out["flash_attn_err"] = str(e)
    try:
        import deepspeed; out["deepspeed"] = deepspeed.__version__
    except Exception as e:
        out["deepspeed"] = None; out["deepspeed_err"] = str(e)
except Exception as e:
    out = {"ok": False, "error": str(e)}
print(json.dumps(out))
EOF

#!/usr/bin/env python3
"""One-off: dequantize flux2_dev_fp8mixed to bf16 for MPS (no fp8 support).

fp8 layers carry per-tensor weight_scale; bf16 = fp8.float() * scale.
Drops *_scale tensors and quantization metadata. Run with ComfyUI venv python.
"""

import json

import torch
from safetensors import safe_open
from safetensors.torch import save_file

SRC = "/Users/wulff/ComfyUI-Shared/models/diffusion_models/flux2_dev_fp8mixed.safetensors"
DST = "/Users/wulff/ComfyUI-Shared/models/diffusion_models/flux2_dev_bf16_dequant.safetensors"

out = {}
with safe_open(SRC, framework="pt", device="cpu") as f:
    meta = f.metadata() or {}
    qmeta = json.loads(meta.get("_quantization_metadata", "{}"))
    qlayers = set(qmeta.get("layers", {}))
    print(f"{len(qlayers)} quantized layers")
    for key in f.keys():
        if key.endswith((".weight_scale", ".input_scale")):
            continue
        t = f.get_tensor(key)
        if t.dtype == torch.float8_e4m3fn:
            layer = key.rsplit(".", 1)[0]
            assert layer in qlayers, key
            scale = f.get_tensor(layer + ".weight_scale").float()
            t = (t.float() * scale).to(torch.bfloat16)
        out[key] = t

print(f"saving {len(out)} tensors -> {DST}")
save_file(out, DST)
print("done")

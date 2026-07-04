#!/usr/bin/env python3
"""Generate images locally with Flux.2 dev via ComfyUI API.

Starts the ComfyUI server (bin/comfyui-server.sh) if not already running,
submits a text-to-image workflow, waits, and saves the PNG.

Usage:
    bin/generate-image.py "a copper cube on a checkerboard" -o /abs/out.png
    bin/generate-image.py "..." --width 640 --height 512 --seed 42
    bin/generate-image.py "..." --no-turbo --steps 20   # full quality, slow

Defaults: Turbo LoRA, 8 steps, guidance 2.5 (turbo) / 4.0 (full).
Stdlib only — no venv needed to run this script.
"""

import argparse
import json
import random
import subprocess
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path

SERVER = "http://127.0.0.1:8188"
PROJECT = Path(__file__).resolve().parent.parent

# bf16 dequant of flux2_dev_fp8mixed — MPS has no fp8 kernels
# (regenerate with tools/convert-fp8-to-bf16.py)
MODEL = "flux2_dev_bf16_dequant.safetensors"
TEXT_ENCODER = "mistral_3_small_flux2_bf16.safetensors"
VAE = "full_encoder_small_decoder.safetensors"
TURBO_LORA = "Flux_2-Turbo-LoRA_comfyui.safetensors"


def build_workflow(args: argparse.Namespace, seed: int) -> dict:
    """Flux.2 dev t2i workflow in ComfyUI API format."""
    model_ref = ["unet", 0]
    wf = {
        "unet": {
            "class_type": "UNETLoader",
            "inputs": {"unet_name": MODEL, "weight_dtype": "default"},
        },
        "clip": {
            "class_type": "CLIPLoader",
            "inputs": {"clip_name": TEXT_ENCODER, "type": "flux2",
                       "device": "default"},
        },
        "vae": {
            "class_type": "VAELoader",
            "inputs": {"vae_name": VAE},
        },
        "encode": {
            "class_type": "CLIPTextEncode",
            "inputs": {"text": args.prompt, "clip": ["clip", 0]},
        },
        "guidance": {
            "class_type": "FluxGuidance",
            "inputs": {"guidance": args.guidance, "conditioning": ["encode", 0]},
        },
        "noise": {
            "class_type": "RandomNoise",
            "inputs": {"noise_seed": seed},
        },
        "sampler_sel": {
            "class_type": "KSamplerSelect",
            "inputs": {"sampler_name": "euler"},
        },
        "sigmas": {
            "class_type": "Flux2Scheduler",
            "inputs": {"steps": args.steps, "width": args.width,
                       "height": args.height},
        },
        "latent": {
            "class_type": "EmptyFlux2LatentImage",
            "inputs": {"width": args.width, "height": args.height,
                       "batch_size": 1},
        },
        "decode": {
            "class_type": "VAEDecode",
            "inputs": {"samples": ["sample", 0], "vae": ["vae", 0]},
        },
        "save": {
            "class_type": "SaveImage",
            "inputs": {"filename_prefix": "genimage", "images": ["decode", 0]},
        },
    }
    if args.turbo:
        wf["lora"] = {
            "class_type": "LoraLoaderModelOnly",
            "inputs": {"lora_name": TURBO_LORA, "strength_model": 1.0,
                       "model": model_ref},
        }
        model_ref = ["lora", 0]
    wf["guider"] = {
        "class_type": "BasicGuider",
        "inputs": {"model": model_ref, "conditioning": ["guidance", 0]},
    }
    wf["sample"] = {
        "class_type": "SamplerCustomAdvanced",
        "inputs": {
            "noise": ["noise", 0],
            "guider": ["guider", 0],
            "sampler": ["sampler_sel", 0],
            "sigmas": ["sigmas", 0],
            "latent_image": ["latent", 0],
        },
    }
    return wf


def api(path: str, payload: dict | None = None) -> dict:
    req = urllib.request.Request(SERVER + path)
    if payload is not None:
        req.data = json.dumps(payload).encode()
        req.add_header("Content-Type", "application/json")
    with urllib.request.urlopen(req, timeout=30) as r:
        return json.loads(r.read())


def server_up() -> bool:
    try:
        api("/system_stats")
        return True
    except (urllib.error.URLError, OSError):
        return False


def ensure_server() -> None:
    if server_up():
        return
    log = PROJECT / "tools" / "comfyui" / "server.log"
    print(f"Starting ComfyUI server (log: {log}) ...", file=sys.stderr)
    with open(log, "ab") as lf:
        subprocess.Popen(
            [str(PROJECT / "bin" / "comfyui-server.sh")],
            stdout=lf, stderr=lf, start_new_session=True,
        )
    for _ in range(120):
        time.sleep(1)
        if server_up():
            print("Server ready.", file=sys.stderr)
            return
    sys.exit("ComfyUI server did not come up in 120s — check " + str(log))


def generate(args: argparse.Namespace) -> Path:
    seed = args.seed if args.seed is not None else random.randrange(2**48)
    wf = build_workflow(args, seed)
    res = api("/prompt", {"prompt": wf, "client_id": "generate-image-cli"})
    if "prompt_id" not in res:
        sys.exit(f"Submit failed: {res}")
    pid = res["prompt_id"]
    print(f"Queued {pid} (seed {seed}, {args.steps} steps, "
          f"{'turbo' if args.turbo else 'full'}) ...", file=sys.stderr)

    t0 = time.time()
    while True:
        time.sleep(2)
        hist = api(f"/history/{pid}")
        if pid in hist:
            entry = hist[pid]
            status = entry.get("status", {})
            if status.get("status_str") == "error":
                msgs = [m for m in status.get("messages", [])
                        if m[0] == "execution_error"]
                sys.exit(f"Execution error: {json.dumps(msgs, indent=2)}")
            if entry.get("outputs"):
                break
        if time.time() - t0 > args.timeout:
            sys.exit(f"Timed out after {args.timeout}s (job {pid} still running)")

    images = [img for out in entry["outputs"].values()
              for img in out.get("images", [])]
    if not images:
        sys.exit("Job finished but produced no images")
    img = images[0]
    q = urllib.parse.urlencode({"filename": img["filename"],
                                "subfolder": img.get("subfolder", ""),
                                "type": img.get("type", "output")})
    with urllib.request.urlopen(f"{SERVER}/view?{q}", timeout=60) as r:
        data = r.read()
    out = Path(args.output).resolve()
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_bytes(data)
    print(f"Done in {time.time() - t0:.0f}s -> {out}", file=sys.stderr)
    return out


def main() -> None:
    p = argparse.ArgumentParser(description="Flux.2 image generation via local ComfyUI")
    p.add_argument("prompt")
    p.add_argument("-o", "--output", required=True, help="output PNG path")
    p.add_argument("--width", type=int, default=1024)
    p.add_argument("--height", type=int, default=1024)
    p.add_argument("--steps", type=int, default=None,
                   help="default: 8 turbo, 20 full")
    p.add_argument("--guidance", type=float, default=None,
                   help="default: 2.5 turbo, 4.0 full")
    p.add_argument("--seed", type=int, default=None)
    p.add_argument("--no-turbo", dest="turbo", action="store_false",
                   help="skip Turbo LoRA (slower, max quality)")
    p.add_argument("--timeout", type=int, default=1800)
    args = p.parse_args()
    if args.steps is None:
        args.steps = 8 if args.turbo else 20
    if args.guidance is None:
        args.guidance = 2.5 if args.turbo else 4.0
    if args.width % 16 or args.height % 16:
        sys.exit("width/height must be multiples of 16")

    ensure_server()
    print(str(generate(args)))


if __name__ == "__main__":
    main()

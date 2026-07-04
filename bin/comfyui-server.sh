#!/bin/sh
# Launch ComfyUI server (MPS) with shared model dir. Listens on 127.0.0.1:8188.
DIR="$(cd "$(dirname "$0")/.." && pwd)"
exec "$DIR/tools/comfyui/.venv/bin/python" "$DIR/tools/comfyui/main.py" \
    --listen 127.0.0.1 --port 8188 \
    --extra-model-paths-config "$DIR/tools/comfyui/extra_model_paths.yaml" \
    --output-directory /Users/wulff/ComfyUI-Shared/output \
    --input-directory /Users/wulff/ComfyUI-Shared/input \
    "$@"

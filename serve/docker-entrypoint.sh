#!/usr/bin/env bash
# Container entrypoint: checks the mounted checkpoint, the visible GPUs, the first-serve toolchain against the host
# driver and /dev/shm, then execs serve/serve.sh (the v2.5.1 launcher with this checkpoint's sidecar and the xhigh
# default). Extra arguments go to `vllm serve`, as with serve/serve.sh.
#
#   docker run ... swift1.5-qwen38-flash-next-3090s:v2.5.1-swift1.5 [/path/inside/container/to/checkpoint] [extra vllm args]
#
# A first argument that starts with `-` is a vllm argument: the default checkpoint path /model is used. Serve knobs
# are serve/serve.sh's environment variables (PORT, HOST, MODEL_NAME, SCALES, COUNTERS, VLLM_API_KEY, ...): pass them
# with -e.
#
# Every probe below is guarded: a missing or failing nvidia-smi skips its check with a note, it never ends the script
# silently under `set -e`.
set -euo pipefail
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

CKPT=/model
if [ $# -gt 0 ]; then
  case "$1" in -*) ;; "") shift ;; *) CKPT="$1"; shift ;; esac
fi

if [ ! -f "$CKPT/config.json" ]; then
  echo "checkpoint not found at $CKPT (no config.json)" >&2
  echo "mount it: -v /path/to/Swift1.5-Qwen3.8-Flash-Next-W4A16-Merlin:/model:ro" >&2
  exit 1
fi
if ! ls "$CKPT"/*.safetensors >/dev/null 2>&1; then
  echo "no *.safetensors in $CKPT: is the mount the checkpoint directory itself?" >&2
  exit 1
fi
# The published checkpoint carries this key; the engine's launcher needs it and the mount may be read-only.
if ! python3 -c 'import json,sys; c=json.load(open(sys.argv[1])); sys.exit(0 if c.get("text_config",{}).get("ple_embedding_dtype")=="float8_e4m3fn" else 1)' "$CKPT/config.json"; then
  echo "config.json lacks text_config.ple_embedding_dtype = float8_e4m3fn: this is not the published checkpoint" >&2
  echo "(hf download halt95/Swift1.5-Qwen3.8-Flash-Next-W4A16-Merlin at the revision README.md pins)" >&2
  exit 1
fi

# GPUs. nvidia-smi exists only when the NVIDIA container runtime injected it (docker run --gpus ...).
ngpu=""
if command -v nvidia-smi >/dev/null 2>&1; then
  ngpu="$(nvidia-smi -L 2>/dev/null | grep -c '^GPU ' || true)"
fi
if [ -z "$ngpu" ] || [ "$ngpu" = 0 ]; then
  echo "WARNING: no NVIDIA GPU visible in the container. Start it with --gpus all, with nvidia-container-toolkit on"
  echo "         the host, registered with: sudo nvidia-ctk runtime configure --runtime=docker && sudo systemctl restart docker"
elif [ "$ngpu" -lt 4 ]; then
  echo "the serving profile needs 4 GPUs but the container sees $ngpu (pass them with --gpus all)" >&2
  exit 1
fi

# First-serve toolchain: FlashInfer compiles with the nvcc at CUDA_HOME; kernels from an nvcc newer than the driver's
# CUDA version are rejected at load ("Unsupported .version"). Refuse that combination up front.
[ -x "${CUDA_HOME:-}/bin/nvcc" ] || { echo "no nvcc at CUDA_HOME=${CUDA_HOME:-unset}" >&2; exit 1; }
[ -e "$CUDA_HOME/lib64/libcudart.so" ] || { echo "$CUDA_HOME/lib64/libcudart.so missing" >&2; exit 1; }
nv_rel="$("$CUDA_HOME/bin/nvcc" --version 2>/dev/null | sed -n 's/.*release \([0-9][0-9]*\.[0-9][0-9]*\),.*/\1/p' | head -1 || true)"
drv_rel=""
if command -v nvidia-smi >/dev/null 2>&1; then
  drv_rel="$(nvidia-smi 2>/dev/null | sed -n 's/.*CUDA \(UMD \)\{0,1\}Version: *\([0-9][0-9]*\.[0-9][0-9]*\).*/\2/p' | head -1 || true)"
fi
if [ -z "$nv_rel" ] || [ -z "$drv_rel" ]; then
  echo "note: could not read the nvcc (${nv_rel:-?}) or driver (${drv_rel:-?}) CUDA version; the nvcc-versus-driver check is skipped"
elif [ "$(printf '%s\n%s\n' "$nv_rel" "$drv_rel" | sort -V | tail -1)" != "$drv_rel" ]; then
  echo "nvcc at $CUDA_HOME is CUDA $nv_rel but the driver supports CUDA $drv_rel: kernels compiled on the first" >&2
  echo "serve would be rejected. Upgrade the host driver (CUDA 13.0 or newer; docs/reference.md, Build and serve)." >&2
  exit 1
fi

# Shared memory and pinned memory: warnings, not failures.
shm_kb="$(df -Pk /dev/shm 2>/dev/null | awk 'NR==2{print $2}' || true)"
case "$shm_kb" in ''|*[!0-9]*) shm_kb="" ;; esac
if [ -n "$shm_kb" ] && [ "$shm_kb" -lt 1048576 ]; then
  echo "WARNING: /dev/shm is $((shm_kb / 1024)) MB; the parallel workers need more (docker run --ipc=host, or --shm-size=8g)"
fi
memlock="$(ulimit -l 2>/dev/null || true)"
if [ -n "$memlock" ] && [ "$memlock" != unlimited ]; then
  echo "WARNING: locked-memory limit is ${memlock} KB; the host-resident tables use pinned memory (docker run --ulimit memlock=-1)"
fi

echo "serving $CKPT on ${HOST:-127.0.0.1}:${PORT:-8000} (serve/serve.sh: v2.5.1 launcher, Swift sidecar, xhigh default)"
exec bash "$REPO/serve/serve.sh" "$CKPT" "$@"

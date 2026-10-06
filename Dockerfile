# Flash-Next v2.5.1 serving the Swift 1.5 weights (Merlin recipe) in one image: the unchanged v2.5.1 engine, installed
# by this release's own route (release/install-env.sh: pinned engine checkout, hash-checked release assets, the
# engine's own build script), served by serve/serve.sh through serve/docker-entrypoint.sh. The checkpoint is mounted,
# never baked in.
#
# Build from the repository root (the build context is the repo; .dockerignore keeps it to the files listed below):
#
#   docker build -t swift1.5-qwen38-flash-next-3090s:v2.5.1-swift1.5 .
#
# Run (four cards; README.md "Container" has compose):
#
#   docker run --gpus all --ipc=host --ulimit memlock=-1 --stop-timeout 70 -p 8000:8000 \
#     -v /path/to/Swift1.5-Qwen3.8-Flash-Next-W4A16-Merlin:/model:ro -v swift15-flash-next-cache-v2.5:/cache \
#     swift1.5-qwen38-flash-next-3090s:v2.5.1-swift1.5
#
# Runtime kernel compilation. The build compiles nothing (the engine's compiled ops come from its release asset), but
# the FIRST SERVE does: FlashInfer compiles its kernels with the nvcc at CUDA_HOME and links -lcudart, and Triton
# compiles its launchers with a C compiler against Python.h. So the image carries gcc/g++ and ninja (the python:3.13
# base ships Python.h); the engine's venv carries the CUDA 13.0 nvcc/crt/nvvm/cccl wheels and the lib64 / unversioned
# library links (its build-v2.5.sh adds them: PTX any CUDA >= 13.0 driver accepts). serve/docker-entrypoint.sh checks
# that nvcc against the host driver before starting (kernels from an nvcc newer than the driver are rejected with
# "Unsupported .version"); the engine's launcher checks the toolchain again.
#
# Host needs: NVIDIA driver for CUDA 13.0 or newer, nvidia-container-toolkit registered with Docker
# (nvidia-ctk runtime configure --runtime=docker, then restart docker), four 24 GB cards, 96 GB host RAM
# (docs/reference.md "Build and serve"), /dev/shm >= 1 GB (--ipc=host or --shm-size=8g).

# python 3.13 on Debian 12 (glibc 2.36); pinned by digest (multi-arch index; the image is linux/amd64 only)
FROM python:3.13-slim-bookworm@sha256:2325bb286ec344af3e5898cc224b5844e2707ac6e26b1632516fd3edc84a5e26

LABEL org.opencontainers.image.title="swift1.5-qwen38-flash-next-3090s" \
      org.opencontainers.image.version="2.5.1-swift1.5" \
      org.opencontainers.image.description="Swift1.5-Qwen3.8-Flash-Next-W4A16-Merlin on the Flash-Next v2.5.1 engine, 4x RTX 3090 (checkpoint mounted at /model)" \
      org.opencontainers.image.licenses="Apache-2.0" \
      org.opencontainers.image.base.name="docker.io/library/python:3.13-slim-bookworm"

ENV DEBIAN_FRONTEND=noninteractive PIP_NO_CACHE_DIR=1 PIP_DISABLE_PIP_VERSION_CHECK=1

# git/curl/gzip/tar: install-env.sh clones the engine and fetches its release assets. gcc/g++/libc6-dev/ninja:
# first-serve JIT (above). procps: ps/pgrep for debugging a running container. curl also serves the HEALTHCHECK.
RUN apt-get update \
    && apt-get install -y --no-install-recommends git ca-certificates curl gzip tar procps gcc g++ libc6-dev ninja-build \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /opt/flash-next
# Only what the install and serve routes read (.dockerignore allow-lists the same set). The scripts get mode 0755
# whatever the build context's checkout did, and every caller below also invokes them through bash.
COPY LICENSE ./
COPY release/install-env.sh release/
COPY quant/kv_scales-swift-e4m3.json quant/
COPY serve/ serve/
RUN chmod 0755 release/install-env.sh serve/*.sh

# The published install route, verbatim: the engine at /opt/flash-next/engine (serve.sh's default ENGINE), its
# checkout, assets and build all asserted by install-env.sh. The downloaded assets are dropped afterwards (the build
# products stay); the venv's pip cache too.
RUN bash release/install-env.sh \
    && rm -f engine/*.bundle engine/*.tar.gz && rm -rf /root/.cache

# The first-serve toolkit the engine's venv carries (see the top of this file): assert it is there, with the links.
RUN set -eu; \
    CU=/opt/flash-next/engine/venv-v2.5/lib/python3.13/site-packages/nvidia/cu13; \
    [ -x "$CU/bin/nvcc" ] || { echo "no nvcc wheel at $CU"; exit 1; }; \
    [ -e "$CU/lib64/libcudart.so" ] || { echo "$CU/lib64/libcudart.so missing"; exit 1; }; \
    "$CU/bin/nvcc" --version | tail -1

ENV ENGINE=/opt/flash-next/engine HOST=0.0.0.0 PORT=8000 CACHE_ROOT=/cache \
    CUDA_HOME=/opt/flash-next/engine/venv-v2.5/lib/python3.13/site-packages/nvidia/cu13
ENV PATH="/opt/flash-next/engine/venv-v2.5/lib/python3.13/site-packages/nvidia/cu13/bin:$PATH"
# Every compile cache goes to the /cache volume, so a re-created container reuses the first boot's work: the engine's
# compile cache (CACHE_ROOT), FlashInfer's JIT kernels and Triton's cache. The checkpoint is local, so the Hub is
# never contacted.
ENV FLASHINFER_WORKSPACE_BASE=/cache/flashinfer TRITON_CACHE_DIR=/cache/triton \
    HF_HUB_OFFLINE=1 HF_HUB_DISABLE_TELEMETRY=1
VOLUME /cache
EXPOSE 8000

# A real one-token generation, not /v1/models: that endpoint answers 200 as soon as the HTTP server listens and keeps
# answering after the engine has died. The first boot compiles the graphs (17 min from an empty cache on the v2.2.0
# image; not re-measured in a v2.5.1 image), hence the start period; the timeout is generous because a probe can queue behind a 262K prefill.
HEALTHCHECK --interval=60s --timeout=90s --start-period=30m --retries=3 \
  CMD m="${MODEL_NAME%% *}"; m="${m:-flash-next-v2}"; curl -fs -m 85 -X POST "http://127.0.0.1:${PORT}/v1/chat/completions" \
      -H "Content-Type: application/json" ${VLLM_API_KEY:+-H "Authorization: Bearer $VLLM_API_KEY"} \
      -d "{\"model\":\"$m\",\"messages\":[{\"role\":\"user\",\"content\":\"ok\"}],\"max_tokens\":1,\"chat_template_kwargs\":{\"enable_thinking\":false}}" \
      | grep -q '"choices"' || exit 1

ENTRYPOINT ["bash", "/opt/flash-next/serve/docker-entrypoint.sh"]
CMD ["/model"]

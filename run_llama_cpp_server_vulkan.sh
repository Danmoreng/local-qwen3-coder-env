#!/bin/bash
set -e

# run_llama_cpp_server_vulkan.sh
# ------------------------------
# Runs the Vulkan-build of llama-server.
# (Run ./install_llama_cpp.sh first to build the Vulkan variant)

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
SERVER_EXE="$SCRIPT_DIR/vendor/llama.cpp/build-vulkan/bin/llama-server"
MODEL_DIR="$SCRIPT_DIR/models"
MODEL_URL="https://huggingface.co/unsloth/Qwen3-Coder-Next-GGUF/resolve/main/Qwen3-Coder-Next-UD-Q4_K_XL.gguf"
MODEL_FILE="$MODEL_DIR/$(basename "$MODEL_URL")"

# Check for executable
if [ ! -f "$SERVER_EXE" ]; then
    echo "Error: llama-server (Vulkan) executable not found at:"
    echo "  $SERVER_EXE"
    echo "Please run './install_llama_cpp.sh' and ensure the Vulkan SDK (glslc) is installed."
    exit 1
fi

# Download Model (Reuse existing check)
if [ ! -f "$MODEL_FILE" ]; then
    echo "-> Model not found. Preparing to download..."
    mkdir -p "$MODEL_DIR"
    
    echo "-> Downloading: $MODEL_URL"
    if command -v wget >/dev/null 2>&1; then
        wget -c "$MODEL_URL" -O "$MODEL_FILE"
    elif command -v curl >/dev/null 2>&1; then
        curl -L -C - "$MODEL_URL" -o "$MODEL_FILE"
    else
        echo "Error: Neither 'wget' nor 'curl' found. Cannot download model."
        exit 1
    fi
    echo "[OK] Download complete."
else
    echo "[OK] Model found: $MODEL_FILE"
fi

# Environment Variables
export LLAMA_SET_ROWS=1
# Force Vulkan backend if needed, though the binary should default to it if compiled with only Vulkan.
# export GGML_VULKAN_DEVICE=0 

echo "-> Starting llama-server (Vulkan) on http://localhost:8080 ..."

# Arguments (Same as CUDA, but removed --flash-attn as it is often CUDA/ROCm specific)
"$SERVER_EXE" \
    --model "$MODEL_FILE" \
    --alias "unsloth/Qwen3-Coder-Next" \
    --fit on \
    --fit-target 256 \
    --jinja \
    -c 32768 \
    -b 1024 \
    -ub 256 \
    -ctk q8_0 \
    -ctv q8_0 \
    --no-mmap \
    --n-cpu-moe 36 \
    --temp 1.0 \
    --top-p 0.95 \
    --top-k 40 \
    --min-p 0.01

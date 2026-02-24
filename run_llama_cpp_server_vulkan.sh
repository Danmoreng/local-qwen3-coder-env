#!/bin/bash
set -e

# run_llama_cpp_server_vulkan.sh
# ------------------------------
# Runs the Vulkan-build of llama-server with the selected model.

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
SERVER_EXE="$SCRIPT_DIR/vendor/llama.cpp/build-vulkan/bin/llama-server"
MODEL_DIR="$SCRIPT_DIR/models"
CONFIG_FILE="$SCRIPT_DIR/.model_config"

# Check for executable
if [ ! -f "$SERVER_EXE" ]; then
    echo "Error: llama-server (Vulkan) executable not found at:"
    echo "  $SERVER_EXE"
    echo "Please run './install_llama_cpp.sh' and ensure the Vulkan SDK is installed."
    exit 1
fi

# Ensure model is selected
if [ ! -f "$CONFIG_FILE" ]; then
    "$SCRIPT_DIR/select_model.sh"
fi

source "$CONFIG_FILE"

MODEL_FILE="$MODEL_DIR/$MODEL_FILENAME"

# Download Model
if [ ! -f "$MODEL_FILE" ]; then
    echo "-> Model not found: $MODEL_NAME"
    echo "-> Preparing to download..."
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

echo "-> Starting llama-server (Vulkan) for $MODEL_NAME on http://localhost:8080 ..."

"$SERVER_EXE" \
    --model "$MODEL_FILE" \
    --alias "$MODEL_ALIAS" \
    --fit on \
    --fit-target 256 \
    --jinja \
    --fit-ctx "$MODEL_CTX" \
    -b 1024 \
    -ub 256 \
    -ctk q8_0 \
    -ctv q8_0 \
    --no-mmap \
    --temp 1.0 \
    --top-p 0.95 \
    --top-k 40 \
    --min-p 0.01

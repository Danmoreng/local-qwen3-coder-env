#!/bin/bash
set -e

# run_llama_cpp_server.sh
# -----------------------
# Downloads the selected Qwen model and runs llama-server on Linux.

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
SERVER_EXE="$SCRIPT_DIR/vendor/llama.cpp/build/bin/llama-server"
MODEL_DIR="$SCRIPT_DIR/models"
CONFIG_FILE="$SCRIPT_DIR/.model_config"

# Check for executable
if [ ! -f "$SERVER_EXE" ]; then
    echo "Error: llama-server executable not found at:"
    echo "  $SERVER_EXE"
    echo "Please run './install_llama_cpp.sh' first."
    exit 1
fi

# Ensure model is selected
if [ ! -f "$CONFIG_FILE" ]; then
    "$SCRIPT_DIR/select_model.sh"
fi

source "$CONFIG_FILE"

# Helper to download
download_file() {
    local url=$1
    local dest=$2
    echo "-> Downloading: $url"
    if command -v wget >/dev/null 2>&1; then
        wget -c "$url" -O "$dest"
    elif command -v curl >/dev/null 2>&1; then
        curl -L -C - "$url" -o "$dest"
    else
        echo "Error: Neither 'wget' nor 'curl' found. Cannot download."
        exit 1
    fi
}

# Download Model (Handling Shards)
if [[ "$MODEL_SHARDS" -gt 1 ]]; then
    # Sharded model
    for i in $(seq 1 "$MODEL_SHARDS"); do
        shard_suffix="-$(printf "%05d" $i)-of-$(printf "%05d" "$MODEL_SHARDS").gguf"
        shard_filename="${MODEL_FILENAME}${shard_suffix}"
        shard_url="${MODEL_URL}${shard_suffix}"
        shard_path="$MODEL_DIR/$shard_filename"
        
        if [ ! -f "$shard_path" ]; then
            echo "-> Shard $i/$MODEL_SHARDS not found."
            download_file "$shard_url" "$shard_path"
        fi
    done
    # Pointer for llama-server is the first shard
    MODEL_FILE="$MODEL_DIR/${MODEL_FILENAME}-00001-of-$(printf "%05d" "$MODEL_SHARDS").gguf"
else
    # Single file model
    MODEL_FILE="$MODEL_DIR/$MODEL_FILENAME"
    if [ ! -f "$MODEL_FILE" ]; then
        echo "-> Model not found: $MODEL_NAME"
        download_file "$MODEL_URL" "$MODEL_FILE"
    fi
fi

# Vision Model Handling
MMPROJ_ARG=""
FIT_TARGET="256"
if [[ "$MMPROJ_FILENAME" != "NONE" ]]; then
    MMPROJ_PATH="$MODEL_DIR/$MMPROJ_FILENAME"
    if [ ! -f "$MMPROJ_PATH" ] && [[ "$MMPROJ_URL" != "NONE" && "$MMPROJ_URL" != "LOCAL" ]]; then
        echo "-> Vision projector not found. Downloading..."
        download_file "$MMPROJ_URL" "$MMPROJ_PATH"
    fi
    
    if [ -f "$MMPROJ_PATH" ]; then
        MMPROJ_ARG="--mmproj $MMPROJ_PATH --mmproj-offload"
        FIT_TARGET="1536"
        echo "-> Vision model detected. Using GPU offload and FIT_TARGET=$FIT_TARGET"
    fi
fi

# Environment Variables
export LLAMA_SET_ROWS=1

# Sampling Parameters based on model series
TEMP="1.0"
TOP_P="0.95"
TOP_K="40"
MIN_P="0.01"

if [[ "$MODEL_NAME" == *"Qwen3.5"* ]]; then
    # Optimized for "Thinking Mode: Precise Coding"
    TEMP="0.6"
    TOP_K="20"
    MIN_P="0.0"
    echo "-> Qwen 3.5 detected. Applying 'Thinking: Precise Coding' sampling parameters."
else
    echo "-> Qwen 3 Coder detected. Applying standard coding sampling parameters."
fi

echo "-> Starting llama-server for $MODEL_NAME on http://localhost:8080 ..."

"$SERVER_EXE" \
    --model "$MODEL_FILE" \
    $MMPROJ_ARG \
    --alias "$MODEL_ALIAS" \
    --fit on \
    --fit-target "$FIT_TARGET" \
    --jinja \
    --flash-attn on \
    --fit-ctx "$MODEL_CTX" \
    -b 1024 \
    -ub 256 \
    -ctk q8_0 \
    -ctv q8_0 \
    --temp "$TEMP" \
    --top-p "$TOP_P" \
    --top-k "$TOP_K" \
    --min-p "$MIN_P"

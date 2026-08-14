#!/bin/bash
set -e

# run_qwen3_6_optimized.sh
# -----------------------
# Specialized script for Qwen 3.6 27B on 16GB VRAM.
# Optimized for text-only, maximum context, and high performance.

TEXT_ONLY=1 # Default to text-only for VRAM efficiency
LOCAL_MODEL=0
for arg in "$@"; do
    case "$arg" in
        --vision) TEXT_ONLY=0 ;;
        --local-model) LOCAL_MODEL=1 ;;
        *) echo "Usage: ./run_qwen3_6_optimized.sh [--vision] [--local-model]"; exit 1 ;;
    esac
done

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
SERVER_EXE="$SCRIPT_DIR/vendor/llama.cpp/build/bin/llama-server"
MODEL_DIR="$SCRIPT_DIR/models"
CONFIG_FILE="$SCRIPT_DIR/model_config.json"

# Check for executable
if [ ! -f "$SERVER_EXE" ]; then
    echo "Error: llama-server executable not found. Please run './install_llama_cpp.sh' first."
    exit 1
fi

# Ensure model is selected
if [ ! -f "$CONFIG_FILE" ]; then
    echo "No model selected. Launching selection menu..."
    "$SCRIPT_DIR/select_model.sh"
fi

# Simple JSON parser helper
get_json_val() {
    local key=$1
    grep -Po '"'$key'":\s*(?:"([^"]*)"|(\d+))' "$CONFIG_FILE" | sed -r 's/"'$key'":\s*//;s/"//g'
}

MODEL_NAME=$(get_json_val "MODEL_NAME")
MODEL_URL=$(get_json_val "MODEL_URL")
MODEL_ALIAS=$(get_json_val "MODEL_ALIAS")
MODEL_CTX=$(get_json_val "MODEL_CTX")
MODEL_FILENAME=$(get_json_val "MODEL_FILENAME")
MODEL_HF_REPO=$(get_json_val "MODEL_HF_REPO" || true)
MODEL_HF_FILE=$(get_json_val "MODEL_HF_FILE" || true)
MMPROJ_URL=$(get_json_val "MMPROJ_URL")
MMPROJ_FILENAME=$(get_json_val "MMPROJ_FILENAME")
MODEL_SHARDS=$(get_json_val "MODEL_SHARDS")

# Validation: Ensure it's a Qwen 3.6 model
if [[ ! "$MODEL_NAME" =~ Qwen3\.6 ]]; then
    echo "Warning: This script is tuned for Qwen 3.6. Selected model: $MODEL_NAME"
    echo "Continuing anyway..."
fi

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
        echo "Error: Neither 'wget' nor 'curl' found."
        exit 1
    fi
}

# Use llama.cpp's shared Hugging Face cache unless this is a local/custom model.
if [[ -z "$MODEL_HF_REPO" || "$MODEL_HF_REPO" == "NONE" ]]; then
    LOCAL_MODEL=1
fi

MODEL_ARGS=()
if [[ "$LOCAL_MODEL" -eq 1 ]]; then
    MODEL_FILE="$MODEL_DIR/$MODEL_FILENAME"
    if [ ! -f "$MODEL_FILE" ]; then
        echo "-> Local model not found: $MODEL_NAME"
        download_file "$MODEL_URL" "$MODEL_FILE"
    fi
    MODEL_ARGS=(--model "$MODEL_FILE")
    echo "-> Model source: local fallback ($MODEL_FILE)"
else
    MODEL_ARGS=(--hf-repo "$MODEL_HF_REPO" --hf-file "$MODEL_HF_FILE")
    echo "-> Model source: Hugging Face cache ($MODEL_HF_REPO / $MODEL_HF_FILE)"
fi

# Vision Model Handling
MMPROJ_ARGS=()
if [[ "$TEXT_ONLY" -eq 1 && "$LOCAL_MODEL" -eq 0 ]]; then
    MMPROJ_ARGS=(--no-mmproj)
elif [[ "$TEXT_ONLY" -eq 0 && "$LOCAL_MODEL" -eq 0 && "$MMPROJ_FILENAME" != "NONE" ]]; then
    MMPROJ_ARGS=(--mmproj-auto --mmproj-offload)
    echo "-> Vision mode enabled. The projector will use the Hugging Face cache."
elif [[ "$TEXT_ONLY" -eq 0 && "$MMPROJ_FILENAME" != "NONE" ]]; then
    MMPROJ_PATH="$MODEL_DIR/$MMPROJ_FILENAME"
    if [ ! -f "$MMPROJ_PATH" ] && [[ "$MMPROJ_URL" != "NONE" ]]; then
        download_file "$MMPROJ_URL" "$MMPROJ_PATH"
    fi
    if [ -f "$MMPROJ_PATH" ]; then
        MMPROJ_ARGS=(--mmproj "$MMPROJ_PATH" --mmproj-offload)
        echo "-> Vision mode enabled. (Caution: Higher VRAM usage)"
    fi
fi

# 16GB VRAM TUNING
# ----------------
# Model Weights (IQ3_M): ~11.5GB
# KV Cache (q4_0): ~2.5GB for 32k context
# Overhead/System: ~1.5GB
# Total: ~15.5GB / 16GB

export LLAMA_SET_ROWS=1
export LLAMA_CHAT_TEMPLATE_KWARGS='{"preserve_thinking":true}'

# Sampling for Qwen 3.6
TEMP="0.6"
TOP_K="20"
MIN_P="0.01"

echo "-> Starting OPTIMIZED llama-server for $MODEL_NAME"
echo "-> VRAM Target: 16GB | Mode: $([[ $TEXT_ONLY -eq 1 ]] && echo "Text-Only" || echo "Vision")"

"$SERVER_EXE" \
    "${MODEL_ARGS[@]}" \
    "${MMPROJ_ARGS[@]}" \
    --alias "$MODEL_ALIAS" \
    --fit on \
    --fit-target 256 \
    --jinja \
    --flash-attn on \
    -ngl 99 \
    -c "$MODEL_CTX" \
    -b 1024 \
    -ub 256 \
    --cache-type-k q8_0 \
    --cache-type-v q8_0 \
    --temp "$TEMP" \
    --top-k "$TOP_K" \
    --min-p "$MIN_P" \
    --reasoning-preserve \
    --host 0.0.0.0 \
    --port 8080

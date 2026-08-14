#!/bin/bash
set -e

# run_llama_cpp_server_vulkan.sh
# ------------------------------
# Runs the Vulkan-build of llama-server with the selected model.

TEXT_ONLY=0
LOCAL_MODEL=0
for arg in "$@"; do
    case "$arg" in
        --text-only) TEXT_ONLY=1 ;;
        --local-model) LOCAL_MODEL=1 ;;
        *) echo "Usage: ./run_llama_cpp_server_vulkan.sh [--text-only] [--local-model]"; exit 1 ;;
    esac
done

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
SERVER_EXE="$SCRIPT_DIR/vendor/llama.cpp/build-vulkan/bin/llama-server"
MODEL_DIR="$SCRIPT_DIR/models"
CONFIG_FILE="$SCRIPT_DIR/model_config.json"

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

if [[ -z "$MODEL_HF_REPO" || "$MODEL_HF_REPO" == "NONE" ]]; then
    LOCAL_MODEL=1
fi

MODEL_ARGS=()
if [[ "$LOCAL_MODEL" -eq 1 && "$MODEL_SHARDS" -gt 1 ]]; then
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
    MODEL_ARGS=(--model "$MODEL_FILE")
elif [[ "$LOCAL_MODEL" -eq 1 ]]; then
    # Single file model
    MODEL_FILE="$MODEL_DIR/$MODEL_FILENAME"
    if [ ! -f "$MODEL_FILE" ]; then
        echo "-> Model not found: $MODEL_NAME"
        download_file "$MODEL_URL" "$MODEL_FILE"
    fi
    MODEL_ARGS=(--model "$MODEL_FILE")
else
    MODEL_ARGS=(--hf-repo "$MODEL_HF_REPO" --hf-file "$MODEL_HF_FILE")
fi

if [[ "$LOCAL_MODEL" -eq 1 ]]; then
    echo "-> Model source: local fallback ($MODEL_FILE)"
else
    echo "-> Model source: Hugging Face cache ($MODEL_HF_REPO / $MODEL_HF_FILE)"
fi

# Vision Model Handling
MMPROJ_ARGS=()
FIT_TARGET="256"
if [[ "$TEXT_ONLY" -eq 1 ]]; then
    echo "-> Text-only mode enabled. Skipping vision projector and using FIT_TARGET=$FIT_TARGET"
    if [[ "$LOCAL_MODEL" -eq 0 ]]; then MMPROJ_ARGS=(--no-mmproj); fi
elif [[ "$LOCAL_MODEL" -eq 0 && "$MMPROJ_FILENAME" != "NONE" ]]; then
    MMPROJ_ARGS=(--mmproj-auto --mmproj-offload)
    FIT_TARGET="1536"
    echo "-> Vision mode enabled. The projector will use the Hugging Face cache."
elif [[ "$MMPROJ_FILENAME" != "NONE" ]]; then
    MMPROJ_PATH="$MODEL_DIR/$MMPROJ_FILENAME"
    if [ ! -f "$MMPROJ_PATH" ] && [[ "$MMPROJ_URL" != "NONE" && "$MMPROJ_URL" != "LOCAL" ]]; then
        echo "-> Vision projector not found. Downloading..."
        download_file "$MMPROJ_URL" "$MMPROJ_PATH"
    fi
    
    if [ -f "$MMPROJ_PATH" ]; then
        MMPROJ_ARGS=(--mmproj "$MMPROJ_PATH" --mmproj-offload)
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

if [[ "$MODEL_NAME" =~ Qwen3\.8 ]]; then
    TEMP="1.0"
    TOP_K="20"
    MIN_P="0.0"
    echo "-> Qwen 3.8 detected. Applying official thinking-mode sampling parameters."
elif [[ "$MODEL_NAME" =~ Qwen3\.(5|6) ]]; then
    # Optimized for Qwen 3.5 / 3.6 reasoning models
    TEMP="0.6"
    TOP_K="20"
    MIN_P="0.0"
    echo "-> Qwen 3.5 / 3.6 detected. Applying 'Thinking: Precise Coding' sampling parameters."
else
    echo "-> Qwen 3 Coder detected. Applying standard coding sampling parameters."
fi

REASONING_ARGS=()
if [[ "$MODEL_NAME" =~ Qwen3\.8 ]]; then
    export LLAMA_CHAT_TEMPLATE_KWARGS='{"enable_thinking":true,"preserve_thinking":true,"reasoning_effort":"xhigh"}'
    REASONING_ARGS=(--reasoning-preserve)
    echo "-> Qwen 3.8 detected. Enabling preserved thinking with xhigh reasoning effort."
elif [[ "$MODEL_NAME" =~ Qwen3\.6 ]]; then
    export LLAMA_CHAT_TEMPLATE_KWARGS='{"preserve_thinking":true}'
    REASONING_ARGS=(--reasoning-preserve)
    echo "-> Qwen 3.6 detected. Enabling preserve_thinking in the chat template."
else
    unset LLAMA_CHAT_TEMPLATE_KWARGS
fi

echo "-> Starting llama-server (Vulkan) for $MODEL_NAME on http://localhost:8080 ..."

"$SERVER_EXE" \
    "${MODEL_ARGS[@]}" \
    "${MMPROJ_ARGS[@]}" \
    "${REASONING_ARGS[@]}" \
    --alias "$MODEL_ALIAS" \
    --fit on \
    --fit-target "$FIT_TARGET" \
    --jinja \
    -np 1 \
    --fit-ctx "$MODEL_CTX" \
    -b 1024 \
    -ub 256 \
    -ctk q8_0 \
    -ctv q8_0 \
    --no-mmap \
    --temp "$TEMP" \
    --top-p "$TOP_P" \
    --top-k "$TOP_K" \
    --min-p "$MIN_P" \
    --presence-penalty 0.0 \
    --repeat-penalty 1.0

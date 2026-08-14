#!/bin/bash
set -e

# Qwen3.8-27B launcher tuned for 16GB NVIDIA GPUs.

VISION=0
LOCAL_MODEL=0
for arg in "$@"; do
    case "$arg" in
        --vision) VISION=1 ;;
        --local-model) LOCAL_MODEL=1 ;;
        *) echo "Usage: ./run_qwen3_8_optimized.sh [--vision] [--local-model]"; exit 1 ;;
    esac
done

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
SERVER_EXE="$SCRIPT_DIR/vendor/llama.cpp/build/bin/llama-server"
MODEL_DIR="$SCRIPT_DIR/models"

MODEL_NAME="Qwen3.8-27B (Dense) - UD-IQ3_XXS"
MODEL_ALIAS="unsloth/Qwen3.8-27B-UD-IQ3_XXS"
MODEL_HF_REPO="unsloth/Qwen3.8-27B-GGUF"
MODEL_HF_FILE="Qwen3.8-27B-UD-IQ3_XXS.gguf"
MODEL_URL="https://huggingface.co/$MODEL_HF_REPO/resolve/main/$MODEL_HF_FILE"
MMPROJ_FILENAME="mmproj-Qwen3.8-27B.gguf"
MMPROJ_URL="https://huggingface.co/$MODEL_HF_REPO/resolve/main/mmproj-BF16.gguf"

if [[ ! -x "$SERVER_EXE" ]]; then
    echo "Error: llama-server not found. Run './install_llama_cpp.sh' first."
    exit 1
fi

download_file() {
    local url=$1
    local dest=$2
    mkdir -p "$(dirname "$dest")"
    if command -v wget >/dev/null 2>&1; then
        wget -c "$url" -O "$dest"
    elif command -v curl >/dev/null 2>&1; then
        curl -L -C - "$url" -o "$dest"
    else
        echo "Error: Neither wget nor curl is installed."
        exit 1
    fi
}

MODEL_ARGS=()
MMPROJ_ARGS=()
FIT_TARGET=256

if [[ "$LOCAL_MODEL" -eq 1 ]]; then
    MODEL_FILE="$MODEL_DIR/$MODEL_HF_FILE"
    [[ -f "$MODEL_FILE" ]] || download_file "$MODEL_URL" "$MODEL_FILE"
    MODEL_ARGS=(--model "$MODEL_FILE")
    echo "-> Model source: local fallback ($MODEL_FILE)"
    if [[ "$VISION" -eq 1 ]]; then
        MMPROJ_FILE="$MODEL_DIR/$MMPROJ_FILENAME"
        [[ -f "$MMPROJ_FILE" ]] || download_file "$MMPROJ_URL" "$MMPROJ_FILE"
        MMPROJ_ARGS=(--mmproj "$MMPROJ_FILE" --mmproj-offload)
        FIT_TARGET=1536
    fi
else
    MODEL_ARGS=(--hf-repo "$MODEL_HF_REPO" --hf-file "$MODEL_HF_FILE")
    echo "-> Model source: central Hugging Face cache ($MODEL_HF_REPO / $MODEL_HF_FILE)"
    if [[ "$VISION" -eq 1 ]]; then
        MMPROJ_ARGS=(--mmproj-auto --mmproj-offload)
        FIT_TARGET=1536
    else
        MMPROJ_ARGS=(--no-mmproj)
    fi
fi

export LLAMA_SET_ROWS=1
export LLAMA_CHAT_TEMPLATE_KWARGS='{"enable_thinking":true,"preserve_thinking":true,"reasoning_effort":"xhigh"}'

echo "-> Starting optimized llama-server for $MODEL_NAME on http://localhost:8080"
echo "-> 64K context, Q8 KV cache, MTP speculative decoding, mode: $([[ "$VISION" -eq 1 ]] && echo vision || echo text-only)"

"$SERVER_EXE" \
    "${MODEL_ARGS[@]}" \
    "${MMPROJ_ARGS[@]}" \
    --alias "$MODEL_ALIAS" \
    --fit on \
    --fit-target "$FIT_TARGET" \
    --jinja \
    --flash-attn on \
    -np 1 \
    --fit-ctx 65536 \
    -b 1024 \
    -ub 512 \
    -ctk q8_0 \
    -ctv q8_0 \
    --temp 1.0 \
    --top-p 0.95 \
    --top-k 20 \
    --min-p 0.0 \
    --presence-penalty 0.0 \
    --repeat-penalty 1.0 \
    --reasoning-preserve \
    --spec-type draft-mtp \
    --host 0.0.0.0 \
    --port 8080

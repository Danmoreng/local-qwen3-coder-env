#!/bin/bash
set -e

# Qwen3.8-27B launcher tuned for 16GB NVIDIA GPUs.

VISION=0
LOCAL_MODEL=0
SAFE_CONTEXT=0
for arg in "$@"; do
    case "$arg" in
        --vision) VISION=1 ;;
        --local-model) LOCAL_MODEL=1 ;;
        --safe-context) SAFE_CONTEXT=1 ;;
        *) echo "Usage: ./run_qwen3_8_optimized.sh [--vision] [--local-model] [--safe-context]"; exit 1 ;;
    esac
done

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
SERVER_EXE="$SCRIPT_DIR/vendor/llama.cpp/build/bin/llama-server"
MODEL_DIR="$SCRIPT_DIR/models"

MODEL_NAME="Qwen3.8-27B (Dense) - UD-IQ3_XXS"
MODEL_ALIAS="unsloth/Qwen3.8-27B-UD-IQ3_XXS"
MODEL_HF_REPO="unsloth/Qwen3.8-27B-GGUF"
MODEL_HF_FILE="Qwen3.8-27B-UD-IQ3_XXS.gguf"
MODEL_HF_REVISION="27af057ecb382ddfea5d12837360a8980560e3ed"
MODEL_LOCAL_FILE="Qwen3.8-27B-UD-IQ3_XXS-Dynamic3-27af057.gguf"
MODEL_URL="https://huggingface.co/$MODEL_HF_REPO/resolve/$MODEL_HF_REVISION/$MODEL_HF_FILE"
MMPROJ_FILENAME="mmproj-Qwen3.8-27B.gguf"
MMPROJ_URL="https://huggingface.co/$MODEL_HF_REPO/resolve/$MODEL_HF_REVISION/mmproj-BF16.gguf"

CONTEXT_SIZE=98304
if [[ "$SAFE_CONTEXT" -eq 1 || "$VISION" -eq 1 ]]; then
    CONTEXT_SIZE=81920
fi
CONTEXT_K=$((CONTEXT_SIZE / 1024))

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

resolve_hf_file() {
    local repo=$1
    local file=$2
    local revision=$3
    local output path
    echo "-> Resolving pinned Hugging Face revision $revision: $repo / $file" >&2
    output=$(hf download "$repo" "$file" --revision "$revision" --quiet) || return 1
    path=$(printf '%s\n' "$output" | tail -n 1)
    path=${path#"${path%%[![:space:]]*}"}
    path=${path%"${path##*[![:space:]]}"}
    path=${path#path:}
    path=${path#path=}
    path=${path#"${path%%[![:space:]]*}"}
    path=${path%"${path##*[![:space:]]}"}
    [[ -f "$path" ]] || { echo "Error: hf did not return a valid file path: $path" >&2; return 1; }
    printf '%s\n' "$path"
}

MODEL_ARGS=()
MMPROJ_ARGS=()
FIT_ARGS=(--fit off)
CTX_ARGS=(-c "$CONTEXT_SIZE")

if [[ "$LOCAL_MODEL" -eq 1 ]]; then
    MODEL_FILE="$MODEL_DIR/$MODEL_LOCAL_FILE"
    [[ -f "$MODEL_FILE" ]] || download_file "$MODEL_URL" "$MODEL_FILE"
    MODEL_ARGS=(--model "$MODEL_FILE")
    echo "-> Model source: local fallback ($MODEL_FILE)"
    if [[ "$VISION" -eq 1 ]]; then
        MMPROJ_FILE="$MODEL_DIR/$MMPROJ_FILENAME"
        [[ -f "$MMPROJ_FILE" ]] || download_file "$MMPROJ_URL" "$MMPROJ_FILE"
        MMPROJ_ARGS=(--mmproj "$MMPROJ_FILE" --mmproj-offload)
        FIT_ARGS=(--fit on --fit-target 1536 --fit-ctx "$CONTEXT_SIZE")
        CTX_ARGS=()
    else
        MMPROJ_ARGS=(--no-mmproj)
    fi
else
    if command -v hf >/dev/null 2>&1; then
        MODEL_FILE=$(resolve_hf_file "$MODEL_HF_REPO" "$MODEL_HF_FILE" "$MODEL_HF_REVISION")
        MODEL_ARGS=(--model "$MODEL_FILE")
        echo "-> Model source: Hugging Face Xet cache ($MODEL_FILE)"
    else
        MODEL_ARGS=(--hf-repo "$MODEL_HF_REPO" --hf-file "$MODEL_HF_FILE")
        echo "-> 'hf' CLI not found; using llama.cpp's built-in downloader."
    fi
    if [[ "$VISION" -eq 1 ]]; then
        if command -v hf >/dev/null 2>&1; then
            MMPROJ_FILE=$(resolve_hf_file "$MODEL_HF_REPO" "mmproj-BF16.gguf" "$MODEL_HF_REVISION")
            MMPROJ_ARGS=(--mmproj "$MMPROJ_FILE" --mmproj-offload)
        else
            MMPROJ_ARGS=(--mmproj-auto --mmproj-offload)
        fi
        FIT_ARGS=(--fit on --fit-target 1536 --fit-ctx "$CONTEXT_SIZE")
        CTX_ARGS=()
    else
        MMPROJ_ARGS=(--no-mmproj)
    fi
fi

echo "-> Starting optimized llama-server for $MODEL_NAME on http://localhost:8080"
if [[ "$VISION" -eq 1 ]]; then
    echo "-> Vision mode: dynamic GPU fitting, ${CONTEXT_K}K context floor, Q8 KV cache, MTP speculative decoding"
else
    echo "-> Text mode: fixed ${CONTEXT_K}K context, full GPU placement, Q8 KV cache, MTP speculative decoding"
fi

"$SERVER_EXE" \
    "${MODEL_ARGS[@]}" \
    "${MMPROJ_ARGS[@]}" \
    --alias "$MODEL_ALIAS" \
    "${FIT_ARGS[@]}" \
    "${CTX_ARGS[@]}" \
    --flash-attn on \
    -np 1 \
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
    --reasoning-effort medium \
    --reasoning-budget 8192 \
    --reasoning-budget-message "... I have been thinking for too long -- let me gather more information about the task and take the next concrete action." \
    --reasoning-preserve \
    --spec-default \
    --spec-type draft-mtp \
    --host 0.0.0.0 \
    --port 8080

#!/bin/bash

MODEL_DIR="models"
mkdir -p "$MODEL_DIR"

# 1. Define Known/Remote Models
# Format: "Display Name|URL|Alias|Context|Filename"
KNOWN_MODELS=(
    "Qwen3-Coder-Next (80B MoE) - Q4_K_XL|https://huggingface.co/unsloth/Qwen3-Coder-Next-GGUF/resolve/main/Qwen3-Coder-Next-UD-Q4_K_XL.gguf|unsloth/Qwen3-Coder-Next|32768|Qwen3-Coder-Next-UD-Q4_K_XL.gguf"
    "Qwen3-Coder-Next (80B MoE) - MXFP4|https://huggingface.co/unsloth/Qwen3-Coder-Next-GGUF/resolve/main/Qwen3-Coder-Next-UD-Q4_K_XL.gguf|unsloth/Qwen3-Coder-Next-MXFP4|65536|Qwen3-Coder-Next-MXFP4_MOE.gguf"
    "Qwen3.5-27B (Dense) - Q4_K_M|https://huggingface.co/unsloth/Qwen3.5-27B-GGUF/resolve/main/Qwen3.5-27B-Q4_K_M.gguf|unsloth/Qwen3.5-27B|32768|Qwen3.5-27B-Q4_K_M.gguf"
    "Qwen3.5-35B-A3B (MoE) - Q4_K_M|https://huggingface.co/unsloth/Qwen3.5-35B-A3B-GGUF/resolve/main/Qwen3.5-35B-A3B-Q4_K_M.gguf|unsloth/Qwen3.5-35B-A3B|32768|Qwen3.5-35B-A3B-Q4_K_M.gguf"
    "Qwen3.5-122B-A10B (MoE) - Q4_K_M|https://huggingface.co/unsloth/Qwen3.5-122B-A10B-GGUF/resolve/main/Qwen3.5-122B-A10B-Q4_K_M.gguf|unsloth/Qwen3.5-122B-A10B|32768|Qwen3.5-122B-A10B-Q4_K_M.gguf"
)

# 2. Collect All Final Options
ALL_OPTIONS=("${KNOWN_MODELS[@]}")

# 3. Scan local models directory for extra files
for file in "$MODEL_DIR"/*.gguf; do
    [ -e "$file" ] || continue
    filename=$(basename "$file")
    
    # Check if this file is already covered by a known model
    is_known=false
    for km in "${KNOWN_MODELS[@]}"; do
        if [[ "$km" == *"$filename"* ]]; then
            is_known=true
            break
        fi
    done
    
    # If not known, add it as a local option
    if [ "$is_known" = false ]; then
        # Format: Display|URL(none)|Alias|Context(default)|Filename
        ALL_OPTIONS+=("Local: $filename|NONE|local/$filename|32768|$filename")
    fi
done

# 4. Display Menu
echo "------------------------------------------"
echo " Available Models (Local files detected *)"
echo "------------------------------------------"
for i in "${!ALL_OPTIONS[@]}"; do
    IFS='|' read -r name url alias ctx filename <<< "${ALL_OPTIONS[$i]}"
    status=""
    if [ -f "$MODEL_DIR/$filename" ]; then status="[Found]"; fi
    echo "[$((i+1))] $name $status"
done
echo "------------------------------------------"

read -p "Selection [1-${#ALL_OPTIONS[@]}]: " choice

if [[ $choice -ge 1 && $choice -le ${#ALL_OPTIONS[@]} ]]; then
    SELECTED="${ALL_OPTIONS[$((choice-1))]}"
    IFS='|' read -r name url alias ctx filename <<< "$SELECTED"
    
    # If it's a new local model, maybe ask for context?
    if [[ "$url" == "NONE" ]]; then
        read -p "Enter context size for $filename [default $ctx]: " user_ctx
        [ ! -z "$user_ctx" ] && ctx="$user_ctx"
    fi

    cat <<EOF > .model_config
MODEL_NAME="$name"
MODEL_URL="$url"
MODEL_ALIAS="$alias"
MODEL_CTX="$ctx"
MODEL_FILENAME="$filename"
EOF
    echo "Selected: $name"
    echo "Config saved to .model_config"
else
    echo "Invalid selection."
    exit 1
fi

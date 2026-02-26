#!/bin/bash

MODEL_DIR="models"
mkdir -p "$MODEL_DIR"

# 1. Define Known/Remote Models
# Format: "Display Name|URL|Alias|Context|Filename|MMPROJ_URL|MMPROJ_FILENAME|SHARDS"
# For shards: Filename should be the base name without the shard suffix (e.g. -00001-of-00003.gguf)
KNOWN_MODELS=(
    "Qwen3-Coder-Next (80B MoE) - Q4_K_M|https://huggingface.co/unsloth/Qwen3-Coder-Next-GGUF/resolve/main/Qwen3-Coder-Next-Q4_K_M.gguf|unsloth/Qwen3-Coder-Next|32768|Qwen3-Coder-Next-Q4_K_M.gguf|NONE|NONE|1"
    "Qwen3-Coder-Next (80B MoE) - MXFP4|https://huggingface.co/unsloth/Qwen3-Coder-Next-GGUF/resolve/main/Qwen3-Coder-Next-MXFP4_MOE.gguf|unsloth/Qwen3-Coder-Next-MXFP4|65536|Qwen3-Coder-Next-MXFP4_MOE.gguf|NONE|NONE|1"
    "Qwen3.5-27B (Dense) - Q4_K_M|https://huggingface.co/unsloth/Qwen3.5-27B-GGUF/resolve/main/Qwen3.5-27B-Q4_K_M.gguf|unsloth/Qwen3.5-27B|32768|Qwen3.5-27B-Q4_K_M.gguf|https://huggingface.co/unsloth/Qwen3.5-27B-GGUF/resolve/main/mmproj-BF16.gguf|mmproj-Qwen3.5-27B.gguf|1"
    "Qwen3.5-35B-A3B (MoE) - Q4_K_M|https://huggingface.co/unsloth/Qwen3.5-35B-A3B-GGUF/resolve/main/Qwen3.5-35B-A3B-Q4_K_M.gguf|unsloth/Qwen3.5-35B-A3B|32768|Qwen3.5-35B-A3B-Q4_K_M.gguf|https://huggingface.co/unsloth/Qwen3.5-35B-A3B-GGUF/resolve/main/mmproj-BF16.gguf|mmproj-Qwen3.5-35B.gguf|1"
    "Qwen3.5-122B-A10B (MoE) - Q4_K_M|https://huggingface.co/unsloth/Qwen3.5-122B-A10B-GGUF/resolve/main/Q4_K_M/Qwen3.5-122B-A10B-Q4_K_M|unsloth/Qwen3.5-122B-A10B|32768|Qwen3.5-122B-A10B-Q4_K_M|https://huggingface.co/unsloth/Qwen3.5-122B-A10B-GGUF/resolve/main/mmproj-BF16.gguf|mmproj-Qwen3.5-122B.gguf|3"
)

# 2. Collect All Final Options
ALL_OPTIONS=("${KNOWN_MODELS[@]}")

# 3. Scan local models directory for extra files
for file in "$MODEL_DIR"/*.gguf; do
    [ -e "$file" ] || continue
    filename=$(basename "$file")
    [[ "$filename" == mmproj* ]] && continue
    # Skip non-primary shards to avoid clutter
    [[ "$filename" =~ -0000[2-9] ]] && continue

    is_known=false
    for km in "${KNOWN_MODELS[@]}"; do
        if [[ "$km" == *"$filename"* ]]; then
            is_known=true
            break
        fi
    done
    
    if [ "$is_known" = false ]; then
        ALL_OPTIONS+=("Local: $filename|NONE|local/$filename|32768|$filename|NONE|NONE|1")
    fi
done

# 4. Display Menu
echo "------------------------------------------"
echo " Available Models (Local files detected *)"
echo "------------------------------------------"
for i in "${!ALL_OPTIONS[@]}"; do
    IFS='|' read -r name url alias ctx filename mmproj_url mmproj_filename shards <<< "${ALL_OPTIONS[$i]}"
    status=""
    
    # Check if first shard exists
    check_file="$filename"
    [[ "$shards" -gt 1 ]] && check_file="${filename}-00001-of-$(printf "%05d" $shards).gguf"
    
    if [ -f "$MODEL_DIR/$check_file" ]; then status="[Found]"; fi
    echo "[$((i+1))] $name $status"
done
echo "------------------------------------------"

read -p "Selection [1-${#ALL_OPTIONS[@]}]: " choice

if [[ $choice -ge 1 && $choice -le ${#ALL_OPTIONS[@]} ]]; then
    SELECTED="${ALL_OPTIONS[$((choice-1))]}"
    IFS='|' read -r name url alias ctx filename mmproj_url mmproj_filename shards <<< "$SELECTED"
    
    if [[ "$url" == "NONE" ]]; then
        read -p "Enter context size for $filename [default $ctx]: " user_ctx
        [ ! -z "$user_ctx" ] && ctx="$user_ctx"
        
        read -p "Does this model need a vision projector (mmproj)? [y/N]: " has_mmproj
        if [[ "$has_mmproj" =~ ^[Yy]$ ]]; then
             read -p "Enter mmproj URL (or filename in models/): " user_mmproj
             if [[ "$user_mmproj" == http* ]]; then
                 mmproj_url="$user_mmproj"
                 mmproj_filename="mmproj-custom-$(date +%s).gguf"
             else
                 mmproj_url="NONE"
                 mmproj_filename="$user_mmproj"
             fi
        fi
    fi

    cat <<EOF > .model_config
MODEL_NAME="$name"
MODEL_URL="$url"
MODEL_ALIAS="$alias"
MODEL_CTX="$ctx"
MODEL_FILENAME="$filename"
MMPROJ_URL="$mmproj_url"
MMPROJ_FILENAME="$mmproj_filename"
MODEL_SHARDS="$shards"
EOF
    echo "Selected: $name"
    echo "Config saved to .model_config"
else
    echo "Invalid selection."
    exit 1
fi

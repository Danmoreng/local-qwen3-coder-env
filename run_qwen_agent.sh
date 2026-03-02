#!/bin/bash
# run_qwen_agent.sh
# -----------------
# Launches the qwen-code CLI configured to talk to the local llama-server.

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
CONFIG_FILE="$SCRIPT_DIR/model_config.json"

if [ ! -f "$CONFIG_FILE" ]; then
    "$SCRIPT_DIR/select_model.sh"
fi

# Simple JSON parser helper
get_json_val() {
    local key=$1
    grep -Po '"'$key'":\s*(?:"([^"]*)"|(\d+))' "$CONFIG_FILE" | sed -r 's/"'$key'":\s*//;s/"//g'
}

MODEL_ALIAS=$(get_json_val "MODEL_ALIAS")

export OPENAI_BASE_URL="http://localhost:8080/v1"
export OPENAI_API_KEY="sk-no-key-required"
export OPENAI_MODEL="$MODEL_ALIAS"

echo "-> Connecting to $OPENAI_MODEL at $OPENAI_BASE_URL..."

if command -v qwen >/dev/null 2>&1; then
    qwen
elif command -v qwen-code >/dev/null 2>&1; then
    qwen-code
else
    echo "Error: Could not find 'qwen' or 'qwen-code' command."
    echo "Please install it via: npm install -g @qwen-code/qwen-code@latest"
    exit 1
fi

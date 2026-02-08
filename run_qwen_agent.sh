#!/bin/bash

# run_qwen_agent.sh
# ------------------
# Launches the qwen-code CLI configured to talk to the local llama-server.
# Ensure run_llama_cpp_server.sh is running!

export OPENAI_API_KEY="sk-no-key-required"
export OPENAI_BASE_URL="http://localhost:8080/v1"
export OPENAI_MODEL="unsloth/Qwen3-Coder-Next"

echo "-> Connecting to Qwen3-Coder-Next at $OPENAI_BASE_URL..."
echo "-> Ensure 'run_llama_cpp_server.sh' is running in another terminal."
echo ""

if command -v qwen >/dev/null 2>&1; then
    qwen
elif command -v qwen-code >/dev/null 2>&1; then
    qwen-code
else
    echo "Error: Could not find 'qwen' or 'qwen-code' command."
    echo "Please install it via: npm install -g @qwen-code/qwen-code@latest"
    exit 1
fi

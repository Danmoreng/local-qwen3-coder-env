<#
    run_qwen_agent.ps1
    ------------------
    Launches the qwen-code CLI configured to talk to the local llama-server.
    Ensure run_llama_cpp_server.ps1 is running!
#>

$env:OPENAI_API_KEY = "sk-no-key-required"
$env:OPENAI_BASE_URL = "http://localhost:8080/v1"
$env:OPENAI_MODEL = "unsloth/Qwen3-Coder-Next"

Write-Host "→ Connecting to Qwen3-Coder-Next at $env:OPENAI_BASE_URL..."
Write-Host "→ Ensure 'run_llama_cpp_server.ps1' is running in another window."
Write-Host ""

if (Get-Command qwen -ErrorAction SilentlyContinue) {
    qwen
} elseif (Get-Command qwen-code -ErrorAction SilentlyContinue) {
    qwen-code
} else {
    Write-Error "Could not find 'qwen' or 'qwen-code' command. Please install it via install_llama_cpp.ps1 or 'npm install -g @qwen-code/qwen-code@latest'"
}

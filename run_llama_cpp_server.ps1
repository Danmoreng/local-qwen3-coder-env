<#  run-qwen3-server.ps1  PowerShell 5/7
    ----------------------------------------------------------
    • Stores GGUF under .\models\ next to this script
    • Resumable download via BITS, fallback = Invoke-WebRequest
    • Launches llama-server.exe from llama.cpp with Qwen-3 Coder + speculative decoding
#>

$ScriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Definition
$ServerExe  = Join-Path $ScriptRoot 'vendor\llama.cpp\build\bin\llama-server.exe'

if (-not (Test-Path $ServerExe)) {
    throw "llama-server.exe not found at '$ServerExe' – check the path."
}

$ModelDir       = Join-Path $ScriptRoot 'models'
# Main 30B model
$ModelUrl       = 'https://huggingface.co/unsloth/Qwen3-Coder-Next-GGUF/resolve/main/Qwen3-Coder-Next-UD-Q4_K_XL.gguf'
$ModelFile      = Join-Path $ModelDir (Split-Path $ModelUrl -Leaf)

function Download-IfNeeded {
    param([string]$Url, [Alias('Dest')][string]$Destination)
    if (Test-Path $Destination) {
        Write-Host "[OK] Cached → $Destination"
        return
    }
    New-Item -ItemType Directory -Path (Split-Path $Destination) -Force | Out-Null
    Write-Host "→ downloading: $Url"
    if (Get-Command Start-BitsTransfer -ErrorAction SilentlyContinue) {
        Start-BitsTransfer -Source $Url -Destination $Destination
    } else {
        Invoke-WebRequest -Uri $Url -OutFile $Destination
    }
    Write-Host "[OK] Download complete."
}

Download-IfNeeded -Url $ModelUrl      -Destination $ModelFile

# Row-major speedup
$Env:LLAMA_SET_ROWS = '1'

# Recommended parameters for Qwen3-Coder-Next
$Args = @(
    '--model',             $ModelFile,
    '--alias',             'unsloth/Qwen3-Coder-Next',
    '--fit',               'on',
    '--fit-target',        '256',
    '--jinja',
    '--flash-attn',        'on',
    '-c',                  '32768',
    '-b',                  '1024',
    '-ub',                 '256',
    '-ctk',                'q8_0',
    '-ctv',                'q8_0',
    '--no-mmap',  
    '--n-cpu-moe',         '36',  
    '--temp',              '1.0',
    '--top-p',             '0.95',
    '--top-k',             '40',
    '--min-p',             '0.01'
)

Write-Host "→ Starting llama-server on http://localhost:8080 ..."
$ServerProcess = Start-Process -FilePath $ServerExe -ArgumentList $Args -NoNewWindow -PassThru

# Wait for server to start (simple sleep, ideally would check port)
Write-Host "  Waiting 10 seconds for server to initialize..."
Start-Sleep -Seconds 10

# Configure environment for qwen-code (OpenAI compatible)
$env:OPENAI_API_KEY = "sk-no-key-required"
$env:OPENAI_BASE_URL = "http://localhost:8001/v1"
$env:OPENAI_MODEL = "unsloth/Qwen3-Coder-Next"

#Write-Host "→ Starting qwen-code CLI in a new window..."
#Write-Host "  (The server logs will stay in this window)"

# Launch qwen-code in a new window using PowerShell 7.
# We use EncodedCommand to safely pass environment variables and commands without quoting issues.
#$commands = @'
#$env:OPENAI_API_KEY = "sk-no-key-required"
#$env:OPENAI_BASE_URL = "http://localhost:8001/v1"
#$env:OPENAI_MODEL = "unsloth/Qwen3-Coder-Next"
#qwen
#'@
#$bytes = [System.Text.Encoding]::Unicode.GetBytes($commands)
#$encoded = [Convert]::ToBase64String($bytes)
#Start-Process pwsh -ArgumentList "-NoExit", "-ExecutionPolicy", "Bypass", "-EncodedCommand", $encoded

#Write-Host "→ Press any key to stop the llama-server and exit..."
#$null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")

# Cleanup server
#Write-Host "→ Stopping llama-server..."
#Stop-Process -Id $ServerProcess.Id -Force

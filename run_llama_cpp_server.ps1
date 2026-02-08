<#  run_llama_cpp_server.ps1  PowerShell 5/7
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
    '--fit-ctx',           '32768',
    '-b',                  '1024',
    '-ub',                 '256',
    '-ctk',                'q8_0',
    '-ctv',                'q8_0',
    '--temp',              '1.0',
    '--top-p',             '0.95',
    '--top-k',             '40',
    '--min-p',             '0.01'
)

Write-Host "→ Starting llama-server on http://localhost:8080 ..."
# Start the process in the current console (NoNewWindow) and wait for it to exit
# This allows the user to see logs directly and kill it with Ctrl+C
Start-Process -FilePath $ServerExe -ArgumentList $Args -NoNewWindow -Wait
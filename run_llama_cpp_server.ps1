<#  run-qwen3-server.ps1  PowerShell 5/7
    ----------------------------------------------------------
    • Stores GGUF under .\models\ next to this script
    • Resumable download via BITS, fallback = Invoke-WebRequest
    • Launches llama-server.exe from llama.cpp with Qwen-3 Coder + speculative decoding
#>

param([int]$Threads = 8)

$ScriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Definition
$ServerExe  = Join-Path $ScriptRoot 'vendor\llama.cpp\build\bin\llama-server.exe'

if (-not (Test-Path $ServerExe)) {
    throw "llama-server.exe not found at '$ServerExe' – check the path."
}

$ModelDir       = Join-Path $ScriptRoot 'models'
# Main 30B model
$ModelUrl       = 'https://huggingface.co/unsloth/Qwen3-Coder-30B-A3B-Instruct-1M-GGUF/resolve/main/Qwen3-Coder-30B-A3B-Instruct-1M-IQ4_NL.gguf'
$ModelFile      = Join-Path $ModelDir (Split-Path $ModelUrl -Leaf)
# Draft 0.6B model
# $DraftModelUrl  = 'https://huggingface.co/Qwen/Qwen3-0.6B-GGUF/resolve/main/Qwen3-0.6B-Q8_0.gguf'
# $DraftModelFile = Join-Path $ModelDir (Split-Path $DraftModelUrl -Leaf)

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
# Download-IfNeeded -Url $DraftModelUrl -Destination $DraftModelFile

# Row-major speedup
$Env:LLAMA_SET_ROWS = '1'

$Args = @(
    '--jinja',
    '--model',             $ModelFile,
    '--threads',           $Threads,
    '-fa',
    '-c',                  '65536',
    '-b', '4096',
    '-ub',                '1024', 
    '-ctk',                'q8_0',
    '-ctv',                'q4_0',
       '-ot',      'blk.(0|1|2|3|4|5|6|7|8|9|10|11|12|13|14|15|16|17|18|19).ffn.*exps=CUDA0',
    '-ot',      'exps=CPU',
    '-ngl',                '999',
    '--temp',              '0.6',
    '--top-p',             '0.95',
    '--top-k',             '20',
    '--presence-penalty',  '1.5'
)

Write-Host "→ Starting llama-server on http://localhost:8080 ..."
Start-Process -FilePath $ServerExe -ArgumentList $Args -NoNewWindow

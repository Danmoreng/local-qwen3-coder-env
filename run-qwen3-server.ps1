<#  run-qwen3-server.ps1  PowerShell 5/7
    ----------------------------------------------------------
    â€¢ Stores GGUF under .\models\ next to this script
    â€¢ Resumable download via BITS, fallback = Invoke-WebRequest
    â€¢ Launches llama-server.exe with Qwen-3 Coder 30B params
#>

param([int]$Threads = 8)

$ScriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Definition
$ServerExe  = Join-Path $ScriptRoot 'vendor\ik_llama.cpp\build\bin\llama-server.exe'

$ModelUrl  = 'https://huggingface.co/unsloth/Qwen3-Coder-30B-A3B-Instruct-1M-GGUF/resolve/main/' +
             'Qwen3-Coder-30B-A3B-Instruct-1M-IQ4_XS.gguf'
$ModelDir  = Join-Path $ScriptRoot 'models'
$FileName  = Split-Path $ModelUrl -Leaf
$ModelFile = Join-Path $ModelDir  $FileName

function Download-IfNeeded {
    param(
        [Parameter(Mandatory)][string]$Url,
        [Parameter(Mandatory)][Alias('Dest')][string]$Destination
    )

    if (Test-Path $Destination) {
        Write-Host "[OK] Model already cached ->’ $Destination"
        return
    }
    New-Item -ItemType Directory -Path (Split-Path $Destination) -Force | Out-Null
    Write-Host "->’ downloading model..."
    if (Get-Command Start-BitsTransfer -ErrorAction SilentlyContinue) {
        Start-BitsTransfer -Source $Url -Destination $Destination -DisplayName "Qwen-3 GGUF"
    } else {
        Invoke-WebRequest -Uri $Url -OutFile $Destination
    }
    Write-Host "[OK] download finished"
}

if (-not (Test-Path $ServerExe)) {
    throw "llama-server.exe not found at '$ServerExe' - check the path."
}

Download-IfNeeded -Url $ModelUrl -Destination $ModelFile

$Args = @(
    '--model',  $ModelFile,
    '-fa',
    '-c',       '65536',
    '-ctk',     'q8_0', '-ctv', 'q8_0',
    '-fmoe',
    '-rtr',
    '-ot',      'blk.(0|1|2|3|4|5|6|7|8|9|10|11|12|13|14|15|16|17|18|19).ffn.*exps=CUDA0',
    '-ot',      'exps=CPU',
    '-ngl',     '99',
    '--threads',$Threads,
    '--temp',   '0.6',
    '--min-p',  '0.0',
    '--top-p',  '0.95',
    '--top-k',  '20'
)

Write-Host "-> starting llama-server on http://localhost:8080 ..."
Start-Process -FilePath $ServerExe -ArgumentList $Args -NoNewWindow

<#  run_llama_cpp_server.ps1  PowerShell 5/7
    ----------------------------------------------------------
    • Manages model selection and download
    • Launches llama-server.exe from llama.cpp with optimized settings
#>

$ScriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Definition
$ServerExe  = Join-Path $ScriptRoot 'vendor\llama.cpp\build\bin\llama-server.exe'
$ConfigFile = Join-Path $ScriptRoot ".model_config.ps1"
$ModelDir   = Join-Path $ScriptRoot 'models'

if (-not (Test-Path $ServerExe)) {
    throw "llama-server.exe not found at '$ServerExe' – please run install_llama_cpp.ps1 first."
}

# Ensure model is selected
if (-not (Test-Path $ConfigFile)) {
    & (Join-Path $ScriptRoot "select_model.ps1")
}

# Load Configuration
. $ConfigFile

$ModelFile = Join-Path $ModelDir $MODEL_FILENAME

function Download-IfNeeded {
    param([string]$Url, [string]$Destination)
    if (Test-Path $Destination) {
        Write-Host "[OK] Model found → $Destination"
        return
    }
    if ($Url -eq "NONE") {
        throw "Model file '$Destination' not found and no download URL available for this local selection."
    }
    
    New-Item -ItemType Directory -Path (Split-Path $Destination) -Force | Out-Null
    Write-Host "→ downloading $MODEL_NAME : $Url"
    if (Get-Command Start-BitsTransfer -ErrorAction SilentlyContinue) {
        Start-BitsTransfer -Source $Url -Destination $Destination
    } else {
        Invoke-WebRequest -Uri $Url -OutFile $Destination
    }
    Write-Host "[OK] Download complete."
}

Download-IfNeeded -Url $MODEL_URL -Destination $ModelFile

# Row-major speedup
$Env:LLAMA_SET_ROWS = '1'

# Recommended parameters
$Args = @(
    '--model',             $ModelFile,
    '--alias',             $MODEL_ALIAS,
    '--fit',               'on',
    '--fit-target',        '256',
    '--jinja',
    '--flash-attn',        'on',
    '--fit-ctx',           $MODEL_CTX,
    '-b',                  '1024',
    '-ub',                 '256',
    '-ctk',                'q8_0',
    '-ctv',                'q8_0',
    '--temp',              '1.0',
    '--top-p',             '0.95',
    '--top-k',             '40',
    '--min-p',             '0.01'
)

Write-Host "→ Starting llama-server for $MODEL_NAME on http://localhost:8080 ..."
Start-Process -FilePath $ServerExe -ArgumentList $Args -NoNewWindow -Wait

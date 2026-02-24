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
    param([string]$Url, [string]$Destination, [string]$Label)
    if (Test-Path $Destination) {
        Write-Host "[OK] $Label found → $Destination"
        return
    }
    if ($Url -eq "NONE" -or $Url -eq "LOCAL") {
        if ($Label -eq "Model") {
            throw "Model file '$Destination' not found and no download URL available."
        } else {
            Write-Host "-> No vision projector URL/file found for this selection. Skipping mmproj."
            return $false
        }
    }
    
    New-Item -ItemType Directory -Path (Split-Path $Destination) -Force | Out-Null
    Write-Host "→ downloading $Label : $Url"
    if (Get-Command Start-BitsTransfer -ErrorAction SilentlyContinue) {
        Start-BitsTransfer -Source $Url -Destination $Destination
    } else {
        Invoke-WebRequest -Uri $Url -OutFile $Destination
    }
    Write-Host "[OK] Download complete."
    return $true
}

Download-IfNeeded -Url $MODEL_URL -Destination $ModelFile -Label "Model"

$MmprojArg = @()
$FitTarget = "256"
if ($MMPROJ_FILENAME -ne "NONE") {
    $MmprojPath = Join-Path $ModelDir $MMPROJ_FILENAME
    $success = Download-IfNeeded -Url $MMPROJ_URL -Destination $MmprojPath -Label "Vision Projector"
    if ((Test-Path $MmprojPath)) {
        # Offload vision projector to GPU and reserve VRAM
        $MmprojArg = @('--mmproj', $MmprojPath, '--mmproj-offload')
        $FitTarget = "1536"
        Write-Host "-> Vision model detected. Using GPU offload and FIT_TARGET=$FitTarget"
    }
}

# Row-major speedup
$Env:LLAMA_SET_ROWS = '1'

# Recommended parameters
$Args = @(
    '--model',             $ModelFile
)
$Args += $MmprojArg
$Args += @(
    '--alias',             $MODEL_ALIAS,
    '--fit',               'on',
    '--fit-target',        $FitTarget,
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

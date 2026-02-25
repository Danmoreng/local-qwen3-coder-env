<#  run_llama_cpp_server.ps1  PowerShell 5/7
    ----------------------------------------------------------
    • Manages model selection and download (supports shards)
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

function Download-File {
    param([string]$Url, [string]$Destination, [string]$Label)
    if (Test-Path $Destination) {
        Write-Host "[OK] $Label found → $Destination"
        return $true
    }
    if ($Url -eq "NONE" -or $Url -eq "LOCAL") { return $false }
    
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

# Handle Shards or Single File
if ($MODEL_SHARDS -gt 1) {
    for ($i = 1; $i -le $MODEL_SHARDS; $i++) {
        $shardSuffix = "-$($i.ToString('00000'))-of-$($MODEL_SHARDS.ToString('00000')).gguf"
        $shardFilename = "${MODEL_FILENAME}${shardSuffix}"
        $shardUrl = "${MODEL_URL}${shardSuffix}"
        $shardPath = Join-Path $ModelDir $shardFilename
        Download-File -Url $shardUrl -Destination $shardPath -Label "Shard $i/$MODEL_SHARDS"
    }
    $ModelFile = Join-Path $ModelDir ("${MODEL_FILENAME}-00001-of-$($MODEL_SHARDS.ToString('00000')).gguf")
} else {
    $ModelFile = Join-Path $ModelDir $MODEL_FILENAME
    Download-File -Url $MODEL_URL -Destination $ModelFile -Label "Model"
}

# Vision Projector
$MmprojArg = @()
$FitTarget = "256"
if ($MMPROJ_FILENAME -ne "NONE") {
    $MmprojPath = Join-Path $ModelDir $MMPROJ_FILENAME
    Download-File -Url $MMPROJ_URL -Destination $MmprojPath -Label "Vision Projector"
    if (Test-Path $MmprojPath) {
        $MmprojArg = @('--mmproj', $MmprojPath, '--mmproj-offload')
        $FitTarget = "1536"
        Write-Host "-> Vision model detected. Using GPU offload and FIT_TARGET=$FitTarget"
    }
}

# Row-major speedup
$Env:LLAMA_SET_ROWS = '1'

# Sampling Parameters based on model series
$Temp    = '1.0'
$TopP    = '0.95'
$TopK    = '40'
$MinP    = '0.01'
$PresPen = '0.0'

if ($MODEL_NAME -like "*Qwen3.5*") {
    # Optimized for "Thinking Mode: Precise Coding"
    $Temp    = '0.6'
    $TopK    = '20'
    $MinP    = '0.0'
    Write-Host "-> Qwen 3.5 detected. Applying 'Thinking: Precise Coding' sampling parameters."
} else {
    Write-Host "-> Qwen 3 Coder detected. Applying standard coding sampling parameters."
}

# Recommended parameters
$Args = @('--model', $ModelFile)
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
    '--temp',              $Temp,
    '--top-p',             $TopP,
    '--top-k',             $TopK,
    '--min-p',             $MinP,
    '--presence-penalty',  $PresPen,
    '--top-k',             $TopK,
    '--min-p',             $MinP
)

Write-Host "→ Starting llama-server for $MODEL_NAME on http://localhost:8080 ..."
Start-Process -FilePath $ServerExe -ArgumentList $Args -NoNewWindow -Wait

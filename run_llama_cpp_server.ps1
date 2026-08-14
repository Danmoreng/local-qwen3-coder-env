<#  run_llama_cpp_server.ps1  PowerShell 5/7
    ----------------------------------------------------------
    - Manages model selection and download (supports shards)
    - Launches llama-server.exe from llama.cpp with optimized settings
#>

param(
    [switch]$TextOnly,
    [switch]$LocalModel
)

$ScriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Definition
$ServerExe  = Join-Path $ScriptRoot 'vendor\llama.cpp\build\bin\llama-server.exe'
$ConfigFile = Join-Path $ScriptRoot "model_config.json"
$ModelDir   = Join-Path $ScriptRoot 'models'

function Get-ConfigValue {
    param(
        [Parameter(Mandatory = $true)]$Config,
        [Parameter(Mandatory = $true)][string]$Primary,
        [Parameter(Mandatory = $true)][string]$Fallback
    )

    $value = $Config.$Primary
    if ($null -ne $value -and $value -ne '') { return $value }
    return $Config.$Fallback
}

if (-not (Test-Path $ServerExe)) {
    throw "llama-server.exe not found at '$ServerExe' - please run install_llama_cpp.ps1 first."
}

# Ensure model is selected
if (-not (Test-Path $ConfigFile)) {
    & (Join-Path $ScriptRoot "select_model.ps1")
}

# Load Configuration (JSON)
$Config = Get-Content -Raw $ConfigFile | ConvertFrom-Json
$MODEL_NAME      = Get-ConfigValue -Config $Config -Primary 'MODEL_NAME' -Fallback 'Name'
$MODEL_URL       = Get-ConfigValue -Config $Config -Primary 'MODEL_URL' -Fallback 'Url'
$MODEL_ALIAS     = Get-ConfigValue -Config $Config -Primary 'MODEL_ALIAS' -Fallback 'Alias'
$MODEL_CTX       = Get-ConfigValue -Config $Config -Primary 'MODEL_CTX' -Fallback 'Ctx'
$MODEL_FILENAME  = Get-ConfigValue -Config $Config -Primary 'MODEL_FILENAME' -Fallback 'Filename'
$MODEL_HF_REPO   = Get-ConfigValue -Config $Config -Primary 'MODEL_HF_REPO' -Fallback 'HfRepo'
$MODEL_HF_FILE   = Get-ConfigValue -Config $Config -Primary 'MODEL_HF_FILE' -Fallback 'HfFile'
$MMPROJ_URL      = Get-ConfigValue -Config $Config -Primary 'MMPROJ_URL' -Fallback 'MmprojUrl'
$MMPROJ_FILENAME = Get-ConfigValue -Config $Config -Primary 'MMPROJ_FILENAME' -Fallback 'MmprojFilename'
$MODEL_SHARDS    = Get-ConfigValue -Config $Config -Primary 'MODEL_SHARDS' -Fallback 'Shards'

function Download-File {
    param([string]$Url, [string]$Destination, [string]$Label)
    if (Test-Path $Destination) {
        Write-Host "[OK] $Label found -> $Destination"
        return $true
    }
    if ($Url -eq "NONE" -or $Url -eq "LOCAL") { return $false }
    
    New-Item -ItemType Directory -Path (Split-Path $Destination) -Force | Out-Null
    Write-Host "-> downloading $Label : $Url"

    $curl = Get-Command curl.exe -ErrorAction SilentlyContinue
    if ($null -ne $curl) {
        & $curl.Source -L --fail --retry 5 --retry-delay 5 --output $Destination $Url
        if ($LASTEXITCODE -ne 0) {
            throw "Download failed for $Label from '$Url' (curl exit code $LASTEXITCODE)."
        }
    } else {
        Invoke-WebRequest -Uri $Url -OutFile $Destination -ErrorAction Stop
    }

    if (-not (Test-Path $Destination)) {
        throw "Download failed for $Label. File was not created at '$Destination'."
    }

    Write-Host "[OK] Download complete."
    return $true
}

if ([string]::IsNullOrWhiteSpace($MODEL_HF_REPO) -or $MODEL_HF_REPO -eq 'NONE') {
    $LocalModel = $true
}

$ModelArgs = @()
if ($LocalModel -and $MODEL_SHARDS -gt 1) {
    for ($i = 1; $i -le $MODEL_SHARDS; $i++) {
        $shardSuffix = "-$($i.ToString('00000'))-of-$($MODEL_SHARDS.ToString('00000')).gguf"
        $shardFilename = "${MODEL_FILENAME}${shardSuffix}"
        $shardUrl = "${MODEL_URL}${shardSuffix}"
        $shardPath = Join-Path $ModelDir $shardFilename
        Download-File -Url $shardUrl -Destination $shardPath -Label "Shard $i/$MODEL_SHARDS"
    }
    $ModelFile = Join-Path $ModelDir ("${MODEL_FILENAME}-00001-of-$($MODEL_SHARDS.ToString('00000')).gguf")
    $ModelArgs = @('--model', $ModelFile)
} elseif ($LocalModel) {
    $ModelFile = Join-Path $ModelDir $MODEL_FILENAME
    Download-File -Url $MODEL_URL -Destination $ModelFile -Label "Model"
    $ModelArgs = @('--model', $ModelFile)
} else {
    $ModelArgs = @('--hf-repo', $MODEL_HF_REPO, '--hf-file', $MODEL_HF_FILE)
}

if ($LocalModel) {
    Write-Host "-> Model source: local fallback ($ModelFile)"
} else {
    Write-Host "-> Model source: Hugging Face cache ($MODEL_HF_REPO / $MODEL_HF_FILE)"
}

# Vision Projector
$MmprojArg = @()
$FitTarget = "256"
if ($TextOnly) {
    Write-Host "-> Text-only mode enabled. Skipping vision projector and using FIT_TARGET=$FitTarget"
    if (-not $LocalModel) { $MmprojArg = @('--no-mmproj') }
} elseif (-not $LocalModel -and $MMPROJ_FILENAME -ne "NONE") {
    $MmprojArg = @('--mmproj-auto', '--mmproj-offload')
    $FitTarget = "1536"
    Write-Host "-> Vision mode enabled. The projector will use the Hugging Face cache."
} elseif ($MMPROJ_FILENAME -ne "NONE") {
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

if ($MODEL_NAME -match 'Qwen3\.8') {
    $Temp    = '1.0'
    $TopK    = '20'
    $MinP    = '0.0'
    Write-Host "-> Qwen 3.8 detected. Applying official thinking-mode sampling parameters."
} elseif ($MODEL_NAME -match 'Qwen3\.(5|6)') {
    # Optimized for Qwen 3.5 / 3.6 reasoning models
    $Temp    = '0.6'
    $TopK    = '20'
    $MinP    = '0.0'
    Write-Host "-> Qwen 3.5 / 3.6 detected. Applying 'Thinking: Precise Coding' sampling parameters."
} else {
    Write-Host "-> Qwen 3 Coder detected. Applying standard coding sampling parameters."
}

$ReasoningArgs = @()
if ($MODEL_NAME -match 'Qwen3\.8') {
    $Env:LLAMA_CHAT_TEMPLATE_KWARGS = '{"enable_thinking":true,"preserve_thinking":true,"reasoning_effort":"xhigh"}'
    $ReasoningArgs = @('--reasoning-preserve')
    Write-Host "-> Qwen 3.8 detected. Enabling preserved thinking with xhigh reasoning effort."
} elseif ($MODEL_NAME -match 'Qwen3\.6') {
    $Env:LLAMA_CHAT_TEMPLATE_KWARGS = '{"preserve_thinking":true}'
    $ReasoningArgs = @('--reasoning-preserve')
    Write-Host "-> Qwen 3.6 detected. Enabling preserve_thinking in the chat template."
} else {
    Remove-Item Env:LLAMA_CHAT_TEMPLATE_KWARGS -ErrorAction SilentlyContinue
}

# Recommended parameters
$BatchSize = '1024'
$UBatchSize = '512'

$Args = $ModelArgs
$Args += $MmprojArg
$Args += $ReasoningArgs
$Args += @(
    '--alias',             $MODEL_ALIAS,
    '--fit',               'on',
    '--fit-target',        $FitTarget,
    '--jinja',
    '--flash-attn',        'on',
    '--no-mmap',
    '-np',                 '1',
    '--fit-ctx',           $MODEL_CTX,
    '-b',                  $BatchSize,
    '-ub',                 $UBatchSize,
    '-ctk',                'q8_0',
    '-ctv',                'q8_0',
    '--temp',              $Temp,
    '--top-p',             $TopP,
    '--top-k',             $TopK,
    '--min-p',             $MinP,
    '--presence-penalty',  $PresPen,
    '--repeat-penalty',    '1.0'
)

Write-Host "-> Starting llama-server for $MODEL_NAME on http://localhost:8080 ..."
Start-Process -FilePath $ServerExe -ArgumentList $Args -NoNewWindow -Wait

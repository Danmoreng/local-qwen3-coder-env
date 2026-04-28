<#  run_qwen3_6_27b_optimized.ps1  PowerShell 5/7
    ----------------------------------------------------------
    Specialized launcher for Qwen 3.6 27B presets on Windows.
    - Defaults to text-only mode for 16GB-class VRAM
    - Supports optional vision mode via -Vision
#>

param(
    [switch]$Vision
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

if (-not (Test-Path $ServerExe)) {
    throw "llama-server.exe not found at '$ServerExe' - please run install_llama_cpp.ps1 first."
}

if (-not (Test-Path $ConfigFile)) {
    & (Join-Path $ScriptRoot "select_model.ps1")
}

$Config = Get-Content -Raw $ConfigFile | ConvertFrom-Json
$MODEL_NAME      = Get-ConfigValue -Config $Config -Primary 'MODEL_NAME' -Fallback 'Name'
$MODEL_URL       = Get-ConfigValue -Config $Config -Primary 'MODEL_URL' -Fallback 'Url'
$MODEL_ALIAS     = Get-ConfigValue -Config $Config -Primary 'MODEL_ALIAS' -Fallback 'Alias'
$MODEL_CTX       = Get-ConfigValue -Config $Config -Primary 'MODEL_CTX' -Fallback 'Ctx'
$MODEL_FILENAME  = Get-ConfigValue -Config $Config -Primary 'MODEL_FILENAME' -Fallback 'Filename'
$MMPROJ_URL      = Get-ConfigValue -Config $Config -Primary 'MMPROJ_URL' -Fallback 'MmprojUrl'
$MMPROJ_FILENAME = Get-ConfigValue -Config $Config -Primary 'MMPROJ_FILENAME' -Fallback 'MmprojFilename'
$MODEL_SHARDS    = Get-ConfigValue -Config $Config -Primary 'MODEL_SHARDS' -Fallback 'Shards'

# This launcher is intentionally fixed to the best 16GB-class Qwen3.6-27B setup:
# UD-IQ3_XXS leaves enough VRAM for long Q8 KV cache while keeping the model fully GPU-resident.
$MODEL_NAME      = 'Qwen3.6-27B (Dense) - UD-IQ3_XXS'
$MODEL_URL       = 'https://huggingface.co/unsloth/Qwen3.6-27B-GGUF/resolve/main/Qwen3.6-27B-UD-IQ3_XXS.gguf'
$MODEL_ALIAS     = 'unsloth/Qwen3.6-27B-UD-IQ3_XXS'
$MODEL_CTX       = 65536
$MODEL_FILENAME  = 'Qwen3.6-27B-UD-IQ3_XXS.gguf'
$MMPROJ_URL      = 'https://huggingface.co/unsloth/Qwen3.6-27B-GGUF/resolve/main/mmproj-BF16.gguf'
$MMPROJ_FILENAME = 'mmproj-Qwen3.6-27B.gguf'
$MODEL_SHARDS    = 1

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

$TextOnly = -not $Vision
$MmprojArg = @()
$FitTarget = "256"

if ($TextOnly) {
    Write-Host "-> Text-only mode enabled. Using FIT_TARGET=$FitTarget."
} elseif ($MMPROJ_FILENAME -ne "NONE") {
    $MmprojPath = Join-Path $ModelDir $MMPROJ_FILENAME
    Download-File -Url $MMPROJ_URL -Destination $MmprojPath -Label "Vision Projector"
    if (Test-Path $MmprojPath) {
        $MmprojArg = @('--mmproj', $MmprojPath, '--mmproj-offload')
        $FitTarget = "1536"
        Write-Host "-> Vision mode enabled. Using FIT_TARGET=$FitTarget with mmproj offload."
    }
}

$EffectiveCtx = "$MODEL_CTX"
$EffectiveCacheTypeK = 'q8_0'
$EffectiveCacheTypeV = 'q8_0'

$Env:LLAMA_SET_ROWS = '1'
$Env:LLAMA_CHAT_TEMPLATE_KWARGS = '{"preserve_thinking":true}'

$Args = @('--model', $ModelFile)
$Args += $MmprojArg
$Args += @(
    '--alias',             $MODEL_ALIAS,
    '--fit',               'on',
    '--fit-target',        $FitTarget,
    '--jinja',
    '--flash-attn',        'on',
    '--no-mmap',
    '-np',                 '1',
    '--fit-ctx',           $EffectiveCtx,
    '-b',                  '1024',
    '-ub',                 '512',
    '-ctk',                $EffectiveCacheTypeK,
    '-ctv',                $EffectiveCacheTypeV,
    '--temp',              '0.6',
    '--top-p',             '0.95',
    '--top-k',             '20',
    '--min-p',             '0.0',
    '--presence-penalty',  '0.0',
    '--spec-type',         'ngram-map-k',
    '--spec-ngram-map-k-size-n', '16',
    '--spec-draft-n-min',  '12',
    '--spec-draft-n-max',  '48'
)
Write-Host "-> Speculative decoding preset: ngram-map-k, n=16, draft 12..48."
Write-Host "-> KV cache types: K=$EffectiveCacheTypeK, V=$EffectiveCacheTypeV. Minimum fit context floor: $EffectiveCtx."

Write-Host "-> Starting optimized llama-server for $MODEL_NAME on http://localhost:8080 ..."
Start-Process -FilePath $ServerExe -ArgumentList $Args -NoNewWindow -Wait

<# Qwen3.8-27B launcher tuned for 16GB NVIDIA GPUs. #>

param(
    [switch]$Vision,
    [switch]$LocalModel,
    [switch]$SafeContext
)

$ScriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Definition
$ServerExe = Join-Path $ScriptRoot 'vendor\llama.cpp\build\bin\llama-server.exe'
$ModelDir = Join-Path $ScriptRoot 'models'

$ModelName = 'Qwen3.8-27B (Dense) - UD-IQ3_XXS'
$ModelAlias = 'unsloth/Qwen3.8-27B-UD-IQ3_XXS'
$ModelHfRepo = 'unsloth/Qwen3.8-27B-GGUF'
$ModelHfFile = 'Qwen3.8-27B-UD-IQ3_XXS.gguf'
$ModelHfRevision = '27af057ecb382ddfea5d12837360a8980560e3ed'
$ModelLocalFile = 'Qwen3.8-27B-UD-IQ3_XXS-Dynamic3-27af057.gguf'
$ModelUrl = "https://huggingface.co/$ModelHfRepo/resolve/$ModelHfRevision/$ModelHfFile"
$MmprojFilename = 'mmproj-Qwen3.8-27B.gguf'
$MmprojUrl = "https://huggingface.co/$ModelHfRepo/resolve/$ModelHfRevision/mmproj-BF16.gguf"
$ContextSize = if ($SafeContext -or $Vision) { 81920 } else { 98304 }
$ContextK = [int]($ContextSize / 1024)

if (-not (Test-Path $ServerExe)) {
    throw "llama-server.exe not found at '$ServerExe' - run install_llama_cpp.ps1 first."
}

function Download-File {
    param([string]$Url, [string]$Destination, [string]$Label)
    if (Test-Path $Destination) { return }
    New-Item -ItemType Directory -Path (Split-Path $Destination) -Force | Out-Null
    Write-Host "-> Downloading ${Label}: $Url"
    $curl = Get-Command curl.exe -ErrorAction SilentlyContinue
    if ($null -ne $curl) {
        & $curl.Source -L --fail --retry 5 --retry-delay 5 --output $Destination $Url
        if ($LASTEXITCODE -ne 0) { throw "Download failed for $Label." }
    } else {
        Invoke-WebRequest -Uri $Url -OutFile $Destination -ErrorAction Stop
    }
}

function Resolve-HfFile {
    param([string]$Repo, [string]$File, [string]$Revision)
    $hf = Get-Command hf -ErrorAction SilentlyContinue
    if ($null -eq $hf) { return $null }

    Write-Host "-> Resolving pinned Hugging Face revision ${Revision}: $Repo / $File"
    $output = @(& $hf.Source download $Repo $File --revision $Revision --quiet)
    if ($LASTEXITCODE -ne 0) { throw "hf download failed for '$Repo/$File'." }
    $path = [string]($output | Select-Object -Last 1)
    $path = $path.Trim()
    if ($path.StartsWith('path=')) { $path = $path.Substring(5) }
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        throw "hf did not return a valid file path: '$path'."
    }
    return (Resolve-Path -LiteralPath $path).Path
}

$ModelArgs = @()
$MmprojArgs = @()
$FitArgs = @('--fit', 'off')
$ContextArgs = @('-c', [string]$ContextSize)

if ($LocalModel) {
    $ModelFile = Join-Path $ModelDir $ModelLocalFile
    Download-File -Url $ModelUrl -Destination $ModelFile -Label 'model'
    $ModelArgs = @('--model', $ModelFile)
    Write-Host "-> Model source: local fallback ($ModelFile)"
    if ($Vision) {
        $MmprojFile = Join-Path $ModelDir $MmprojFilename
        Download-File -Url $MmprojUrl -Destination $MmprojFile -Label 'vision projector'
        $MmprojArgs = @('--mmproj', $MmprojFile, '--mmproj-offload')
        $FitArgs = @('--fit', 'on', '--fit-target', '1536', '--fit-ctx', [string]$ContextSize)
        $ContextArgs = @()
    } else {
        $MmprojArgs = @('--no-mmproj')
    }
} else {
    $CachedModel = Resolve-HfFile -Repo $ModelHfRepo -File $ModelHfFile -Revision $ModelHfRevision
    if ($null -ne $CachedModel) {
        $ModelArgs = @('--model', $CachedModel)
        Write-Host "-> Model source: Hugging Face Xet cache ($CachedModel)"
    } else {
        $ModelArgs = @('--hf-repo', $ModelHfRepo, '--hf-file', $ModelHfFile)
        Write-Host "-> 'hf' CLI not found; using llama.cpp's built-in downloader."
    }
    if ($Vision) {
        $CachedMmproj = Resolve-HfFile -Repo $ModelHfRepo -File 'mmproj-BF16.gguf' -Revision $ModelHfRevision
        if ($null -ne $CachedMmproj) {
            $MmprojArgs = @('--mmproj', $CachedMmproj, '--mmproj-offload')
        } else {
            $MmprojArgs = @('--mmproj-auto', '--mmproj-offload')
        }
        $FitArgs = @('--fit', 'on', '--fit-target', '1536', '--fit-ctx', [string]$ContextSize)
        $ContextArgs = @()
    } else {
        $MmprojArgs = @('--no-mmproj')
    }
}

$Args = $ModelArgs
$Args += $MmprojArgs
$Args += $FitArgs
$Args += $ContextArgs
$Args += @(
    '--alias', $ModelAlias,
    '--flash-attn', 'on',
    '-np', '1',
    '-b', '1024',
    '-ub', '512',
    '-ctk', 'q8_0',
    '-ctv', 'q8_0',
    '--temp', '1.0',
    '--top-p', '0.95',
    '--top-k', '20',
    '--min-p', '0.0',
    '--presence-penalty', '0.0',
    '--repeat-penalty', '1.0',
    '--reasoning-effort', 'medium',
    '--reasoning-budget', '8192',
    '--reasoning-budget-message', '... I have been thinking for too long -- let me gather more information about the task and take the next concrete action.',
    '--reasoning-preserve',
    '--spec-default',
    '--spec-type', 'draft-mtp',
    '--host', '0.0.0.0',
    '--port', '8080'
)

Write-Host "-> Starting optimized llama-server for $ModelName on http://localhost:8080"
if ($Vision) {
    Write-Host "-> Vision mode: dynamic GPU fitting, ${ContextK}K context floor, Q8 KV cache, MTP speculative decoding"
} else {
    Write-Host "-> Text mode: fixed ${ContextK}K context, full GPU placement, Q8 KV cache, MTP speculative decoding"
}
& $ServerExe @Args
if ($LASTEXITCODE -ne 0) {
    throw "llama-server exited with code $LASTEXITCODE."
}

<# Qwen3.8-27B launcher tuned for 16GB NVIDIA GPUs. #>

param(
    [switch]$Vision,
    [switch]$LocalModel
)

$ScriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Definition
$ServerExe = Join-Path $ScriptRoot 'vendor\llama.cpp\build\bin\llama-server.exe'
$ModelDir = Join-Path $ScriptRoot 'models'

$ModelName = 'Qwen3.8-27B (Dense) - UD-IQ3_XXS'
$ModelAlias = 'unsloth/Qwen3.8-27B-UD-IQ3_XXS'
$ModelHfRepo = 'unsloth/Qwen3.8-27B-GGUF'
$ModelHfFile = 'Qwen3.8-27B-UD-IQ3_XXS.gguf'
$ModelUrl = "https://huggingface.co/$ModelHfRepo/resolve/main/$ModelHfFile"
$MmprojFilename = 'mmproj-Qwen3.8-27B.gguf'
$MmprojUrl = "https://huggingface.co/$ModelHfRepo/resolve/main/mmproj-BF16.gguf"

if (-not (Test-Path $ServerExe)) {
    throw "llama-server.exe not found at '$ServerExe' - run install_llama_cpp.ps1 first."
}

function Download-File {
    param([string]$Url, [string]$Destination, [string]$Label)
    if (Test-Path $Destination) { return }
    New-Item -ItemType Directory -Path (Split-Path $Destination) -Force | Out-Null
    Write-Host "-> Downloading $Label: $Url"
    $curl = Get-Command curl.exe -ErrorAction SilentlyContinue
    if ($null -ne $curl) {
        & $curl.Source -L --fail --retry 5 --retry-delay 5 --output $Destination $Url
        if ($LASTEXITCODE -ne 0) { throw "Download failed for $Label." }
    } else {
        Invoke-WebRequest -Uri $Url -OutFile $Destination -ErrorAction Stop
    }
}

function Resolve-HfFile {
    param([string]$Repo, [string]$File)
    $hf = Get-Command hf -ErrorAction SilentlyContinue
    if ($null -eq $hf) { return $null }

    Write-Host "-> Downloading or resolving with Hugging Face Xet: $Repo / $File"
    $output = @(& $hf.Source download $Repo $File)
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
$FitTarget = '256'

if ($LocalModel) {
    $ModelFile = Join-Path $ModelDir $ModelHfFile
    Download-File -Url $ModelUrl -Destination $ModelFile -Label 'model'
    $ModelArgs = @('--model', $ModelFile)
    Write-Host "-> Model source: local fallback ($ModelFile)"
    if ($Vision) {
        $MmprojFile = Join-Path $ModelDir $MmprojFilename
        Download-File -Url $MmprojUrl -Destination $MmprojFile -Label 'vision projector'
        $MmprojArgs = @('--mmproj', $MmprojFile, '--mmproj-offload')
        $FitTarget = '1536'
    }
} else {
    $CachedModel = Resolve-HfFile -Repo $ModelHfRepo -File $ModelHfFile
    if ($null -ne $CachedModel) {
        $ModelArgs = @('--model', $CachedModel)
        Write-Host "-> Model source: Hugging Face Xet cache ($CachedModel)"
    } else {
        $ModelArgs = @('--hf-repo', $ModelHfRepo, '--hf-file', $ModelHfFile)
        Write-Host "-> 'hf' CLI not found; using llama.cpp's built-in downloader."
    }
    if ($Vision) {
        $CachedMmproj = Resolve-HfFile -Repo $ModelHfRepo -File 'mmproj-BF16.gguf'
        if ($null -ne $CachedMmproj) {
            $MmprojArgs = @('--mmproj', $CachedMmproj, '--mmproj-offload')
        } else {
            $MmprojArgs = @('--mmproj-auto', '--mmproj-offload')
        }
        $FitTarget = '1536'
    } else {
        $MmprojArgs = @('--no-mmproj')
    }
}

$Env:LLAMA_SET_ROWS = '1'
$Env:LLAMA_CHAT_TEMPLATE_KWARGS = '{"enable_thinking":true,"preserve_thinking":true,"reasoning_effort":"xhigh"}'

$Args = $ModelArgs
$Args += $MmprojArgs
$Args += @(
    '--alias', $ModelAlias,
    '--fit', 'on',
    '--fit-target', $FitTarget,
    '--jinja',
    '--flash-attn', 'on',
    '-np', '1',
    '--fit-ctx', '65536',
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
    '--reasoning-preserve',
    '--spec-type', 'draft-mtp',
    '--host', '0.0.0.0',
    '--port', '8080'
)

Write-Host "-> Starting optimized llama-server for $ModelName on http://localhost:8080"
Write-Host "-> 64K context, Q8 KV cache, MTP speculative decoding, vision=$Vision"
Start-Process -FilePath $ServerExe -ArgumentList $Args -NoNewWindow -Wait

<# select_model.ps1 #>
$ScriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Definition
$ModelDir   = Join-Path $ScriptRoot "models"
$ConfigFile = Join-Path $ScriptRoot ".model_config.ps1"

if (-not (Test-Path $ModelDir)) {
    New-Item -ItemType Directory -Path $ModelDir -Force | Out-Null
}

# 1. Define Known Models
$KnownModels = @(
    @{ Name = "Qwen3-Coder-Next (80B MoE) - Q4_K_M";  Url = "https://huggingface.co/unsloth/Qwen3-Coder-Next-GGUF/resolve/main/Qwen3-Coder-Next-Q4_K_M.gguf";  Alias = "unsloth/Qwen3-Coder-Next"; Ctx = 32768; Filename = "Qwen3-Coder-Next-Q4_K_M.gguf"; MmprojUrl = "NONE"; MmprojFilename = "NONE"; Shards = 1 },
    @{ Name = "Qwen3-Coder-Next (80B MoE) - MXFP4";   Url = "https://huggingface.co/unsloth/Qwen3-Coder-Next-GGUF/resolve/main/Qwen3-Coder-Next-MXFP4_MOE.gguf";   Alias = "unsloth/Qwen3-Coder-Next-MXFP4";   Ctx = 65536; Filename = "Qwen3-Coder-Next-MXFP4_MOE.gguf"; MmprojUrl = "NONE"; MmprojFilename = "NONE"; Shards = 1 },
    @{ Name = "Qwen3.5-27B (Dense) - Q4_K_M";        Url = "https://huggingface.co/unsloth/Qwen3.5-27B-GGUF/resolve/main/Qwen3.5-27B-Q4_K_M.gguf";        Alias = "unsloth/Qwen3.5-27B";        Ctx = 32768; Filename = "Qwen3.5-27B-Q4_K_M.gguf"; MmprojUrl = "https://huggingface.co/unsloth/Qwen3.5-27B-GGUF/resolve/main/mmproj-BF16.gguf"; MmprojFilename = "mmproj-Qwen3.5-27B.gguf"; Shards = 1 },
    @{ Name = "Qwen3.5-35B-A3B (MoE) - Q4_K_M";      Url = "https://huggingface.co/unsloth/Qwen3.5-35B-A3B-GGUF/resolve/main/Qwen3.5-35B-A3B-Q4_K_M.gguf";      Alias = "unsloth/Qwen3.5-35B-A3B";      Ctx = 32768; Filename = "Qwen3.5-35B-A3B-Q4_K_M.gguf"; MmprojUrl = "https://huggingface.co/unsloth/Qwen3.5-35B-A3B-GGUF/resolve/main/mmproj-BF16.gguf"; MmprojFilename = "mmproj-Qwen3.5-35B.gguf"; Shards = 1 },
    @{ Name = "Qwen3.5-122B-A10B (MoE) - Q4_K_M";    Url = "https://huggingface.co/unsloth/Qwen3.5-122B-A10B-GGUF/resolve/main/Q4_K_M/Qwen3.5-122B-A10B-Q4_K_M"; Alias = "unsloth/Qwen3.5-122B-A10B"; Ctx = 32768; Filename = "Qwen3.5-122B-A10B-Q4_K_M"; MmprojUrl = "https://huggingface.co/unsloth/Qwen3.5-122B-A10B-GGUF/resolve/main/mmproj-BF16.gguf"; MmprojFilename = "mmproj-Qwen3.5-122B.gguf"; Shards = 2 }
)

# 2. Collect All Options
$AllOptions = New-Object System.Collections.Generic.List[PSObject]
foreach ($km in $KnownModels) { $AllOptions.Add((New-Object PSObject -Property $km)) }

# 3. Scan for Local Models
$LocalFiles = Get-ChildItem -Path $ModelDir -Filter "*.gguf"
foreach ($file in $LocalFiles) {
    if ($file.Name -like "mmproj*") { continue }
    if ($file.Name -match "-0000[2-9]") { continue }
    $found = $false
    foreach ($km in $KnownModels) { if ($km.Filename -eq $file.Name) { $found = $true; break } }
    if (-not $found) {
        $AllOptions.Add((New-Object PSObject -Property @{
            Name = "Local: $($file.Name)"; Url = "NONE"; Alias = "local/$($file.BaseName)"; Ctx = 32768; Filename = $file.Name; MmprojUrl = "NONE"; MmprojFilename = "NONE"; Shards = 1
        }))
    }
}

# 4. Display Menu
Write-Host "------------------------------------------"
Write-Host " Available Models (Local files detected *)"
Write-Host "------------------------------------------"
for ($i = 0; $i -lt $AllOptions.Count; $i++) {
    $opt = $AllOptions[$i]
    $status = ""
    $checkFile = $opt.Filename
    if ($opt.Shards -gt 1) { $checkFile = "$($opt.Filename)-00001-of-$($opt.Shards.ToString('00000')).gguf" }
    if (Test-Path (Join-Path $ModelDir $checkFile)) { $status = "[Found]" }
    Write-Host "[$($i + 1)] $($opt.Name) $status"
}
Write-Host "------------------------------------------"

$choice = Read-Host "Selection [1-$($AllOptions.Count)]"
$index = 0
if ([int]::TryParse($choice, [ref]$index)) { $index -= 1 } else { $index = -1 }

if ($index -ge 0 -and $index -lt $AllOptions.Count) {
    $Selected = $AllOptions[$index]
    if ($Selected.Url -eq "NONE") {
        $userCtx = Read-Host "Enter context size for $($Selected.Filename) [default $($Selected.Ctx)]"
        if (-not [string]::IsNullOrWhiteSpace($userCtx)) { $Selected.Ctx = $userCtx }
        $hasMmproj = Read-Host "Does this model need a vision projector (mmproj)? [y/N]"
        if ($hasMmproj -match "y") {
            $userMmproj = Read-Host "Enter mmproj URL (or filename in models/)"
            if ($userMmproj -match "^http") {
                $Selected.MmprojUrl = $userMmproj
                $Selected.MmprojFilename = "mmproj-custom-$([DateTimeOffset]::Now.ToUnixTimeSeconds()).gguf"
            } else { $Selected.MmprojFilename = $userMmproj }
        }
    }

    $ConfigContent = @"
`$MODEL_NAME = '$($Selected.Name)'
`$MODEL_URL  = '$($Selected.Url)'
`$MODEL_ALIAS = '$($Selected.Alias)'
`$MODEL_CTX  = $($Selected.Ctx)
`$MODEL_FILENAME = '$($Selected.Filename)'
`$MMPROJ_URL = '$($Selected.MmprojUrl)'
`$MMPROJ_FILENAME = '$($Selected.MmprojFilename)'
`$MODEL_SHARDS = $($Selected.Shards)
"@
    Set-Content -Path $ConfigFile -Value $ConfigContent
    Write-Host "Selected: $($Selected.Name)"
    Write-Host "Config saved to .model_config.ps1"
} else { Write-Error "Invalid selection."; exit 1 }

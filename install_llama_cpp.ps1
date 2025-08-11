<#
    install_llama_cpp.ps1
    ---------------------
    Installs all prerequisites and builds ggerganov/llama.cpp on Windows.

    • Works on Windows PowerShell 5 and PowerShell 7
    • Uses the Ninja generator (fast, no VS-integration dependency)
    • Re-usable: just run the script; it installs only what is missing
    • Pass -CudaArch <SM> to target a different GPU
      (defaults to 89 = Ada; GTX-1070 = 61, RTX-30-series = 86, etc.)
#>

[CmdletBinding()]
param(
    [int]   $CudaArch = 89,
    [switch]$SkipBuild
)

$ScriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Definition

# ---------------------------------------------------------------------------
# Helper functions
# ---------------------------------------------------------------------------

function Assert-Admin {
    $id  = [Security.Principal.WindowsIdentity]::GetCurrent()
    $prn = New-Object Security.Principal.WindowsPrincipal($id)
    if (-not $prn.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        throw "Run this script from an *elevated* PowerShell window."
    }
}

function Test-Command ([string]$Name) {
    (Get-Command $Name -ErrorAction SilentlyContinue) -ne $null
}

function Test-VSTools {
    $vswhere = Join-Path ${Env:ProgramFiles(x86)} 'Microsoft Visual Studio\Installer\vswhere.exe'
    if (-not (Test-Path $vswhere)) { return $false }
    $path = & $vswhere -latest -products * `
            -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 `
            -property installationPath 2>$null
    -not [string]::IsNullOrWhiteSpace($path)
}

function Test-CUDA {
    $root = 'C:\Program Files\NVIDIA GPU Computing Toolkit\CUDA'
    if (-not (Test-Path $root)) { return $false }
    foreach ($d in Get-ChildItem $root -Directory) {
        if ($d.Name -match '^v13\.(\d+)$' -and [int]$Matches[1] -ge 0) { return $true }
    }
    return $false
}

function Wait-Until ($TestFn, [int]$TimeoutMin, [string]$What) {
    Write-Host "  waiting for $What ..."
    $sw = [Diagnostics.Stopwatch]::StartNew()
    while ($sw.Elapsed.TotalMinutes -lt $TimeoutMin) {
        if (& $TestFn) { return }
        Start-Sleep 30
    }
    throw "$What did not finish installing in $TimeoutMin minutes."
}

function Install-Winget ([string]$Id, [string]$Override = '') {
    Write-Host "-> installing $Id ..."
    $args = @(
        'install','--id',$Id,'--silent','--disable-interactivity',
        '--accept-source-agreements','--accept-package-agreements','-e','--wait'
    )
    if ($Override) { $args += @('--override', "`"$Override`"") }
    $p = Start-Process winget -ArgumentList $args -NoNewWindow -Wait -PassThru
    # -1978335189 (0x8A150005) = "no applicable upgrade found"
    if ($p.ExitCode -and $p.ExitCode -ne -1978335189) {
        throw "winget failed (exit $($p.ExitCode)) while installing $Id"
    }
}

function Install-VSTools {
    Write-Host "-> downloading and installing VS 2022 Build Tools ..."
    $url  = 'https://aka.ms/vs/17/release/vs_BuildTools.exe'
    $exe  = Join-Path $env:TEMP 'vs_BuildTools.exe'
    Invoke-WebRequest -Uri $url -OutFile $exe
    $args = '--add Microsoft.VisualStudio.Workload.VCTools --includeRecommended --quiet --norestart --wait'
    $p = Start-Process -FilePath $exe -ArgumentList $args -Wait -PassThru
    if ($p.ExitCode -ne 0 -and $p.ExitCode -ne 3010) {
        throw "VS Build Tools installer failed with exit code $($p.ExitCode)."
    }
}

# Bring MSVC variables (cl, link, lib paths, etc.) into this PowerShell session
function Import-VSEnv {
    $vswhere = Join-Path ${Env:ProgramFiles(x86)} 'Microsoft Visual Studio\Installer\vswhere.exe'
    $vsroot  = & $vswhere -latest -products * `
               -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 `
               -property installationPath 2>$null
    if (-not $vsroot) { throw "VS Build Tools not found." }

    $vcvars = Join-Path $vsroot 'VC\Auxiliary\Build\vcvars64.bat'
    Write-Host "  importing MSVC environment from $vcvars"
    $envDump = cmd /s /c "`"$vcvars`" && set"
    foreach ($line in $envDump -split "`r?`n") {
        if ($line -match '^(.*?)=(.*)$') {
            $name,$value = $Matches[1],$Matches[2]
            Set-Item -Path "Env:$name" -Value $value
        }
    }
}

# Select newest CUDA 13.x >=12.4, export env, return CMake arg
function Use-LatestCuda {
    $root = 'C:\Program Files\NVIDIA GPU Computing Toolkit\CUDA'
    $latest = Get-ChildItem $root -Directory |
              Where-Object Name -Match '^v13\.(\d+)$' |
              Sort-Object { [int]($_.Name -replace '^v13\.') } -Descending |
              Select-Object -First 1
    if (-not $latest) { throw 'No CUDA 13.x installation found.' }

    $env:CUDA_PATH = $latest.FullName
    $minor = ($latest.Name -split '\.')[1]
    Set-Item -Path ("Env:CUDA_PATH_V13_$minor") -Value $latest.FullName
    $env:Path = "$($latest.FullName)\bin;$env:Path"

    Write-Host "  Using CUDA toolkit at $($env:CUDA_PATH)"
    "-DCUDAToolkit_ROOT=$($latest.FullName)"
}

# ---------------------------------------------------------------------------
# Main routine
# ---------------------------------------------------------------------------

Assert-Admin

$reqs = @(
    @{Name='Git';            Test={ Test-Command git };   Id='Git.Git' },
    @{Name='CMake';          Test={ Test-Command cmake }; Id='Kitware.CMake' },
    @{Name='Ninja';          Test={ Test-Command ninja }; Id='Kitware.Ninja' },
    @{Name='VS Build Tools'; Test={ Test-VSTools };
      Id='Microsoft.VisualStudio.2022.BuildTools';
      Override='--add Microsoft.VisualStudio.Workload.VCTools --includeRecommended --quiet --norestart' },
    @{Name='CUDA Toolkit >=12.4'; Test={ Test-CUDA }; Id='Nvidia.CUDA' }
)

foreach ($r in $reqs) {
    if (-not (& $r.Test)) {
        if ($r.Name -eq 'VS Build Tools') {
            Install-VSTools
            if (-not (Wait-VSToolsReady)) { throw 'VS Build Tools install timed out.' }
        }
        else {
            Install-Winget -Id $r.Id -Override $r.Override
            if ($r.Name -eq 'CUDA Toolkit >=12.4') {
                if (-not (Wait-CUDAReady)) { throw 'CUDA install timed out.' }
            }
            elseif (-not (& $r.Test)) {
                throw "$($r.Name) could not be installed automatically."
            }
        }
    }
    Write-Host ("[OK] {0}" -f $r.Name)
}

Import-VSEnv   # make cl.exe etc. available in this session

if ($SkipBuild) { Write-Host 'SkipBuild set – done.'; return }

# ---------------------------------------------------------------------------
# Clone & build ggerganov/llama.cpp
# ---------------------------------------------------------------------------

$LlamaRepo   = Join-Path $ScriptRoot 'vendor\llama.cpp'
$LlamaBuild  = Join-Path $LlamaRepo  'build'

if (-not (Test-Path $LlamaRepo)) {
    Write-Host "-> cloning upstream llama.cpp into $LlamaRepo"
    git clone https://github.com/ggerganov/llama.cpp $LlamaRepo
} else {
    Write-Host "-> updating existing llama.cpp in $LlamaRepo"
    git -C $LlamaRepo pull --ff-only
}

# --- configure & build ------------------------------------------------------

$cudaRootArg = Use-LatestCuda

New-Item $LlamaBuild -ItemType Directory -Force | Out-Null
Push-Location $LlamaBuild

Write-Host '-> generating upstream llama.cpp solution ...'
cmake .. -G Ninja `
    -DGGML_CUDA=ON -DGGML_CUBLAS=ON `
    -DCMAKE_BUILD_TYPE=Release `
    -DLLAMA_CURL=OFF `
    -DGGML_CUDA_FA_ALL_QUANTS=ON `
    "-DCMAKE_CUDA_ARCHITECTURES=$CudaArch" `
    $cudaRootArg

Write-Host '-> building upstream llama.cpp tools (Release) ...'
cmake --build . --config Release --target llama-server llama-batched-bench llama-cli llama-bench --parallel
Pop-Location

Write-Host ''
Write-Host ("Done!  llama.cpp binaries are in: ""{0}""." -f (Join-Path $LlamaBuild 'bin'))

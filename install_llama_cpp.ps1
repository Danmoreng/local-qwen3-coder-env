<#
    install_llama_cpp.ps1
    --------------------
    Installs all prerequisites and builds ggerganov/llama.cpp on Windows.

    • Works on Windows PowerShell 7
    • Uses the Ninja generator (fast, no VS-integration dependency)
    • Re-usable: just run the script; it installs only what is missing
    • Pass -CudaArch <SM> to target a different GPU
      (89 = Ada; GTX-1070 = 61, RTX-30-series = 86, etc.)
#>

[CmdletBinding()]
param(
    [switch]$SkipBuild
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$ScriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Definition

# Make PS5 iwr happy and TLS modern
try { [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 } catch {}

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

    $instRoot = & $vswhere -latest -products * `
        -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 `
        -property installationPath 2>$null

    if ([string]::IsNullOrWhiteSpace($instRoot)) { return $false }

    $vcvars = Join-Path $instRoot 'VC\Auxiliary\Build\vcvars64.bat'
    if (-not (Test-Path $vcvars)) { return $false }

    $cl = Get-ChildItem -Path (Join-Path $instRoot 'VC\Tools\MSVC') `
        -Recurse -Filter cl.exe -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $cl) { return $false }

    # Windows SDK tools (needed by CMake generator/linker steps)
    $sdkBin = 'C:\Program Files (x86)\Windows Kits\10\bin'
    $rc = Get-ChildItem $sdkBin -Recurse -Filter rc.exe -ErrorAction SilentlyContinue | Select-Object -First 1
    $mt = Get-ChildItem $sdkBin -Recurse -Filter mt.exe -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not ($rc -and $mt)) { return $false }

    return $true
}

# --- CUDA: generic discovery (12.4+ including 13.x) -------------------------

function Get-CudaInstalls {
    $root = 'C:\Program Files\NVIDIA GPU Computing Toolkit\CUDA'
    if (-not (Test-Path $root)) { return @() }
    $out = @()
    foreach ($d in Get-ChildItem $root -Directory) {
        $nvcc = Join-Path $d.FullName 'bin\nvcc.exe'
        if (($d.Name -match '^v(\d+)\.(\d+)$') -and (Test-Path $nvcc)) {
            $maj = [int]$Matches[1]; $min = [int]$Matches[2]
            $ver = [version]::new($maj, $min)
            $out += [pscustomobject]@{ Version=$ver; Major=$maj; Minor=$min; Path=$d.FullName }
        }
    }
    $out
}

function Test-CUDA {
    $min = [version]'12.4'
    $installs = Get-CudaInstalls
    if (-not $installs) { return $false }
    return ($installs | Where-Object { $_.Version -ge $min } | Select-Object -First 1) -ne $null
}

function Test-CUDAExact {
    param([Parameter(Mandatory=$true)][string]$MajorMinor) # e.g. '12.4'
    $target = [version]("$MajorMinor")
    $hit = Get-CudaInstalls | Where-Object {
        $_.Version.Major -eq $target.Major -and $_.Version.Minor -eq $target.Minor
    } | Select-Object -First 1
    return $null -ne $hit
}

function Install-CUDA124-FromNVIDIA {
    # Installs CUDA 12.4.1 silently (toolkit only; no driver, no GFE)
    $url = 'https://developer.download.nvidia.com/compute/cuda/12.4.1/local_installers/cuda_12.4.1_551.78_windows.exe'
    $exe = Join-Path $env:TEMP 'cuda_12.4.1_551.78_windows.exe'
    if (-not (Test-Path $exe)) {
        Write-Host "-> downloading CUDA 12.4.1 (local installer) ..."
        Invoke-WebRequest -Uri $url -OutFile $exe -UseBasicParsing
    }

    # Toolkit-only selection (no driver = no GeForce Experience)
    $toolkitPkgs = @(
        'nvcc_12.4',         # compiler
        'cudart_12.4',       # CUDA runtime
        'cublas_12.4',       # cuBLAS runtime
        'cublas_dev_12.4'    # cuBLAS headers/libs for build
    )

    $args = @('-s') + $toolkitPkgs + '-n'

    Write-Host "-> installing CUDA 12.4.1 (silent, toolkit only) ..."
    $p = Start-Process -FilePath $exe -ArgumentList $args -NoNewWindow -Wait -PassThru

    if ($p.ExitCode -ne 0 -and $p.ExitCode -ne 3010) {
        throw "CUDA 12.4.1 installer failed with exit code $($p.ExitCode)."
    }

    Refresh-Env

    $nvcc = 'C:\Program Files\NVIDIA GPU Computing Toolkit\CUDA\v12.4\bin\nvcc.exe'
    if (-not (Test-Path $nvcc)) {
        throw "CUDA 12.4.1 appears not to be installed correctly (missing $nvcc)."
    }
    Write-Host "[OK] CUDA 12.4.1 (nvcc present)"
}



function Wait-Until ($TestFn, [int]$TimeoutMin, [string]$What) {
    $sw = [Diagnostics.Stopwatch]::StartNew()
    $maxLen = 0
    while ($sw.Elapsed.TotalMinutes -lt $TimeoutMin) {
        if (& $TestFn) {
            $msg = "  $($What): done."
            $maxLen = [Math]::Max($maxLen, $msg.Length)
            Write-Host ("`r{0}{1}" -f $msg, ' ' * ($maxLen - $msg.Length)) -NoNewline
            Write-Host ""
            return
        }
        $msg = "  waiting for $($What) ... $($sw.Elapsed.ToString('mm\:ss'))"
        $maxLen = [Math]::Max($maxLen, $msg.Length)
        Write-Host ("`r{0}{1}" -f $msg, ' ' * ($maxLen - $msg.Length)) -NoNewline
        Start-Sleep -Milliseconds 250
    }
    Write-Host ""
    throw "$($What) did not finish in $TimeoutMin minutes."
}


function Refresh-Env {
    # Pull fresh Machine+User env into this process (esp. PATH, CUDA_PATH)
    $machine = [Environment]::GetEnvironmentVariables('Machine')
    $user    = [Environment]::GetEnvironmentVariables('User')

    foreach ($k in $machine.Keys) { Set-Item -Path "Env:$k" -Value $machine[$k] }
    foreach ($k in $user.Keys)    { Set-Item -Path "Env:$k" -Value $user[$k] }

    # Re-compose PATH explicitly (User appended to Machine by convention)
    $env:Path = "$([Environment]::GetEnvironmentVariable('Path','Machine'));$([Environment]::GetEnvironmentVariable('Path','User'))"
}

function Ensure-CommandAvailable([string]$Cmd, [int]$TimeoutMin = 5) {
    Refresh-Env
    Wait-Until { Test-Command $Cmd } $TimeoutMin "command '$Cmd' to appear on PATH"
}

function Add-ToMachinePath([string]$Dir) {
    if (-not (Test-Path $Dir)) { return }
    $regPath = 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Environment'
    $current = (Get-ItemProperty -Path $regPath -Name Path).Path
    $parts = $current -split ';' | Where-Object { $_ -ne '' }
    if ($parts -contains $Dir) { return }
    $new = ($parts + $Dir) -join ';'
    Set-ItemProperty -Path $regPath -Name Path -Value $new
}

# Run winget non-interactively, force community source, and redirect output to a log
function Install-Winget {
    param(
        [Parameter(Mandatory=$true)][string]$Id,
        [string]$InstallerArgs = '',   # for MSI and some EXEs; passed to --custom
        [string]$Version = ''
    )
    if (-not (Test-Command winget)) {
        throw "The 'winget' command is not available. Install the Microsoft 'App Installer' from the Store and try again."
    }
    Write-Host "-> installing $Id $($Version) ..."
    $argList = @(
        'install','--id',$Id,
        '--source','winget',              # avoid msstore agreements/UI
        '--silent','--disable-interactivity',
        '--accept-source-agreements','--accept-package-agreements'
    )
    if ($Version) {
        $argList += @('--version', $Version)
    }
    if ($InstallerArgs) {
        $argList += @('--custom', $InstallerArgs)
    }

    $log = Join-Path $env:TEMP ("winget_install_{0}.log" -f ($Id -replace '[^A-Za-z0-9]+','_'))

    & winget @argList *> $log
    $exitCode = $LASTEXITCODE

    # -1978335189: "no applicable upgrade found" (OK for up-to-date installs)
    # -1978335212: "no package found matching input criteria"
    if ($Version -and $exitCode -eq -1978335212) {
        throw "winget could not find $Id version $Version. See log: $log"
    }
    if ($exitCode -and $exitCode -notin @(-1978335189, -1978335212)) {
        throw "winget failed (exit $exitCode) while installing $Id. See log: $log"
    }

    Refresh-Env

}

function Install-VSTools {
    # Require winget (silent + no GUI)
    if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
        throw "The 'winget' command is not available. Install the Microsoft 'App Installer' from the Store and try again."
    }

    Write-Host "-> installing VS 2022 Build Tools (silent, via winget) ..."
    $installPath = 'C:\Program Files (x86)\Microsoft Visual Studio\2022\BuildTools'

    # Common component set
    $customCommon = @(
        '--add Microsoft.VisualStudio.Workload.VCTools',
        '--add Microsoft.VisualStudio.Component.VC.Tools.x86.x64',
        '--add Microsoft.VisualStudio.Component.VC.CoreBuildTools',
        '--add Microsoft.VisualStudio.Component.VC.Redist.14.Latest',
        '--includeRecommended',
        ('--installPath "{0}"' -f $installPath)
    ) -join ' '

    # Prefer Win11 SDK; fall back to Win10 SDK if not available on this machine/feed
    $customWin11 = "$customCommon --add Microsoft.VisualStudio.Component.Windows11SDK.22621"
    $customWin10 = "$customCommon --add Microsoft.VisualStudio.Component.Windows10SDK.19041"

    $logDir = Join-Path $env:TEMP "vsbuildtools_logs"
    New-Item -ItemType Directory -Path $logDir -Force | Out-Null
    $log = Join-Path $logDir "winget_vstools.log"

    # Kill any running VS installer UI just in case
    Get-Process -Name "vs_installer","VisualStudioInstaller" -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue

    # Helper to invoke winget silently with a given --custom payload
    function Invoke-VsInstall([string]$customArgs) {
        & winget install --id Microsoft.VisualStudio.2022.BuildTools `
            --source winget `
            --silent --disable-interactivity `
            --accept-source-agreements --accept-package-agreements `
            --custom $customArgs *> $log
        return $LASTEXITCODE
    }

    # Try Win11 SDK set first; if that fails, try Win10 SDK set
    $code = Invoke-VsInstall $customWin11
    if ($code -ne 0 -and $code -ne 3010) {
        Write-Host "  Win11 SDK component not available; retrying with Win10 SDK ..."
        $code = Invoke-VsInstall $customWin10
    }

    if ($code -ne 0 -and $code -ne 3010) {
        throw "VS Build Tools install failed (exit $code). See log: $log"
    }

    Refresh-Env
}

function Wait-VSToolsReady { Wait-Until { Test-VSTools } 20 'Visual Studio Build Tools' }
function Wait-CUDAReady    { Wait-Until { Test-CUDA    } 30 'CUDA Toolkit' }

# Bring MSVC variables (cl, link, lib paths, etc.) into this PowerShell session
function Import-VSEnv {
    $vswhere = Join-Path ${Env:ProgramFiles(x86)} 'Microsoft Visual Studio\Installer\vswhere.exe'
    $vsroot  = & $vswhere -latest -products * `
               -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 `
               -property installationPath 2>$null
    if (-not $vsroot) { throw "VS Build Tools not found." }

    $vcvars = Join-Path $vsroot 'VC\Auxiliary\Build\vcvars64.bat'
    if (-not (Test-Path $vcvars)) {
        throw "VS C++ Build Tools look registered at '$vsroot' but vcvars64.bat is missing.
Try re-installing the Build Tools with the Windows SDK component (see Install-VSTools)."
    }

    Write-Host "  importing MSVC environment from $vcvars"
    $envDump = cmd /s /c "`"$vcvars`" && set"
    foreach ($line in $envDump -split "`r?`n") {
        if ($line -match '^(.*?)=(.*)$') {
            $name,$value = $Matches[1],$Matches[2]
            Set-Item -Path "Env:$name" -Value $value
        }
    }
}

# Ninja: install portable to C:\Program Files\Ninja and add to PATH
function Install-NinjaPortable {
    if (Test-Command ninja) { return }
    Write-Host "-> installing Ninja (portable) ..."
    $url  = 'https://github.com/ninja-build/ninja/releases/latest/download/ninja-win.zip'
    $zip  = Join-Path $env:TEMP 'ninja-win.zip'
    $dest = 'C:\Program Files\Ninja'
    New-Item -ItemType Directory -Force -Path $dest | Out-Null
    Invoke-WebRequest -Uri $url -OutFile $zip -UseBasicParsing
    Expand-Archive -Path $zip -DestinationPath $dest -Force
    Remove-Item $zip -Force
    Add-ToMachinePath $dest
    Refresh-Env
    Ensure-CommandAvailable -Cmd 'ninja' -TimeoutMin 2
    Write-Host "[OK] Ninja"
}

# Select newest CUDA (>=12.4), export env, return CMake arg
function Use-LatestCuda {
    param([version]$Min=[version]'12.4',[version]$Prefer=$null)

    $installs = Get-CudaInstalls | Sort-Object Version -Descending

    if ($Prefer) {
        $pick = $installs | Where-Object {
            $_.Version.Major -eq $Prefer.Major -and $_.Version.Minor -eq $Prefer.Minor
        } | Select-Object -First 1
        if (-not $pick) {
            $have = ($installs.Version | ForEach-Object { $_.ToString(2) }) -join ', '
            throw "Requested CUDA $($Prefer.ToString(2)) not found. Installed versions: $have"
        }
    } else {
        $pick = $installs | Where-Object { $_.Version -ge $Min } | Select-Object -First 1
        if (-not $pick) { throw "No CUDA installation >= $Min found." }
    }

    $env:CUDA_PATH = $pick.Path
    $envName = "CUDA_PATH_V{0}_{1}" -f $pick.Major, $pick.Minor
    Set-Item -Path ("Env:$envName") -Value $pick.Path
    $cudaBin = Join-Path $pick.Path 'bin'
    if (-not ($env:Path -split ';' | Where-Object { $_ -ieq $cudaBin })) { $env:Path = "$cudaBin;$env:Path" }

    Write-Host "  Using CUDA toolkit $($pick.Version) at $($pick.Path)"
    "-DCUDAToolkit_ROOT=$($pick.Path)"
}

# Auto-detect CUDA architecture without nvidia-smi.exe
function Get-GpuCudaArch {
    # Try NVML (driver component) first
    $nvmlDirs = @(
        (Join-Path ${Env:ProgramFiles} 'NVIDIA Corporation\NVSMI'),
        "$env:SystemRoot\System32",
        "$env:SystemRoot\SysWOW64"
    ) | Where-Object { Test-Path (Join-Path $_ 'nvml.dll') }

    $cs = @"
using System;
using System.Runtime.InteropServices;
public static class NvmlHelper {
    [DllImport("kernel32.dll", SetLastError = true, CharSet=CharSet.Unicode)]
    public static extern bool SetDllDirectory(string lpPathName);

    [DllImport("nvml.dll", CallingConvention = CallingConvention.Cdecl)]
    private static extern int nvmlInit_v2();
    [DllImport("nvml.dll", CallingConvention = CallingConvention.Cdecl)]
    private static extern int nvmlShutdown();
    [DllImport("nvml.dll", CallingConvention = CallingConvention.Cdecl)]
    private static extern int nvmlDeviceGetCount_v2(out int count);
    [DllImport("nvml.dll", CallingConvention = CallingConvention.Cdecl)]
    private static extern int nvmlDeviceGetHandleByIndex_v2(uint index, out IntPtr device);
    [DllImport("nvml.dll", CallingConvention = CallingConvention.Cdecl)]
    private static extern int nvmlDeviceGetCudaComputeCapability(IntPtr device, out int major, out int minor);

    public static int GetMaxSm() {
        int rc = nvmlInit_v2();
        if (rc != 0) return -1;
        try {
            int count;
            rc = nvmlDeviceGetCount_v2(out count);
            if (rc != 0 || count < 1) return -1;
            int best = -1;
            for (uint i = 0; i < count; i++) {
                IntPtr dev;
                rc = nvmlDeviceGetHandleByIndex_v2(i, out dev);
                if (rc != 0) continue;
                int maj, min;
                rc = nvmlDeviceGetCudaComputeCapability(dev, out maj, out min);
                if (rc != 0) continue;
                int sm = maj * 10 + min;
                if (sm > best) best = sm;
            }
            return best;
        } finally {
            nvmlShutdown();
        }
    }
}
"@

    # Compile the helper just once
    try { Add-Type -TypeDefinition $cs -Language CSharp -ErrorAction Stop | Out-Null } catch { }

    foreach ($dir in $nvmlDirs) {
        try {
            [NvmlHelper]::SetDllDirectory($dir) | Out-Null
            $sm = [NvmlHelper]::GetMaxSm()
            if ($sm -ge 10) { return [int]$sm } # e.g., 86, 89, 75, ...
        } catch { }
    }

    # Fallback: heuristic via GPU name (WMI)
    try {
        $gpu = Get-CimInstance -ClassName Win32_VideoController -ErrorAction Stop |
                Where-Object { $_.AdapterCompatibility -like '*NVIDIA*' } |
                Select-Object -First 1
        if ($gpu) {
            $name = $gpu.Name
            $map = @(
                @{ Re = 'RTX\s*50|Blackwell|GB\d{3}'; SM = 100 } # best guess
                @{ Re = 'RTX\s*4\d|RTX\s*40|Ada|^AD';        SM = 89 }
                @{ Re = 'RTX\s*3\d|RTX\s*30|A[4-9]000|A30|A40|^GA|MX[34]50'; SM = 86 }
                @{ Re = 'RTX\s*2\d|RTX\s*20|Quadro\s*RTX|TITAN\s*RTX|T4|GTX\s*16|TU\d{2}'; SM = 75 }
                @{ Re = 'GTX\s*10|^GP|P10|P40|TITAN\s*Xp|TITAN\s*X\b';       SM = 61 }
                @{ Re = 'GTX\s*9|^GM|Tesla\s*M';                             SM = 52 }
                @{ Re = 'GTX\s*7|GTX\s*8|^GK|Tesla\s*K|K80|GT\s*7';          SM = 35 }
            )
            foreach ($m in $map) { if ($name -match $m.Re) { return [int]$m.SM } }
        }
    } catch { }

    return $null  # unknown
}


# ---------------------------------------------------------------------------
# Main routine
# ---------------------------------------------------------------------------

Assert-Admin

# --- Base prerequisites (excluding CUDA, which is handled dynamically) ---
$reqs = @(
    @{
        Name          = 'Git'
        Test          = { Test-Command git }
        Id            = 'Git.Git'
        Cmd           = 'git'
        InstallerArgs = '/VERYSILENT /NORESTART /SP- /NOCANCEL'  # Inno Setup
    },
    @{
        Name          = 'CMake'
        Test          = { Test-Command cmake }
        Id            = 'Kitware.CMake'
        Cmd           = 'cmake'
        InstallerArgs = 'ADD_CMAKE_TO_PATH=System ALLUSERS=1'     # MSI properties; 100% silent
    },
    @{
        Name     = 'VS Build Tools'
        Test     = { Test-VSTools }
        Id       = 'Microsoft.VisualStudio.2022.BuildTools'
        # Installed via dedicated function (quiet)
    },
    @{
        Name          = 'Ninja'
        Test          = { Test-Command ninja }
        Id            = 'Ninja-build.Ninja'
        Cmd           = 'ninja'
    }
)

# --- Detect GPU and select appropriate CUDA toolkit version ---
$DetectedSm = Get-GpuCudaArch

$cudaReq = @{
    Name    = 'CUDA Toolkit'
    Test    = { Test-CUDA }
    Id      = 'Nvidia.CUDA'
    Version = ''
}
$PreferCudaVersion = $null

if ($DetectedSm) {
    if ($DetectedSm -lt 70) {
        Write-Host "-> GPU detected: sm_$DetectedSm (pre-Turing) – selecting CUDA 12.4 for compatibility."
        $cudaReq.Name    = 'CUDA Toolkit 12.4'
        $cudaReq.Version = '12.4.1'
        $cudaReq.Test    = { Test-CUDAExact -MajorMinor '12.4' }
        $PreferCudaVersion = [version]'12.4'
    } else {
        Write-Host "-> GPU detected: sm_$DetectedSm – selecting latest CUDA."
    }
} else {
    Write-Host "-> GPU SM could not be determined pre-install – selecting latest CUDA."
}

$reqs += $cudaReq


# --- Install all prerequisites ---
foreach ($r in $reqs) {
    if (-not (& $r.Test)) {
        switch ($r.Name) {
            'VS Build Tools' {
                Install-VSTools
                Wait-VSToolsReady
            }
            'CUDA Toolkit 12.4' {
                try {
                    # Try winget first (if it has that exact minor)
                    Install-Winget -Id $r.Id -Version $r.Version
                } catch {
                    Write-Warning "winget path failed for CUDA 12.4.1: $($_.Exception.Message)"
                    Install-CUDA124-FromNVIDIA            # <<< direct NVIDIA fallback
                }
                # After either path, verify
                if (-not (Test-CUDAExact -MajorMinor '12.4')) {
                    $have = ((Get-CudaInstalls).Version | ForEach-Object { $_.ToString(2) }) -join ', '
                    throw "CUDA 12.4 did not get installed. Installed versions: $have"
                }
            }
            default {
                $installerArgs = $r.ContainsKey('InstallerArgs') ? $r['InstallerArgs'] : ''
                $version = $r.ContainsKey('Version')       ? $r['Version']       : ''
                Install-Winget -Id $r.Id -InstallerArgs $installerArgs -Version $version
                if ($r.Name -ne 'Ninja') {
                    if ($r.ContainsKey('Cmd') -and $r['Cmd']) {
                        Ensure-CommandAvailable -Cmd $r['Cmd'] -TimeoutMin 5
                    } else {
                        Refresh-Env
                    }
                }
            }
        }
        if (-not (& $r.Test)) {
            throw "$($r.Name) could not be installed automatically."
        }
    }
    Write-Host ("[OK] {0}" -f $r.Name)
}

# Ninja: install portable (more reliable than winget IDs/sources)
if (-not (Test-Command ninja)) {
    Install-NinjaPortable
} else {
    Write-Host "[OK] Ninja"
}

Import-VSEnv   # make cl.exe etc. available in this session

if ($SkipBuild) { Write-Host 'SkipBuild set – done.'; return }

if ($PreferCudaVersion) {
    $hasExact = Get-CudaInstalls | Where-Object {
        $_.Version.Major -eq $PreferCudaVersion.Major -and $_.Version.Minor -eq $PreferCudaVersion.Minor
    } | Select-Object -First 1
    if (-not $hasExact) {
        $have = ((Get-CudaInstalls).Version | ForEach-Object { $_.ToString(2) }) -join ', '
        throw "CUDA $($PreferCudaVersion.ToString(2)) did not get installed. Installed versions: $have"
    }
}

# --- Select CUDA toolkit and auto-detect architecture ---
$cudaRootArg = Use-LatestCuda -Prefer $PreferCudaVersion

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

git -C $LlamaRepo submodule update --init --recursive

# --- configure & build ------------------------------------------------------
# Prepare CMake CUDA architectures argument
$CudaArchArg = $DetectedSm ? "$DetectedSm" : 'native'
if ($DetectedSm) {
    Write-Host ("-> Using detected compute capability sm_{0}" -f $DetectedSm)
} else {
    Write-Host "-> Using CMAKE_CUDA_ARCHITECTURES=native (toolkit will detect during compile)."
}

New-Item $LlamaBuild -ItemType Directory -Force | Out-Null
Push-Location $LlamaBuild

Write-Host '-> generating upstream llama.cpp solution ...'
cmake .. -G Ninja `
    -DGGML_CUDA=ON -DGGML_CUBLAS=ON `
    -DCMAKE_BUILD_TYPE=Release `
    -DLLAMA_CURL=OFF `
    -DGGML_CUDA_FA_ALL_QUANTS=ON `
    "-DCMAKE_CUDA_ARCHITECTURES=$CudaArchArg" `
    $cudaRootArg

Write-Host '-> building upstream llama.cpp tools (Release) ...'
cmake --build . --config Release --target llama-server llama-batched-bench llama-cli llama-bench --parallel
Pop-Location

Write-Host ''
Write-Host ("Done!  llama.cpp binaries are in: ""{0}""." -f (Join-Path $LlamaBuild 'bin'))

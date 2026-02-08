# Local LLM Environment

This project provides PowerShell scripts to download, build, and run **Qwen3-Coder-Next** (80B) locally on Windows using `llama.cpp` and the `qwen-code` CLI tool.

The workflow is self-contained:
```
repo/                     # your checkout
├─ vendor/                # llama.cpp source cloned & built here
└─ models/                # downloaded GGUF model(s)
```

---

## Prerequisites

*   Windows 10/11 x64
*   PowerShell 7
*   NVIDIA GPU with CUDA 12.4+ (compute ≥ 7.0 recommended)
*   ~50 GB free disk space (source tree and model)

## Linux Support

This project now includes Bash scripts for **Linux** users (tested on Arch Linux).

### Prerequisites (Linux)
*   **Arch Linux** (recommended) or another distribution with access to `pacman` (scripts attempt to install dependencies via pacman).
*   **Git**, **CMake**, **Ninja**, **Node.js**, **npm**.
*   **CUDA Toolkit** (for CUDA build) or **Vulkan SDK** (for Vulkan build).
*   ~50 GB free disk space.

### 1. Installation (Linux)

Run the installation script to check for prerequisites, install missing Vulkan headers (on Arch), and build `llama.cpp` for both **CUDA** (if `nvcc` is found) and **Vulkan** (if `glslc`/`vulkan-headers` are found).

```bash
chmod +x install_llama_cpp.sh
./install_llama_cpp.sh
```

### 2. Execution (Linux)

You can run the server with either the CUDA backend or the Vulkan backend.

**Option A: CUDA (Recommended for NVIDIA GPUs)**
```bash
chmod +x run_llama_cpp_server.sh
./run_llama_cpp_server.sh
```

**Option B: Vulkan (Cross-vendor GPU support)**
```bash
chmod +x run_llama_cpp_server_vulkan.sh
./run_llama_cpp_server_vulkan.sh
```

**Step 3: Start the Agent (Linux)**
Open a **new** terminal and run:

```bash
chmod +x run_qwen_agent.sh
./run_qwen_agent.sh
```

These scripts will:
1.  Download the model if missing.
2.  Start `llama-server` on port 8080.
3.  Launch the `qwen-code` CLI tool pre-configured for the local server.

---

## Setup and Usage (Windows)

The process is split into three steps:
1.  **Installation**: Run the `install_llama_cpp.ps1` script once.
2.  **Server**: Run `run_llama_cpp_server.ps1` to start the model server.
3.  **Agent**: Run `run_qwen_agent.ps1` in a new window to start the coding assistant.

### 1. Installation

Run the `install_llama_cpp.ps1` script from an **elevated** PowerShell 7 prompt. This will:
*   Download and install prerequisites (Git, CMake, VS Build Tools, Ninja, CUDA, Node.js).
*   Clone and build `llama.cpp` from source.
*   Install the `qwen-code` CLI tool via npm.

```powershell
# Allow script execution for this session
Set-ExecutionPolicy Bypass -Scope Process

# Run the installer
./install_llama_cpp.ps1
```

### 2. Execution

**Step A: Start the Server**
Open a PowerShell terminal and run:

```powershell
./run_llama_cpp_server.ps1
```

This script will:
1.  Download the **`Qwen3-Coder-Next-UD-Q4_K_XL.gguf`** model (~45GB) if not already present.
2.  Start `llama-server` on **port 8080** with optimized settings.
3.  Wait for connections (keep this window open).

**Step B: Start the Agent**
Open a **new** PowerShell terminal and run:

```powershell
./run_qwen_agent.ps1
```

This will configure the environment and launch the `qwen-code` CLI, connected to your local server.

---

## Script Arguments

### `install_llama_cpp.ps1`
*   `-SkipBuild`: Skips cloning and building `llama.cpp`. Use this if you only need to re-verify prerequisites or reinstall the CLI.

### `run_llama_cpp_server.ps1`
*   (No arguments required.)

### `run_qwen_agent.ps1`
*   (No arguments required. Connects to `localhost:8080`.)

---

## Parameter Explanations

The `run` scripts use a set of optimized flags to launch the server for `Qwen3-Coder-Next`.

| Flag | Purpose | Value |
| --- | --- | --- |
| `--fit-ctx 32768` | Fits the context to 32k, managing VRAM usage efficiently. | `32768` |
| `--fit on` | Automatically offloads layers between GPU and CPU based on available VRAM. | `on` |
| `-ctk q8_0` | Quantizes the 'key' part of the KV cache to save memory. | `q8_0` |
| `-ctv q8_0` | Quantizes the 'value' part of the KV cache. | `q8_0` |
| `--temp 1.0` | Recommended temperature for this model. | `1.0` |
| `--min-p 0.01` | Minimum probability threshold. | `0.01` |

**Performance Note:** Recent updates to the Linux script (`run_llama_cpp_server.sh`) removed manual CPU offloading (`--n-cpu-moe`) and enabled memory mapping (removed `--no-mmap`), resulting in significant performance gains (e.g., ~34.6 t/s on RTX 5080 Mobile).

> **Note:** The `run_qwen_agent.ps1` script (Windows) or manual configuration (Linux) ensures the `qwen-code` CLI uses the following settings:
> * `OPENAI_API_KEY`: `sk-no-key-required`
> * `OPENAI_BASE_URL`: `http://localhost:8080/v1`
> * `OPENAI_MODEL`: `unsloth/Qwen3-Coder-Next`

## License

This project is licensed under the MIT License. See the [LICENSE](LICENSE) file for details.
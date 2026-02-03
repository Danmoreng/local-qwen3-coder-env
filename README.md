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

---

## Setup and Usage

The process is split into two steps:
1.  **Installation**: Run the `install_llama_cpp.ps1` script once.
2.  **Execution**: Run the `run_llama_cpp_server.ps1` script to start the server and the coding assistant.

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

Once the installation is complete, start the environment.

```powershell
./run_llama_cpp_server.ps1
```

This script will:
1.  Download the **`Qwen3-Coder-Next-UD-Q4_K_XL.gguf`** model (~45GB) if not already present.
2.  Start the `llama-server` on **port 8001** with optimized settings for the model.
3.  Launch the `qwen-code` CLI tool, pre-configured to talk to the local server.

---

## Script Arguments

### `install_llama_cpp.ps1`
*   `-SkipBuild`: Skips cloning and building `llama.cpp`. Use this if you only need to re-verify prerequisites or reinstall the CLI.

### `run_llama_cpp_server.ps1`
*   (No arguments required. Thread count is auto-detected.)

---

## Parameter Explanations

The `run` script uses a set of optimized flags to launch the server for `Qwen3-Coder-Next`.

| Flag | Purpose | Value |
| --- | --- | --- |
| `-c 32768` | Sets the context size to 32k for efficient local use. | `32768` |
| `--fit on` | Automatically offloads layers between GPU and CPU based on available VRAM. | `on` |
| `-ctk q8_0` | Quantizes the 'key' part of the KV cache to save memory. | `q8_0` |
| `-ctv q4_0` | Quantizes the 'value' part of the KV cache. | `q4_0` |
| `--temp 1.0` | Recommended temperature for this model. | `1.0` |
| `--min-p 0.01` | Minimum probability threshold. | `0.01` |

> **Note:** The script launches `llama-server` in the main window and opens a **new PowerShell 7 window** for the `qwen-code` CLI. This window is automatically configured with the following environment variables to route requests to the local server:
> * `OPENAI_API_KEY`: `sk-no-key-required`
> * `OPENAI_BASE_URL`: `http://localhost:8001/v1`
> * `OPENAI_MODEL`: `unsloth/Qwen3-Coder-Next`

## License

This project is licensed under the MIT License. See the [LICENSE](LICENSE) file for details.
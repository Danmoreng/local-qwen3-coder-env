# Local Qwen Environment

A streamlined environment for running **Qwen3-Coder** and **Qwen3.5** models locally with high performance. This project automates the setup, building, and serving of GGUF models using `llama.cpp`, providing a ready-to-use coding assistant.

## Features

- **Modular Model Selection**: Choose between various Qwen3-Coder and Qwen3.5 variants (27B, 35B MoE, 80B MoE, 122B MoE).
- **Vision Model Support**: Full multimodal support for the **Qwen 3.5** family. The environment automatically manages the necessary vision projectors (`mmproj`).
- **Auto-Detection**: Automatically detects any `.gguf` files placed in the `models/` directory.
- **Optimized Performance**: Pre-configured with flags for Flash Attention, KV-cache quantization, and MoE-specific optimizations.
- **Cross-Platform**: Full support for Linux (CUDA/Vulkan) and Windows (CUDA).

---

## Automatic Dependency Management

The installation scripts (`install_llama_cpp.sh` and `install_llama_cpp.ps1`) attempt to automatically install or verify the following dependencies:

### Linux (via `pacman` or system package manager)
- **Git**, **CMake**, **Ninja**
- **Node.js** (LTS) & **npm**
- **CUDA Toolkit** (12.4+ for NVIDIA GPUs)
- **Vulkan SDK** (`shaderc`, `vulkan-headers`, `vulkan-icd-loader`)
- **qwen-code** CLI (installed via npm)

### Windows (via `winget`)
- **Git**, **CMake**, **Ninja**
- **Node.js** (v24.13.0) & **npm**
- **Visual Studio 2022 Build Tools** (C++ Workload & Windows SDK)
- **CUDA Toolkit** (12.4.1 Toolkit only, avoids driver/GFE bloat)
- **qwen-code** CLI (installed via npm)

---

## Quick Start (Linux)

### 1. Installation
Build `llama.cpp` and install the required CLI tools:
```bash
chmod +x install_llama_cpp.sh
./install_llama_cpp.sh
```

### 2. Select Your Model
Choose from a list of optimized presets or use your own local files:
```bash
./select_model.sh
```

### 3. Start the Server
Run the server using your preferred backend:
```bash
# For NVIDIA GPUs (CUDA)
./run_llama_cpp_server.sh

# For Cross-vendor/AMD GPUs (Vulkan)
./run_llama_cpp_server_vulkan.sh
```

### 4. Launch the Coding Agent
In a new terminal, start the agent:
```bash
./run_qwen_agent.sh
```

---

## Quick Start (Windows)

### 1. Installation
Run from an elevated PowerShell 7 prompt:
```powershell
./install_llama_cpp.ps1
```

### 2. Execution
Start the server and agent in separate windows:
```powershell
./run_llama_cpp_server.ps1
./run_qwen_agent.ps1
```

---

## Custom Models & Vision

To use a custom model not listed in the presets:
1. Place your `.gguf` file in the `models/` directory.
2. Run `./select_model.sh`.
3. Your file will appear as a `Local: [filename]` option.
4. Select it and specify the desired context size when prompted.
5. If the model is a vision model, you will be prompted for an `mmproj` URL or local file path.

---

## Server Optimization Details

The environment uses several key optimizations to ensure smooth performance on consumer hardware. 

```bash
llama-server \
    --model <model_path> \
    [--mmproj <mmproj_path> --mmproj-offload] \
    --alias <alias_name> \
    --fit on \
    --fit-target <256 or 1536> \
    --jinja \
    --flash-attn on \
    --fit-ctx <context_size> \
    -b 1024 \
    -ub 256 \
    -ctk q8_0 \
    -ctv q8_0 \
    --temp 1.0 \
    --top-p 0.95 \
    --top-k 40 \
    --min-p 0.01
```

| Optimization | Purpose | Details |
| --- | --- | --- |
| **Flash Attention** | Faster inference | Enabled by default for all models. |
| **Vision GPU Offload** | Fast prompt processing | Projector is offloaded to GPU when available. |
| **KV Quantization** | VRAM Efficiency | `-ctk q8_0 -ctv q8_0` saves significant memory. |
| **Context Fitting** | Dynamic Offloading | Uses `--fit-target 256` for text models and `1536` for vision models. |
| **MoE Support** | Architecture Tuning | Specific handling for Mixture-of-Experts (Qwen MoE). |

## Project Structure

- `vendor/llama.cpp/`: The engine powering the local inference.
- `models/`: Storage for GGUF model files and vision projectors.
- `select_model.sh` / `select_model.ps1`: Interactive configuration tool.
- `run_qwen_agent.sh` / `run_qwen_agent.ps1`: Launches the `qwen-code` CLI.

## License

This project is licensed under the MIT License. See the [LICENSE](LICENSE) file for details.

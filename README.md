# Local Qwen Environment

A streamlined environment for running **Qwen3-Coder** and **Qwen3.5** models locally with high performance. This project automates the setup, building, and serving of GGUF models using `llama.cpp`, providing a ready-to-use coding assistant.

## Features

- **Modular Model Selection**: Choose between various Qwen3-Coder and Qwen3.5 variants (27B, 35B MoE, 80B MoE, 122B MoE).
- **Auto-Detection**: Automatically detects any `.gguf` files placed in the `models/` directory.
- **Optimized Performance**: Pre-configured with flags for Flash Attention, KV-cache quantization, and MoE-specific optimizations.
- **Cross-Platform**: Full support for Linux (CUDA/Vulkan) and Windows (CUDA).

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

## Custom Models

To use a custom model not listed in the presets:
1. Place your `.gguf` file in the `models/` directory.
2. Run `./select_model.sh`.
3. Your file will appear as a `Local: [filename]` option.
4. Select it and specify the desired context size when prompted.

---

## Server Optimization Details

The environment uses several key optimizations to ensure smooth performance on consumer hardware:

| Optimization | Purpose |
| --- | --- |
| **Flash Attention** | Significant speedup and memory reduction during inference. |
| **KV Quantization** | `-ctk q8_0 -ctv q8_0` saves VRAM by quantizing the KV cache. |
| **Context Fitting** | Dynamic context management to maximize efficiency without OOM. |
| **MoE Support** | Specific handling for the Mixture-of-Experts architecture in Qwen models. |

## Project Structure

- `vendor/llama.cpp/`: The engine powering the local inference.
- `models/`: Storage for GGUF model files.
- `select_model.sh`: Interactive configuration tool.
- `run_qwen_agent.sh`: Launches the `qwen-code` CLI pre-configured for the local environment.

## License

This project is licensed under the MIT License. See the [LICENSE](LICENSE) file for details.

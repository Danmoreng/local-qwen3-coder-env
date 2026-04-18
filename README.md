# Local Qwen Environment

A streamlined set of scripts for running **Qwen3-Coder**, **Qwen3.5**, and **Qwen3.6** models locally with tuned `llama.cpp` launcher defaults for coding workflows on Windows and Linux.

If you only want a focused `llama.cpp` source build/install flow (without Qwen-specific model/agent setup), use the simpler companion repo: [Danmoreng/llama.cpp-installer](https://github.com/Danmoreng/llama.cpp-installer).

## Features

- **Modular Model Selection**: Choose between various Qwen3-Coder, Qwen3.5, and Qwen3.6 variants, including the added **Qwen3.6 35B** preset models.
- **Vision Model Support**: Full multimodal support for the **Qwen 3.5 / 3.6** families. The environment automatically manages the necessary vision projectors (`mmproj`).
- **Auto-Detection**: Automatically detects any `.gguf` files placed in the `models/` directory.
- **Optimized Performance**: Pre-configured with flags for Flash Attention, KV-cache quantization, `--no-mmap`, `-ub 512`, and MoE-aware fitting defaults.
- **Cross-Platform**: Full support for Linux (CUDA/Vulkan) and Windows (CUDA).

---

## Automatic Dependency Management

The base installation scripts (`install_llama_cpp.sh` and `install_llama_cpp.ps1`) install or verify the dependencies needed to build and run `llama.cpp`.

### Linux (via `pacman` or system package manager)
- **Git**, **CMake**, **Ninja**
- **CUDA Toolkit** (12.4+ for NVIDIA GPUs)
- **Vulkan SDK** (`shaderc`, `vulkan-headers`, `vulkan-icd-loader`)

### Windows (via `winget`)
- **Git**, **CMake**, **Ninja**
- **Visual Studio 2022 Build Tools** (C++ Workload & Windows SDK)
- **CUDA Toolkit** (selected automatically based on GPU compatibility: pre-Turing pins to 12.4, Blackwell prefers 12.8+, otherwise latest compatible)

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

For text-only benchmarking or A/B testing on multimodal presets:
```bash
./run_llama_cpp_server.sh --text-only
./run_llama_cpp_server_vulkan.sh --text-only
```

---

## Quick Start (Windows)

### 1. Installation
Run from an elevated PowerShell 7 prompt:
```powershell
./install_llama_cpp.ps1
```

### 2. Execution
Start the server:
```powershell
./run_llama_cpp_server.ps1
```

For text-only benchmarking or A/B testing on multimodal presets, start the server with:
```powershell
./run_llama_cpp_server.ps1 -TextOnly
```

---

## Compatible Coding Agents

Any coding agent that supports an OpenAI-compatible API can be used with this setup.

Connection settings:
- Base URL: `http://localhost:8080/v1`
- API key: any placeholder value, for example `sk-no-key-required`
- Model: the selected model alias from `model_config.json`

Examples:
- **Qwen Code**: https://github.com/QwenLM/qwen-code
- **Pi Coding Agent**: https://github.com/badlogic/pi-mono

---

## Custom Models & Vision

To use a custom model not listed in the presets:
1. Place your `.gguf` file in the `models/` directory.
2. Run `./select_model.sh`.
3. Your file will appear as a `Local: [filename]` option.
4. Select it and specify the desired context size when prompted.
5. If the model is a vision model, you will be prompted for an `mmproj` URL or local file path.

---

## Runtime Defaults

The launchers default to a single server slot with `-np 1`, which reduces recurrent-state overhead for single-user local coding setups. Text loads use `--fit-target 256`; vision loads switch to `--fit-target 1536` when an `mmproj` is active. The `--fit-ctx` value is the minimum context floor that `--fit` is allowed to keep, not a hard fixed runtime context.

---

## Sampling Parameters & Modes

The environment automatically adjusts sampling parameters based on the selected model to ensure optimal results for coding and reasoning tasks.

### Automated Defaults (Precise Coding)
When you start the server, it detects the model type and applies these settings:

| Model Series | Mode | Temp | Top-P | Top-K | Min-P |
| :--- | :--- | :--- | :--- | :--- | :--- |
| **Qwen 3 Coder** | **Standard Coding** | 1.0 | 0.95 | 40 | 0.01 |
| **Qwen 3.5 / 3.6** | **Thinking: Precise Coding** | 0.6 | 0.95 | 20 | 0.0 |

### Alternative Qwen 3.5 / 3.6 Recommendations
For non-coding tasks with the **Qwen 3.5 / 3.6** series, you may manually adjust parameters in the server or UI:

- **Thinking Mode (General Reasoning):**
  - `temp=1.0`, `top_p=0.95`, `top_k=20`, `presence_penalty=1.5`
- **Instruct Mode (Standard Chat):**
  - `temp=0.7`, `top_p=0.8`, `top_k=20`, `presence_penalty=1.5`

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
    --no-mmap \
    -np 1 \
    --fit-ctx <context_size> \
    -b 1024 \
    -ub 512 \
    -ctk q8_0 \
    -ctv q8_0 \
    --temp <0.6 or 1.0> \
    --top-p 0.95 \
    --top-k <20 or 40> \
    --min-p <0.0 or 0.01>
```

| Optimization | Purpose | Details |
| --- | --- | --- |
| **Flash Attention** | Faster inference | Enabled by default across the launchers. |
| **Vision GPU Offload** | Faster multimodal prompt processing | Offloads the vision projector to the GPU for multimodal loads. |
| **KV Quantization** | Lower memory use | `-ctk q8_0 -ctv q8_0` reduces KV cache memory usage. |
| **Single Server Slot** | Lower recurrent-state overhead | `-np 1` configures the server for a single local user session. |
| **No `mmap`** | More stable host/GPU balance | Enabled in the Windows launcher for large text-model loads. |
| **Larger UBatch** | Higher prompt throughput | `-ub 512` increases prompt-processing throughput in the Windows launcher. |
| **Context Fitting** | Dynamic memory fitting | `--fit-target` reserves per-device headroom, and `--fit-ctx` defines the minimum context floor used by `--fit`. |
| **Dynamic Sampling** | Model-specific defaults | Applies coding-oriented defaults for Qwen 3 Coder and precise-coding defaults for Qwen 3.5 / 3.6. |
| **MoE Support** | Better large-model handling | Uses launcher defaults that work well with Qwen Mixture-of-Experts models. |

## Project Structure

- `vendor/llama.cpp/`: The engine powering the local inference.
- `models/`: Storage for GGUF model files and vision projectors.
- `select_model.sh` / `select_model.ps1`: Interactive configuration tool.

## License

This project is licensed under the MIT License. See the [LICENSE](LICENSE) file for details.

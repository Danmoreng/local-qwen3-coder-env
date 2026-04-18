# Local Qwen Environment

A streamlined environment for running **Qwen3-Coder**, **Qwen3.5**, and **Qwen3.6** models locally with high performance. This project automates the setup, building, and serving of GGUF models using `llama.cpp`, providing a ready-to-use coding assistant.

If you only want a focused `llama.cpp` source build/install flow (without Qwen-specific model/agent setup), use the simpler companion repo: [Danmoreng/llama.cpp-installer](https://github.com/Danmoreng/llama.cpp-installer).

## Features

- **Modular Model Selection**: Choose between various Qwen3-Coder, Qwen3.5, and Qwen3.6 variants, including the added **Qwen3.6 35B** preset models.
- **Vision Model Support**: Full multimodal support for the **Qwen 3.5 / 3.6** families. The environment automatically manages the necessary vision projectors (`mmproj`).
- **Auto-Detection**: Automatically detects any `.gguf` files placed in the `models/` directory.
- **Optimized Performance**: Pre-configured with flags for Flash Attention, KV-cache quantization, `--no-mmap`, `-ub 512`, and MoE-aware fitting defaults.
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
- **CUDA Toolkit** (selected automatically based on GPU compatibility: pre-Turing pins to 12.4, Blackwell prefers 12.8+, otherwise latest compatible)
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

For text-only benchmarking or A/B testing on multimodal presets, start the server with:
```powershell
./run_llama_cpp_server.ps1 -TextOnly
```

### Minimal Product Request Frontend
This repo also includes a small local web frontend for drafting structured product requests with the selected `llama-server` model.

1. Start `llama-server` first:
```powershell
./run_llama_cpp_server.ps1
```
2. In another terminal, start the web app:
```powershell
npm run start:web
```
3. Open `http://127.0.0.1:4173`

The UI provides:
- a chat panel where the model asks follow-up questions
- an editable request canvas that the model rewrites every turn
- direct local proxying to `http://127.0.0.1:8080/v1/chat/completions`

### Benchmark Speculative Editing
Run a benchmark that starts `llama-server`, measures a code-generation pass plus two edit passes, and compares baseline output speed against self-speculative variants:
```powershell
./benchmark_speculative_editing.ps1
```

Default variants:
- `baseline`
- `ngram-mod` using `--spec-ngram-size-n 18 --draft-min 6 --draft-max 48`
- `ngram-map-k4v` using `--spec-ngram-size-n 7 --spec-ngram-size-m 4 --spec-ngram-min-hits 1 --draft-max 16`

The benchmark writes per-stage JSON/CSV artifacts under `benchmark-results/`.

Important:
- By default the benchmark ignores `mmproj` even if your selected preset is multimodal. `llama.cpp` disables speculative decoding for multimodal server loads, so text-only mode is required for meaningful speculative results.
- The workflow is intentionally edit-heavy: it generates a complete algorithm, then re-sends the full file for small edits so repeated code patterns can be exploited by n-gram speculative decoding.

---

## Custom Models & Vision

To use a custom model not listed in the presets:
1. Place your `.gguf` file in the `models/` directory.
2. Run `./select_model.sh`.
3. Your file will appear as a `Local: [filename]` option.
4. Select it and specify the desired context size when prompted.
5. If the model is a vision model, you will be prompted for an `mmproj` URL or local file path.

---

## Qwen3.6 35B Support

The repo now includes preset model support and tested server defaults for **Qwen3.6 35B**.

The launchers now default to a single server slot with `-np 1`, which reduces recurrent-state overhead for single-user local coding setups. For the Windows server path, the optimized shared defaults also use `--fit on`, `--fit-target 256` for text models, `--no-mmap`, and `-ub 512`. Vision models still switch to `--fit-target 1536` when an `mmproj` is active.

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
| **Flash Attention** | Faster inference | Enabled by default for all models. |
| **Vision GPU Offload** | Fast prompt processing | Projector is offloaded to GPU when available. |
| **KV Quantization** | VRAM Efficiency | `-ctk q8_0 -ctv q8_0` saves significant memory. |
| **Single Server Slot** | Lower recurrent-state overhead | `-np 1` is now the default for local single-user runs, avoiding the server auto-default of 4 slots. |
| **No `mmap`** | More stable host/GPU balance | `--no-mmap` is enabled in the Windows launcher to improve performance for large Qwen 3.6 35B text presets. |
| **Larger UBatch** | Faster throughput | `-ub 512` is now the default in the Windows launcher. |
| **Context Fitting** | Dynamic Offloading | Uses `--fit-target 256` for text models and `1536` for vision models. |
| **Dynamic Sampling** | Task Optimization | Automatically switches between Coder-Next and Qwen 3.5 / 3.6 thinking parameters. |
| **MoE Support** | Architecture Tuning | Specific handling for Mixture-of-Experts (Qwen MoE). |

## Project Structure

- `vendor/llama.cpp/`: The engine powering the local inference.
- `models/`: Storage for GGUF model files and vision projectors.
- `select_model.sh` / `select_model.ps1`: Interactive configuration tool.
- `run_qwen_agent.sh` / `run_qwen_agent.ps1`: Launches the `qwen-code` CLI.

## License

This project is licensed under the MIT License. See the [LICENSE](LICENSE) file for details.

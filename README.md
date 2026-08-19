# Local Qwen Environment

A streamlined environment for running **Qwen3.8-27B** locally with tuned `llama.cpp` launcher defaults for coding workflows on Windows and Linux. Existing Qwen3-Coder and Qwen3.5 presets remain available through the general model selector.

If you only want a focused `llama.cpp` source build/install flow (without Qwen-specific model/agent setup), use the simpler companion repo: [Danmoreng/llama.cpp-installer](https://github.com/Danmoreng/llama.cpp-installer).

## Features

- **Modular Model Selection**: Qwen3.8-27B is the recommended default, with additional Qwen3-Coder and Qwen3.5 presets available.
- **Qwen3.8 27B Launcher**: Dedicated Linux and Windows launchers tuned for `Qwen3.8-27B-UD-IQ3_XXS` on 16GB-class GPUs.
- **Pi Coding Agent Guide**: A focused Windows workflow for using Qwen3.8-27B as a local coding agent through the Hugging Face `pi-llama` extension.
- **Official llama.app Alternative**: Documents the new unified `llama` application as the simplest prebuilt installation path while retaining this repo's tuned source-build launchers.
- **Integrated MTP Drafting**: Uses Qwen3.8's built-in MTP layer through `--spec-default --spec-type draft-mtp`; no separate draft model is required.
- **Central Model Cache**: Hugging Face presets use the standard shared Hugging Face cache instead of duplicating files inside the repository.
- **Vision Model Support**: Multimodal support for the Qwen3.8 and Qwen3.5 families, including automatic cached `mmproj` downloads.
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

The recommended 16GB Qwen3.8 launcher is:
```bash
./run_qwen3_8_optimized.sh
```

Add `--vision` for multimodal input or `--local-model` to use the legacy `models/` directory instead of the shared cache.

To pre-download the recommended GGUF with Hugging Face's resumable Xet downloader:
```bash
hf download unsloth/Qwen3.8-27B-GGUF Qwen3.8-27B-UD-IQ3_XXS.gguf
```

If `hf` is installed, the launchers run this step automatically and pass the resolved cache file to `llama-server`. Without it, they fall back to `llama.cpp`'s built-in downloader. Install the official CLI with:
```bash
curl -LsSf https://hf.co/cli/install.sh | bash
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

For the recommended 16GB Qwen3.8-27B profile:
```powershell
.\run_qwen3_8_optimized.ps1
```

Use `-Vision` for multimodal input or `-LocalModel` to use the legacy `models/` directory.

The model can also be downloaded into the shared cache before starting the server:
```powershell
hf download unsloth/Qwen3.8-27B-GGUF Qwen3.8-27B-UD-IQ3_XXS.gguf
```

The PowerShell launchers use `hf download` automatically when the CLI is available, including for the optional vision projector. Install the official CLI once if `hf --help` is not recognized:
```powershell
powershell -ExecutionPolicy ByPass -c "irm https://hf.co/cli/install.ps1 | iex"
```

### Official `llama` app alternative

The official [llama.app](https://llama.app/) installer provides a prebuilt, unified `llama` command. Its `llama serve` subcommand is the packaged equivalent of `llama-server` and is a convenient alternative when you do not need a local source build:

```powershell
irm https://llama.app/install.ps1 | iex
llama serve
```

Running `llama serve` without a model starts the model router and discovers GGUFs in the llama.cpp cache. The dedicated launcher in this repository remains the recommended route for Qwen3.8-27B on a 16GB NVIDIA GPU because it applies the tested quantization, context fitting, KV-cache, sampling, and MTP settings explicitly.

For the complete setup, including an equivalent tuned `llama serve` command and Pi integration, see [Qwen3.8-27B with llama.cpp and Pi on a 16GB NVIDIA GPU](docs/qwen3.8-27b-pi-windows.md).

---

## Compatible Coding Agents

Any coding agent that supports an OpenAI-compatible API can be used with this setup.

Connection settings:
- Base URL: `http://localhost:8080/v1`
- API key: any placeholder value, for example `sk-no-key-required`
- Model: the selected model alias from `model_config.json`

Examples:
- **Pi Coding Agent**: Use the [`pi-llama`](https://github.com/huggingface/pi-llama) extension for automatic discovery of this repo's running single-model server. This repository's `.pi/settings.json` selects the local Qwen3.8 model with medium reasoning by default. A user-level `~/.pi/agent/models.json` override raises Pi's per-response output limit from the extension's 16K default to 32K. Follow the [16GB Windows guide](docs/qwen3.8-27b-pi-windows.md).
- **Qwen Code**: https://github.com/QwenLM/qwen-code

Current Pi versions also include direct management for llama.cpp's multi-model router through `/login llama.cpp` and `/llama`. The `pi-llama` extension is the more direct match for this repo's tuned single-model launcher; the built-in integration is useful when `llama serve` is running without `--model`, `-m`, or `-hf`.

---

## Custom Models & Vision

### Model storage

Known Hugging Face presets are downloaded by `llama.cpp` into the shared Hugging Face cache. The cache location follows this precedence:

1. `LLAMA_CACHE`
2. `HF_HUB_CACHE` or `HUGGINGFACE_HUB_CACHE`
3. `$HF_HOME/hub`
4. `$XDG_CACHE_HOME/huggingface/hub`
5. `~/.cache/huggingface/hub`

This allows `llama.cpp`, Hugging Face tools, and other local projects to reuse the same files. To force a known preset to use `models/`, add `--local-model` on Linux or `-LocalModel` on Windows.

To use a custom model not listed in the presets:
1. Place your `.gguf` file in the `models/` directory.
2. Run `./select_model.sh`.
3. Your file will appear as a `Local: [filename]` option.
4. Select it and specify the desired context size when prompted.
5. If the model is a vision model, you will be prompted for an `mmproj` URL or local file path.

---

## Runtime Defaults

The launchers default to a single server slot with `-np 1`, which reduces recurrent-state overhead for single-user local coding setups. The dedicated Qwen3.8 text launchers use a fixed 96K context with `--fit off`, keeping the entire tested model placement on the GPU. Add `--safe-context` on Linux or `-SafeContext` on Windows for the previous 80K profile. Vision mode uses the 80K context floor with dynamic fitting and `--fit-target 1536`, because the BF16 projector requires additional VRAM.

For Qwen3.8, the dedicated launchers default to `medium` reasoning, cap each thinking phase at 8,192 tokens, inject an action-oriented cutoff message when that budget is reached, and preserve reasoning traces across the conversation history. Individual API requests may still disable thinking when the client supports the model's chat-template control.

### Recommended Qwen3.8-27B profile

The dedicated `run_qwen3_8_optimized` launchers use the following profile on both Linux and Windows:

| Setting | Value |
| --- | --- |
| Model | [`unsloth/Qwen3.8-27B-GGUF`](https://huggingface.co/unsloth/Qwen3.8-27B-GGUF) |
| Hub revision | `27af057ecb382ddfea5d12837360a8980560e3ed` (pinned Dynamic 3.0 refresh) |
| Quantization | `Qwen3.8-27B-UD-IQ3_XXS.gguf` (Unsloth Dynamic 3.0, about 10.9 GB) |
| Context | fixed `98304` tokens via `-c 98304` |
| GPU memory fitting | `--fit off` for text; vision uses `--fit on` with a `1536` MiB target |
| Prompt batches | `-b 1024 -ub 512` |
| KV cache | `-ctk q8_0 -ctv q8_0` |
| Parallel slots | `-np 1` |
| Attention | `--flash-attn on` |
| Sampling | temperature `1.0`, top-p `0.95`, top-k `20`, min-p `0.0` |
| Penalties | presence `0.0`, repetition `1.0` |
| Thinking | `medium` reasoning effort with an 8K hard budget, an action-oriented cutoff message, and history preserved |
| Speculative decoding | integrated MTP via `--spec-default --spec-type draft-mtp` |
| API endpoint | `http://localhost:8080/v1` |

The 96K text profile is the highest practical agent profile found for the current Dynamic 3.0 GGUF on the tested 16GB RTX 5080 Laptop GPU, not the model's architectural maximum. It completed a 4,153-token prompt plus MTP generation at about 76 tokens/s and left 358 MiB of total GPU memory free after CUDA graph allocation. A 100K profile also completed the test but left only 182 MiB free; 104K fell to 36 MiB, and 108K crashed on the first request with a CUDA out-of-memory error. Keep other GPU-heavy applications closed at 96K, or use the 80K safe-context option for substantially more headroom. Vision is opt-in and retains the 80K dynamic-fitting profile because its BF16 projector requires additional VRAM.

---

## Sampling Parameters & Modes

The environment automatically adjusts sampling parameters based on the selected model to ensure optimal results for coding and reasoning tasks.

### Automated Defaults (Precise Coding)
When you start the server, it detects the model type and applies these settings:

| Model Series | Mode | Temp | Top-P | Top-K | Min-P |
| :--- | :--- | :--- | :--- | :--- | :--- |
| **Qwen 3 Coder** | **Standard Coding** | 1.0 | 0.95 | 40 | 0.01 |
| **Qwen 3.5** | **Thinking: Precise Coding** | 0.6 | 0.95 | 20 | 0.0 |
| **Qwen 3.8** | **Thinking** | 1.0 | 0.95 | 20 | 0.0 |

### Alternative Qwen3.5 Recommendations
For non-coding tasks with the **Qwen3.5** series, you may manually adjust parameters in the server or UI:

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
    --no-mmproj \
    --alias <alias_name> \
    --fit off \
    -c 98304 \
    --flash-attn on \
    -np 1 \
    -b 1024 \
    -ub 512 \
    -ctk q8_0 \
    -ctv q8_0 \
    --temp 1.0 \
    --top-p 0.95 \
    --top-k 20 \
    --min-p 0.0 \
    --reasoning-effort medium \
    --reasoning-budget 8192 \
    --reasoning-budget-message "... I have been thinking for too long -- let me gather more information about the task and take the next concrete action." \
    --reasoning-preserve \
    --spec-default \
    --spec-type draft-mtp
```

| Optimization | Purpose | Details |
| --- | --- | --- |
| **Flash Attention** | Faster inference | Enabled by default across the launchers. |
| **Vision GPU Offload** | Faster multimodal prompt processing | Offloads the vision projector to the GPU for multimodal loads. |
| **KV Quantization** | Lower memory use | `-ctk q8_0 -ctv q8_0` reduces KV cache memory usage. |
| **Single Server Slot** | Lower recurrent-state overhead | `-np 1` configures the server for a single local user session. |
| **No `mmap`** | More stable host/GPU balance | Enabled in the Windows launcher for large text-model loads. |
| **Larger UBatch** | Higher prompt throughput | `-ub 512` increases prompt-processing throughput in the Windows launcher. |
| **Fixed Text Placement** | Predictable full-GPU performance | The dedicated Qwen3.8 text profile uses `--fit off -c 98304`; `--safe-context`/`-SafeContext` selects 80K, while vision retains dynamic fitting. |
| **MTP Drafting** | Faster Qwen3.8 generation | Uses the model's integrated next-token prediction layer and reports draft acceptance in the server timing log. |
| **Dynamic Sampling** | Model-specific defaults | Applies the recommended thinking-mode defaults for Qwen3.8 and compatible settings for the remaining presets. |
| **MoE Support** | Better large-model handling | Uses launcher defaults that work well with Qwen Mixture-of-Experts models. |

## Project Structure

- `vendor/llama.cpp/`: The engine powering the local inference.
- Shared Hugging Face cache: primary storage for known remote presets.
- `models/`: Optional fallback storage for local GGUF files and vision projectors.
- `select_model.sh` / `select_model.ps1`: Interactive configuration tool.

## Acknowledgments

- **Qwen**: https://github.com/QwenLM
- **llama.cpp**: https://github.com/ggml-org/llama.cpp

## License

This project is licensed under the MIT License. See the [LICENSE](LICENSE) file for details.

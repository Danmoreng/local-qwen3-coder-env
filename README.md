# Local Qwen Environment

A streamlined set of scripts for running **Qwen3-Coder**, **Qwen3.5**, **Qwen3.6**, and **Qwen3.8** models locally with tuned `llama.cpp` launcher defaults for coding workflows on Windows and Linux.

If you only want a focused `llama.cpp` source build/install flow (without Qwen-specific model/agent setup), use the simpler companion repo: [Danmoreng/llama.cpp-installer](https://github.com/Danmoreng/llama.cpp-installer).

## Features

- **Modular Model Selection**: Choose between Qwen3-Coder, Qwen3.5, Qwen3.6, and Qwen3.8 variants.
- **Qwen3.8 27B Launcher**: Dedicated Linux and Windows launchers tuned for `Qwen3.8-27B-UD-IQ3_XXS` on 16GB-class GPUs.
- **Integrated MTP Drafting**: Uses Qwen3.8's built-in MTP layer through `--spec-type draft-mtp`; no separate draft model is required.
- **Central Model Cache**: Hugging Face presets use the standard shared Hugging Face cache instead of duplicating files inside the repository.
- **Vision Model Support**: Full multimodal support for the Qwen 3.5, 3.6, and 3.8 families, including automatic cached `mmproj` downloads.
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

Add `--vision` for multimodal input or `--local-model` to use the legacy `models/` directory instead of the shared cache. The older optimized Qwen3.6 Linux launcher accepts the same flags.

To pre-download the recommended GGUF with Hugging Face's resumable Xet downloader:
```bash
hf download unsloth/Qwen3.8-27B-GGUF Qwen3.8-27B-UD-IQ3_XXS.gguf
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

Use `-Vision` for multimodal input or `-LocalModel` to use the legacy `models/` directory. The optimized Qwen3.6 Windows launcher accepts these flags as well.

The model can also be downloaded into the shared cache before starting the server:
```powershell
hf download unsloth/Qwen3.8-27B-GGUF Qwen3.8-27B-UD-IQ3_XXS.gguf
```

For the dedicated 16GB GPU Qwen3.6-27B launcher:
```powershell
./run_qwen3_6_27b_optimized.ps1
```

This script intentionally fixes the model and runtime profile for 16GB NVIDIA GPUs: `Qwen3.6-27B-UD-IQ3_XXS`, Q8 K/V cache, Flash Attention, one server slot, `ngram-map-k` speculative decoding, a 64K context floor, and `preserve_thinking=true` for stronger coding/reasoning continuity. `llama.cpp --fit` can raise the actual context above 64K when VRAM allows.

To enable vision mode in the specialized launcher:
```powershell
./run_qwen3_6_27b_optimized.ps1 -Vision
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

The launchers default to a single server slot with `-np 1`, which reduces recurrent-state overhead for single-user local coding setups. Text loads use `--fit-target 256`; vision loads switch to `--fit-target 1536` when an `mmproj` is active. The `--fit-ctx` value is the minimum context floor that `--fit` is allowed to keep, not a hard fixed runtime context.

For `Qwen3.6` presets, the launchers set `preserve_thinking=true`. Qwen3.8 additionally enables thinking and sets `reasoning_effort=xhigh` through the chat-template arguments because current `llama.cpp` does not forward all top-level OpenAI `reasoning_effort` values to model templates. Both families also use `--reasoning-preserve` so reasoning traces remain available across the full conversation history.

The dedicated Windows `Qwen3.6-27B` launcher (`run_qwen3_6_27b_optimized.ps1`) uses `ngram-map-k` speculative decoding by default.

### Recommended Qwen3.8-27B profile

The dedicated `run_qwen3_8_optimized` launchers use the following profile on both Linux and Windows:

| Setting | Value |
| --- | --- |
| Model | [`unsloth/Qwen3.8-27B-GGUF`](https://huggingface.co/unsloth/Qwen3.8-27B-GGUF) |
| Quantization | `Qwen3.8-27B-UD-IQ3_XXS.gguf` (about 11.9 GB) |
| Context floor | `65536` tokens via `--fit-ctx 65536` |
| GPU memory fitting | `--fit on`, text headroom `256` MiB, vision headroom `1536` MiB |
| Prompt batches | `-b 1024 -ub 512` |
| KV cache | `-ctk q8_0 -ctv q8_0` |
| Parallel slots | `-np 1` |
| Attention | `--flash-attn on` |
| Sampling | temperature `1.0`, top-p `0.95`, top-k `20`, min-p `0.0` |
| Penalties | presence `0.0`, repetition `1.0` |
| Thinking | enabled, preserved, `reasoning_effort=xhigh` |
| Speculative decoding | integrated MTP via `--spec-type draft-mtp` |
| API endpoint | `http://localhost:8080/v1` |

The 64K value is a practical minimum context target for a 16GB GPU, not the model's architectural maximum. `llama.cpp --fit` may adjust the effective GPU placement and context according to available memory. Vision is opt-in on the dedicated launcher because its BF16 projector requires additional VRAM.

---

## Sampling Parameters & Modes

The environment automatically adjusts sampling parameters based on the selected model to ensure optimal results for coding and reasoning tasks.

### Automated Defaults (Precise Coding)
When you start the server, it detects the model type and applies these settings:

| Model Series | Mode | Temp | Top-P | Top-K | Min-P |
| :--- | :--- | :--- | :--- | :--- | :--- |
| **Qwen 3 Coder** | **Standard Coding** | 1.0 | 0.95 | 40 | 0.01 |
| **Qwen 3.5 / 3.6** | **Thinking: Precise Coding** | 0.6 | 0.95 | 20 | 0.0 |
| **Qwen 3.8** | **Thinking** | 1.0 | 0.95 | 20 | 0.0 |

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
    [LLAMA_CHAT_TEMPLATE_KWARGS='{"preserve_thinking":true}' for Qwen3.6] \
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
    --min-p <0.0 or 0.01> \
    [--reasoning-preserve] \
    [--spec-type draft-mtp]
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
| **MTP Drafting** | Faster Qwen3.8 generation | Uses the model's integrated next-token prediction layer and reports draft acceptance in the server timing log. |
| **Dynamic Sampling** | Model-specific defaults | Applies coding-oriented defaults for Qwen 3 Coder and precise-coding defaults for Qwen 3.5 / 3.6. |
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

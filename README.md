# Local LLM Environment

This project provides PowerShell scripts to download, build, and run large language models locally on Windows using either the standard **`llama.cpp`** or the performance-oriented **`ik_llama.cpp`** fork.

You can choose the engine that best suits your needs:
*   **`llama.cpp`**: The official, stable, and widely used version.
*   **`ik_llama.cpp`**: A fork with advanced features for fine-tuning performance, especially for machines with limited VRAM.

The workflow is self-contained:
```
repo/                     # your checkout
├─ vendor/                # llama.cpp and/or ik_llama.cpp source cloned & built here
└─ models/                # downloaded GGUF model(s)
```

---

## Prerequisites

*   Windows 10/11 x64
*   PowerShell 7
*   NVIDIA GPU with CUDA 12.4+ (compute ≥ 7.0 highly recommended)
*   ~40 GB free disk space (source tree and model)

---

## Setup and Usage

The process is split into two steps:
1.  **Installation**: Run the appropriate `install_*.ps1` script once.
2.  **Execution**: Run the corresponding `run_*_server.ps1` script to start the model server.

### 1. Choose Your Engine

First, decide whether you want to use the standard `llama.cpp` or the `ik_llama.cpp` fork.

#### Option A: Standard `llama.cpp` (Recommended for most users)

This is the official and most stable version.

**Installation:**
Run the `install_llama_cpp.ps1` script from an **elevated** PowerShell 7 prompt. This will download and build the `llama.cpp` engine.

```powershell
# Allow script execution for this session
Set-ExecutionPolicy Bypass -Scope Process

# Run the installer
./install_llama_cpp.ps1
```

**Execution:**
Once the installation is complete, start the server.

```powershell
./run_llama_cpp_server.ps1
```

#### Option B: Performance `ik_llama.cpp` (Advanced)

This version offers special flags for optimizing performance, like quantizing the KV-cache or splitting model layers between GPU and CPU.

**Installation:**
Run the `install_ik_llama.ps1` script from an **elevated** PowerShell prompt.

```powershell
# Allow script execution for this session
Set-ExecutionPolicy Bypass -Scope Process

# Run the installer (adjust CudaArch for your GPU)
./install_ik_llama.ps1 -CudaArch 86
```

**Execution:**
Once the installation is complete, start the server.

```powershell
./run_ik_llama_server.ps1
```

---

## Server and Model

The `run` scripts will download a ~17 GB GGUF model into the `models/` directory and launch the `llama-server.exe` with a tuned set of runtime flags.

*   `run_llama_cpp_server.ps1` uses the **`Qwen3-Coder-30B-A3B-Instruct-1M-IQ4_NL.gguf`** model.
*   `run_ik_llama_server.ps1` uses the **`Qwen3-Coder-30B-A3B-Instruct-IQ4_KSS.gguf`** model, which is a special quantization format supported by this fork.

The server starts on [http://localhost:8080](http://localhost:8080) and exposes both a browser chat UI and an OpenAI-compatible REST API.

### Performance Note

With the provided settings, both server implementations should achieve comparable performance. On a system with a **Ryzen 5 7600 CPU, 32GB DDR5-5600 RAM, and an NVIDIA RTX 4070 Ti (12GB)**, both servers run at approximately **35 tokens/second**.

### CUDA Architecture (`-CudaArch`)

To get the best performance, match the `-CudaArch` parameter to your GPU generation during installation.

| Architecture  | Cards (examples)   | Flag         |
| ------------- | ------------------ | ------------ |
| **Pascal**    | GTX 10×0, Quadro P | 60 / 61 / 62 |
| **Turing**    | RTX 20×0 / 16×0    | 75           |
| **Ampere**    | RTX 30×0           | 80 / 86 / 87 |
| **Ada**       | RTX 40×0           | 89           |
| **Blackwell** | RTX 50×0           | 90           |

---

## Parameter Explanations

The `run` scripts use a set of optimized flags to launch the server. Most of these are now available in both `llama.cpp` and `ik_llama.cpp`.

| Flag | Purpose | Value(s) in Script |
| --- | --- | --- |
| `-ngl 999` | Offloads all possible layers to the GPU. | `999` (all) |
| `-c 65536` | Sets the context size for the model. | `65536` |
| `-fa` | Enables Flash Attention kernels for faster processing. | Enabled |
| `-ctk <type>` | Quantizes the 'key' part of the KV cache to save memory. | `q8_0` (8-bit) |
| `-ctv <type>` | Quantizes the 'value' part of the KV cache. | `q4_0` (4-bit) |
| `-ot <regex>=<backend>` | Overrides tensor placement. Used here to keep some MoE experts on the CPU to save VRAM. | See script |
| `--temp`, `--top-p`, etc. | Standard sampling parameters to control the model's output. | See script |

### Key `ik_llama.cpp` Differences

While `llama.cpp` has integrated many high-performance features, `ik_llama.cpp` currently provides a few unique advantages:

*   **`-fmoe` / `--fused-moe`**: Enables fused Mixture-of-Experts kernels, which can improve performance for models like Qwen that use this architecture.
*   **`-ser <n>,<p>` / `--smart-expert-reduction`**: A powerful feature that computes only the most probable `n` experts with a cumulative probability of `p`. This can significantly speed up MoE models by reducing computation, especially on GPUs with lower memory bandwidth.
*   **Specialized Quants**: `ik_llama.cpp` often supports new quantization methods first. The `run_ik_llama_server.ps1` script uses the **`IQ4_KSS`** quant, which can offer a different balance of performance and quality compared to the `IQ4_NL` quant used by the standard `llama.cpp` script.

The `run_ik_llama_server.ps1` script enables `-fmoe` and `-ser` for maximum performance.

## License

This project is licensed under the MIT License. See the [LICENSE](LICENSE) file for details.
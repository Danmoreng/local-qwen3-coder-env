# Qwen3.8-27B with llama.cpp and Pi on a 16GB NVIDIA GPU

This guide sets up Qwen3.8-27B as a fully local coding agent on Windows. The recommended path uses this repository's tuned llama.cpp build and launcher together with Hugging Face's [`pi-llama`](https://github.com/huggingface/pi-llama) extension for [Pi](https://pi.dev/).

The official [llama.app](https://llama.app/) is also covered as a simpler prebuilt alternative. It installs the unified `llama` executable: `llama serve` and `llama-server` expose the same server functionality.

## Recommended configuration

The 16GB profile is intentionally text-first and single-user:

| Component | Choice |
| --- | --- |
| Model | `unsloth/Qwen3.8-27B-GGUF` |
| Hub revision | `27af057ecb382ddfea5d12837360a8980560e3ed` |
| GGUF | `Qwen3.8-27B-UD-IQ3_XXS.gguf` (Unsloth Dynamic 3.0, about 10.9 GB) |
| Context | Fixed 98,304 tokens; optional 81,920-token safe profile |
| KV cache | Q8 for keys and values |
| Server slots | 1 |
| Prompt batch / micro-batch | 1024 / 512 |
| Attention | Flash Attention |
| Drafting | Integrated MTP (`draft-mtp`) |
| Reasoning | Medium effort with an 8K hard budget, an action-oriented cutoff message, and history preserved |
| Vision | Opt-in; projector runs on CPU/RAM by default |
| Local API | `http://localhost:8080/v1` |

`UD-IQ3_XXS` leaves substantially more room for context and GPU offload than a larger 4-bit quantization. The tradeoff is some model quality. On a 16GB card, that is usually preferable for agent work, where a useful context window and stable tool loop matter more than maximizing weight precision.

## 1. Install and start llama.cpp

Choose one of the following server paths. Do not start both at the same time because both use port 8080.

### Path A: tuned repository launcher (recommended)

Open PowerShell 7 in this repository and run:

```powershell
.\install_llama_cpp.ps1
.\run_qwen3_8_optimized.ps1
```

The first launch downloads or resolves the recommended GGUF. Keep this terminal open while Pi is running.

The default text profile uses the tested 96K context. If Windows, another application, or a different 16GB GPU needs more VRAM headroom, start the 80K fallback with `.\run_qwen3_8_optimized.ps1 -SafeContext`.

The current repository launcher binds to `0.0.0.0`, so Windows Firewall may make it reachable from the local network. For a strictly local coding setup, change its `--host` value to `127.0.0.1` or restrict access with the firewall.

The default is text-only. Enable vision when Pi needs to inspect screenshots, diagrams, or other images:

```powershell
.\run_qwen3_8_optimized.ps1 -Vision
```

This Windows profile fixes the context at 81,920 tokens and passes `--no-mmproj-offload --mmproj-device none`, keeping the approximately 0.93 GB BF16 projector in system RAM and executing it on the CPU. The quantized language model remains on the GPU, and its context still includes the image tokens. If image-encoding speed matters more than VRAM headroom, opt into GPU projector offload and dynamic fitting:

```powershell
.\run_qwen3_8_optimized.ps1 -Vision -VisionGpu
```

### Path B: official llama.app binary

The official installer detects the available acceleration backend and installs the unified `llama` command:

```powershell
irm https://llama.app/install.ps1 | iex
```

Review downloaded scripts before piping them into PowerShell if required by your security policy. Then reproduce this repository's text-only 16GB profile:

```powershell
llama serve `
    --hf-repo unsloth/Qwen3.8-27B-GGUF `
    --hf-file Qwen3.8-27B-UD-IQ3_XXS.gguf `
    --no-mmproj `
    --alias unsloth/Qwen3.8-27B-UD-IQ3_XXS `
    --fit off `
    -c 98304 `
    --flash-attn on `
    -np 1 `
    -b 1024 `
    -ub 512 `
    -ctk q8_0 `
    -ctv q8_0 `
    --temp 1.0 `
    --top-p 0.95 `
    --top-k 20 `
    --min-p 0.0 `
    --presence-penalty 0.0 `
    --repeat-penalty 1.0 `
    --reasoning-effort medium `
    --reasoning-budget 8192 `
    --reasoning-budget-message "... I have been thinking for too long -- let me gather more information about the task and take the next concrete action." `
    --reasoning-preserve `
    --spec-default `
    --spec-type draft-mtp `
    --host 127.0.0.1 `
    --port 8080
```

Unlike a bare `llama serve`, this starts a tuned single-model server. A bare invocation starts llama.cpp's multi-model router and discovers models from its cache; see [Router mode](#router-mode-with-pis-built-in-integration) below.

## 2. Verify the server

In a second PowerShell terminal:

```powershell
Invoke-RestMethod http://localhost:8080/health
Invoke-RestMethod http://localhost:8080/v1/models | ConvertTo-Json -Depth 6
```

The health request should succeed and the models response should contain the Qwen alias. Wait for model loading to finish if the server is still downloading or allocating memory.

## 3. Install Pi on Windows

Pi needs Node.js and a Bash-compatible shell for its coding tools. Current Pi documentation recommends Git for Windows as the simplest Bash provider on Windows.

1. Install [Node.js LTS](https://nodejs.org/) and [Git for Windows](https://git-scm.com/download/win).
2. Open a new PowerShell terminal so `node`, `npm`, `git`, and `bash` can be rediscovered.
3. Install Pi:

```powershell
npm install -g --ignore-scripts @earendil-works/pi-coding-agent
pi --version
```

Pi packages and extensions execute with the user's filesystem and process permissions. Review third-party extension source before installing it.

## 4. Connect Pi through pi-llama

Install Hugging Face's extension once:

```powershell
pi install git:github.com/huggingface/pi-llama
```

The extension defaults match this repository:

- `LLAMA_BASE_URL=http://localhost:8080/v1`
- `LLAMA_API_KEY=no-key`

This repository includes `.pi/settings.json`, which selects the discovered `llama-cpp` Qwen3.8 model and Pi's `medium` thinking level without changing your global Pi defaults. Start Pi from the repository root after the server is ready:

```powershell
pi
```

The first interactive launch may ask you to trust the repository before loading its project settings. For a one-off explicit launch that does not depend on project defaults, use:

```powershell
pi --provider llama-cpp --model unsloth/Qwen3.8-27B-UD-IQ3_XXS --thinking medium
```

Start the llama.cpp server before launching Pi. Then change to the root of the codebase that Pi should edit:

```powershell
Set-Location C:\path\to\your\project
pi
```

Inside Pi:

1. Run `/model` or press `Ctrl+L`.
2. Search for the `llama-cpp` provider.
3. Select `unsloth/Qwen3.8-27B-UD-IQ3_XXS`.
4. Use `/llama-version` to confirm which llama.cpp build the extension reached.

`pi-llama` queries the running server for its model list, effective context window, chat template, and thinking support. No API key is needed for the local default endpoint. Current single-model llama.cpp responses advertise the multimodal capability without the `architecture.input_modalities` field that `pi-llama` reads, and the extension otherwise advertises a fixed 16K per-response output limit. Use the following user-level override in `~/.pi/agent/models.json` to expose image attachments to Pi and allow up to 32K output tokens:

```json
{
  "providers": {
    "llama-cpp": {
      "modelOverrides": {
        "unsloth/Qwen3.8-27B-UD-IQ3_XXS": {
          "input": ["text", "image"],
          "maxTokens": 32768
        }
      }
    }
  }
}
```

With the server-side 8K reasoning budget, a single model turn therefore retains up to roughly 24K tokens for tool calls and final output. The actual available output also depends on how much of the active 96K text or 80K vision context is already occupied by the conversation. Attach an image on the command line with `pi @screenshot.png "Inspect this UI"`, drag it into Pi, or paste it in the interactive terminal.

If Pi runs on another machine or the endpoint is different, set the variables before starting Pi:

```powershell
$env:LLAMA_BASE_URL = 'http://server-name:8080/v1'
$env:LLAMA_API_KEY = 'no-key'
pi
```

For a remote endpoint, protect the server with an API key and an appropriate firewall or reverse proxy. Do not expose an unauthenticated coding-model endpoint directly to the internet.

## 5. Use Pi effectively with a 96K local context

- Start Pi in the repository root. Pi automatically loads applicable `AGENTS.md` or `CLAUDE.md` files, so keep project commands and conventions there.
- Give one concrete task at a time and name the relevant area of the codebase. A 27B local model is more reliable with bounded changes than with broad, underspecified rewrites.
- Ask it to inspect before editing and to run the smallest relevant tests after editing.
- Keep Git changes reviewable. Check `git diff` between larger tasks and create your own checkpoints before risky work.
- Use `/compact` before the context is nearly full. Pi also compacts automatically, but manual compaction at a clean task boundary usually preserves intent better.
- Start a fresh Pi session for unrelated work. Old tool output consumes context without helping the next task.
- Leave vision disabled for ordinary coding. Enable CPU/RAM vision for screenshots, diagrams, or UI inspection; use `-VisionGpu` only when the additional VRAM use is acceptable.

The text launcher's `--fit off -c 98304` profile fixes the context and prevents llama.cpp's automatic fitter from conservatively changing GPU placement. With the current 10.9 GB Dynamic 3.0 GGUF on the tested RTX 5080 Laptop GPU, a 4,153-token prompt plus MTP generation left 358 MiB of total GPU memory free. This is the highest practical tested agent profile, but it assumes the GPU is otherwise mostly idle. Use `-SafeContext` for the 80K profile when Windows or other GPU applications need more headroom.

## Router mode with Pi's built-in integration

Current Pi versions can manage llama.cpp's multi-model router without `pi-llama`. This is useful when convenience and model switching matter more than one precisely tuned model process.

Start the current unified app without `--model`, `-m`, or `-hf`:

```powershell
llama serve --models-dir C:\path\to\gguf-models --no-models-autoload --jinja --host 127.0.0.1 --port 8080 -ngl 999 -c 32768
```

Then, inside Pi:

```text
/login llama.cpp
/llama
/model
```

`/llama` loads or unloads router models; only loaded models appear in `/model`. Per-model presets are the right place for advanced settings such as Qwen3.8's fixed 96K context, Q8 KV cache, and MTP. The tuned single-model launcher is simpler when Qwen3.8-27B is the only desired model.

## Troubleshooting and tuning

### `llama-cpp` does not appear in `/model`

Start the server first, verify `/v1/models`, and restart Pi. Confirm that `LLAMA_BASE_URL` ends in `/v1` when using `pi-llama`.

### Pi cannot run shell tools on Windows

Install Git for Windows. Pi looks for Git Bash at `C:\Program Files\Git\bin\bash.exe`. A custom Bash path can be set as `shellPath` in `~/.pi/agent/settings.json`.

### CUDA out-of-memory or unstable desktop

Close GPU-heavy browsers, games, video tools, and other model servers before loading Qwen. If pressure remains:

1. Start the optimized launcher with `-SafeContext` to reduce the fixed context from 96K to 80K.
2. If more headroom is still required, reduce the context to `-c 65536` or replace the fixed profile with `--fit on --fit-target 512 --fit-ctx 32768` to allow automatic placement.
3. Keep vision disabled, or use the default CPU/RAM projector mode rather than `-VisionGpu`.
4. Reduce `-b` to `512` and `-ub` to `256` if prompt ingestion causes the failure.

These changes favor stability over context size or prompt-processing speed.

### Responses are slow

Confirm from the server log that CUDA is active, Flash Attention is enabled, most model layers are offloaded, and MTP reports drafted-token acceptance. Generation speed also falls as the active context grows; compact or start a new session when old history is no longer useful.

### Update the components

```powershell
# llama.app installation
llama update

# Pi and installed extensions
pi update --all
```

For this repository's source build, rerun `install_llama_cpp.ps1` when you intentionally want to rebuild/update llama.cpp, then recheck the launcher's supported arguments.

## Upstream references

- [llama.app](https://llama.app/)
- [Unified llama app announcement](https://github.com/ggml-org/llama.cpp/discussions/23875)
- [llama.cpp server and router documentation](https://github.com/ggml-org/llama.cpp/blob/master/tools/server/README.md)
- [Hugging Face pi-llama extension](https://github.com/huggingface/pi-llama)
- [Pi coding agent](https://pi.dev/)
- [Pi llama.cpp router documentation](https://github.com/earendil-works/pi/blob/main/packages/coding-agent/docs/llama-cpp.md)
- [Pi Windows documentation](https://github.com/earendil-works/pi/blob/main/packages/coding-agent/docs/windows.md)

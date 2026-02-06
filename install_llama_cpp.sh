#!/bin/bash
set -e

# install_llama_cpp.sh
# --------------------
# Installs prerequisites and builds ggerganov/llama.cpp on Linux.
# Mimics the functionality of install_llama_cpp.ps1

# Helper to check commands
command_exists() {
  command -v "$1" >/dev/null 2>&1
}

echo "Checking prerequisites..."

if ! command_exists git; then
  echo "Error: 'git' is not installed. Please install it using your package manager."
  exit 1
fi

if ! command_exists cmake; then
  echo "Error: 'cmake' is not installed. Please install it using your package manager."
  exit 1
fi

if ! command_exists node; then
    echo "Error: 'node' (Node.js) is not installed. Please install it (LTS version recommended)."
    exit 1
fi

if ! command_exists npm; then
    echo "Error: 'npm' is not installed. Please install it."
    exit 1
fi

if ! command_exists ninja; then
  echo "Warning: 'ninja' is not installed. CMake will default to 'make'."
  echo "         Installing ninja-build is recommended for faster builds."
fi

if ! command_exists nvcc; then
  echo "Warning: 'nvcc' (CUDA compiler) not found in PATH."
  echo "         Build will likely fall back to CPU-only or fail if CUDA is expected."
  echo "         Please ensure the CUDA Toolkit (12.4+) is installed and in your PATH."
else
    NVCC_VERSION=$(nvcc --version | grep "release" | sed 's/.*release //;s/,.*//')
    echo "Found CUDA compiler: $NVCC_VERSION"
fi

# Setup directories
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
LLAMA_REPO="$SCRIPT_DIR/vendor/llama.cpp"
LLAMA_BUILD="$LLAMA_REPO/build"

# Clone or Update llama.cpp
if [ ! -d "$LLAMA_REPO" ]; then
  echo "-> Cloning llama.cpp into $LLAMA_REPO..."
  git clone https://github.com/ggerganov/llama.cpp "$LLAMA_REPO"
else
  echo "-> Updating existing llama.cpp in $LLAMA_REPO..."
  git -C "$LLAMA_REPO" pull --ff-only
fi

git -C "$LLAMA_REPO" submodule update --init --recursive

# Configure & Build
echo "-> Configuring CMake..."
mkdir -p "$LLAMA_BUILD"
cd "$LLAMA_BUILD"

# CMake Arguments
# -DGGML_CUDA=ON enables CUDA backend
# -DCMAKE_CUDA_ARCHITECTURES=native targets the local GPU
CMAKE_ARGS="-DGGML_CUDA=ON -DGGML_CUBLAS=ON -DCMAKE_BUILD_TYPE=Release -DLLAMA_CURL=OFF -DGGML_CUDA_FA_ALL_QUANTS=ON -DCMAKE_CUDA_ARCHITECTURES=native"

if command_exists ninja; then
  CMAKE_ARGS="-G Ninja $CMAKE_ARGS"
fi

echo "Running cmake with: $CMAKE_ARGS"
cmake .. $CMAKE_ARGS

echo "-> Building targets (llama-server, llama-cli, etc.)..."
cmake --build . --config Release --target llama-server llama-batched-bench llama-cli llama-bench llama-fit-params --parallel

echo ""
echo "Done! llama.cpp (CUDA) binaries are in: $LLAMA_BUILD/bin"

# --- Vulkan Build ---
if command_exists glslc; then
    echo ""
    echo "-> Vulkan SDK (glslc) found."

    # Arch Linux: Check for headers
    if [ -f "/etc/arch-release" ]; then
        if ! pacman -Q vulkan-headers >/dev/null 2>&1; then
             echo "-> Missing 'vulkan-headers'. Attempting to install..."
             if sudo pacman -S --needed --noconfirm vulkan-headers vulkan-icd-loader vulkan-tools shaderc; then
                 echo "[OK] Vulkan dependencies installed."
             else
                 echo "Error: Failed to install Vulkan headers. Please run: sudo pacman -S vulkan-headers"
                 exit 1
             fi
        fi
    fi

    echo "-> Building llama.cpp with Vulkan support..."
    LLAMA_BUILD_VK="$LLAMA_REPO/build-vulkan"
    mkdir -p "$LLAMA_BUILD_VK"
    cd "$LLAMA_BUILD_VK"

    # Configure for Vulkan (Disable CUDA to ensure pure Vulkan build/priority)
    CMAKE_ARGS_VK="-DGGML_VULKAN=ON -DGGML_CUDA=OFF -DCMAKE_BUILD_TYPE=Release -DLLAMA_CURL=OFF"
    
    if command_exists ninja; then
        CMAKE_ARGS_VK="-G Ninja $CMAKE_ARGS_VK"
    fi

    echo "Running cmake (Vulkan) with: $CMAKE_ARGS_VK"
    cmake .. $CMAKE_ARGS_VK

    echo "-> Building targets (Vulkan)..."
    cmake --build . --config Release --target llama-server llama-batched-bench llama-cli llama-bench llama-fit-params --parallel

    echo ""
    echo "Done! llama.cpp (Vulkan) binaries are in: $LLAMA_BUILD_VK/bin"
else
    echo ""
    echo "Warning: 'glslc' not found. Skipping Vulkan build."
    echo "         Please install the Vulkan SDK (vulkan-devel / vulkan-sdk) to enable this."
fi

# Install qwen-code CLI
echo "-> Installing qwen-code CLI globally..."
# We use sudo for global install if we are not root/owner, trying without first or checking permission might be better but standard is often sudo npm install -g
if [ -w "$(npm root -g)" ]; then
    npm install -g @qwen-code/qwen-code@latest
else
    echo "   (Root privileges required for global npm install)"
    sudo npm install -g @qwen-code/qwen-code@latest
fi

echo "[OK] qwen-code CLI installed."

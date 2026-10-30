#!/usr/bin/env bash
# Proje geliştirme ortamı kurulumu (CachyOS / Arch Linux).
#
#   ./setup.sh                  # her şeyi kur (tekrar çalıştırmak güvenlidir)
#   ./setup.sh --skip-system    # pacman adımını atla (Arch dışı sistemler için)
#   TORCH_BACKEND=cu126 ./setup.sh   # PyTorch derlemesini elle seç (varsayılan: auto)
#
# Kurulanlar:
#   - sistem paketleri (pacman): base-devel git cmake ninja uv pciutils
#   - .venv: uv'nin yönettiği Python + PyTorch + requirements.txt + gguf-py
#   - third_party/llama.cpp: versions.env'deki sürüm, CPU derlemesi
# Sonunda scripts/check_env.py ortamı doğrular ve raporu env_reports/ altına yazar.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$ROOT"
# shellcheck source=versions.env
source "$ROOT/versions.env"

SKIP_SYSTEM=0
for arg in "$@"; do
    case "$arg" in
        --skip-system) SKIP_SYSTEM=1 ;;
        -h|--help) sed -n '2,13p' "$0"; exit 0 ;;
        *) echo "Bilinmeyen seçenek: $arg" >&2; exit 2 ;;
    esac
done

TORCH_BACKEND="${TORCH_BACKEND:-auto}"
LLAMA_DIR="$ROOT/third_party/llama.cpp"
VENV="$ROOT/.venv"
JOBS="$(nproc)"

step() { printf '\n\033[1;34m==> %s\033[0m\n' "$*"; }
warn() { printf '\033[1;33m!! %s\033[0m\n' "$*" >&2; }
die()  { printf '\033[1;31mXX %s\033[0m\n' "$*" >&2; exit 1; }

# ---------------------------------------------------------------- 1. sistem
step "1/6 Sistem paketleri"
SYS_PKGS=(base-devel git cmake ninja uv pciutils)
if [[ $SKIP_SYSTEM -eq 0 ]] && command -v pacman >/dev/null; then
    missing="$(pacman -T "${SYS_PKGS[@]}" || true)"
    if [[ -n "$missing" ]]; then
        echo "Eksik paketler: $missing"
        # shellcheck disable=SC2086
        sudo pacman -S --needed $missing
    else
        echo "Hepsi kurulu."
    fi
else
    [[ $SKIP_SYSTEM -eq 0 ]] && warn "pacman bulunamadı; sistem paketleri atlanıyor."
    for cmd in git cmake ninja g++ uv; do
        command -v "$cmd" >/dev/null || die "'$cmd' bulunamadı. Önce sistem paket yöneticisiyle kur."
    done
    echo "Gerekli komutlar mevcut."
fi

# ---------------------------------------------------------------- 2. donanım
step "2/6 Donanım"
echo "CPU : $(grep -m1 'model name' /proc/cpuinfo | cut -d: -f2 | xargs) ($JOBS iş parçacığı)"
echo "RAM : $(awk '/MemTotal/ {printf "%.1f GiB", $2/1048576}' /proc/meminfo)"
if command -v nvidia-smi >/dev/null && nvidia-smi >/dev/null 2>&1; then
    nvidia-smi --query-gpu=name,driver_version,memory.total,compute_cap --format=csv,noheader \
        | sed 's/^/GPU : /'
elif command -v lspci >/dev/null; then
    lspci | grep -Ei 'vga|3d|display' | sed 's/^/GPU : /' || true
    warn "nvidia-smi çalışmıyor; PyTorch CUDA'sız kurulabilir."
fi

# ---------------------------------------------------------------- 3. llama.cpp kaynak
step "3/6 llama.cpp ($LLAMA_CPP_REF)"
if [[ ! -d "$LLAMA_DIR/.git" ]]; then
    mkdir -p "$(dirname "$LLAMA_DIR")"
    git -c advice.detachedHead=false clone --depth 1 --branch "$LLAMA_CPP_REF" \
        https://github.com/ggml-org/llama.cpp "$LLAMA_DIR"
elif [[ "$(git -C "$LLAMA_DIR" rev-parse HEAD)" != \
        "$(git -C "$LLAMA_DIR" rev-parse -q --verify "$LLAMA_CPP_REF^{commit}" || echo none)" ]]; then
    git -C "$LLAMA_DIR" fetch --depth 1 origin tag "$LLAMA_CPP_REF"
    git -C "$LLAMA_DIR" -c advice.detachedHead=false checkout "$LLAMA_CPP_REF"
else
    echo "Zaten $LLAMA_CPP_REF sürümünde."
fi

# ---------------------------------------------------------------- 4. python
step "4/6 Python $PYTHON_VERSION ortamı (.venv)"
# uv'nin indirdiği Python kullanılır: iki makinede de aynı sürüm olsun diye.
uv venv --python "$PYTHON_VERSION" --managed-python --allow-existing "$VENV"
export VIRTUAL_ENV="$VENV"

echo "PyTorch $TORCH_VERSION (backend: $TORCH_BACKEND)"
uv pip install "torch==$TORCH_VERSION" --torch-backend "$TORCH_BACKEND" \
    || die "PyTorch kurulamadı. Eski bir GPU'n varsa TORCH_BACKEND=cu126 dene; gerekirse versions.env'deki TORCH_VERSION'ı değiştir."
uv pip install -r requirements.txt
# gguf-py'yi pinlenmiş llama.cpp'den kur: dönüştürücüyle aynı sürüm olsun.
uv pip install -e "$LLAMA_DIR/gguf-py"

# ---------------------------------------------------------------- 5. llama.cpp derleme
step "5/6 llama.cpp derlemesi (CPU, $JOBS iş parçacığı)"
cmake -S "$LLAMA_DIR" -B "$LLAMA_DIR/build" -G Ninja \
    -DCMAKE_BUILD_TYPE=Release \
    -DLLAMA_BUILD_TESTS=OFF -DLLAMA_BUILD_EXAMPLES=OFF \
    -DLLAMA_BUILD_SERVER=OFF -DLLAMA_BUILD_APP=OFF \
    >/dev/null
cmake --build "$LLAMA_DIR/build" -j "$JOBS" --target \
    llama-quantize llama-perplexity llama-bench llama-completion llama-tokenize llama-gguf-split

# ---------------------------------------------------------------- 6. doğrulama
step "6/6 Ortam kontrolü"
"$VENV/bin/python" scripts/check_env.py

printf '\n\033[1;32mKurulum tamam.\033[0m Her yeni terminalde:  source env.fish  (bash/zsh: source env.sh)\n'

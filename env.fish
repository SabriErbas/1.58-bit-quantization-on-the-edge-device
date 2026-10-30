# Kullanım (fish, CachyOS'un varsayılan kabuğu):  source env.fish
# .venv'i etkinleştirir ve llama.cpp araçlarını PATH'e ekler.

set -l _root (path resolve (dirname (status --current-filename)))
source $_root/.venv/bin/activate.fish
set -gx LLAMA_CPP_DIR $_root/third_party/llama.cpp
if not contains -- $LLAMA_CPP_DIR/build/bin $PATH
    set -gx PATH $LLAMA_CPP_DIR/build/bin $PATH
end

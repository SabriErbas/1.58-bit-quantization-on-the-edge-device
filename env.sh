# shellcheck shell=bash
# Kullanım:  source env.sh
# .venv'i etkinleştirir ve llama.cpp araçlarını (llama-quantize, llama-perplexity,
# llama-bench, ...) PATH'e ekler. convert_hf_to_gguf.py için $LLAMA_CPP_DIR kullan.

_root="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
# shellcheck source=/dev/null
source "$_root/.venv/bin/activate"
export LLAMA_CPP_DIR="$_root/third_party/llama.cpp"
case ":$PATH:" in
    *":$LLAMA_CPP_DIR/build/bin:"*) ;;
    *) export PATH="$LLAMA_CPP_DIR/build/bin:$PATH" ;;
esac
unset _root

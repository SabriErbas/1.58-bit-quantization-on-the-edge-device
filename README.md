# 1.58-bit-quantization-on-the-edge-device
1.58-bit (ternary) weight quantization - graduation project

## Kurulum (CachyOS / Arch Linux)

```bash
git clone https://github.com/SabriErbas/1.58-bit-quantization-on-the-edge-device
cd 1.58-bit-quantization-on-the-edge-device
./setup.sh          # tekrar çalıştırmak güvenlidir
source env.fish     # her yeni terminalde (bash/zsh: source env.sh)
```

`env.fish` / `env.sh`, `.venv`'i etkinleştirir ve llama.cpp araçlarını
(`llama-quantize`, `llama-perplexity`, `llama-bench`, ...) PATH'e ekler;
`convert_hf_to_gguf.py` için `$LLAMA_CPP_DIR` kullanılabilir.

`setup.sh` şunları yapar: eksik sistem paketlerini pacman ile kurar, `.venv` içine
uv'nin yönettiği Python'u, PyTorch'u (GPU'ya göre otomatik seçilir) ve
`requirements.txt`'yi kurar, `versions.env`'de sabitlenen llama.cpp sürümünü
`third_party/` altına indirip CPU için derler ve son olarak
`scripts/check_env.py` ile ortamı doğrular.

- **Sürümler** `versions.env`'de sabittir (Python, PyTorch, llama.cpp). İki makinede
  aynı sonuçları almak için bu dosyayı birlikte güncelleyin.
- **PyTorch derlemesi** varsayılan olarak sürücüye göre seçilir. Eski bir NVIDIA
  kartta (GTX 10xx ve öncesi) GPU testi başarısız olursa: `TORCH_BACKEND=cu126 ./setup.sh`
- **Python paketi eklemek:** `requirements.in`'e yazın, sonra
  `uv pip compile requirements.in --python-version 3.12 -o requirements.txt`
  ve `./setup.sh`.
- **Ortam raporu** `env_reports/<makine>.txt` dosyasına yazılır; tezdeki
  yazılım/donanım sürüm bilgileri buradan alınabilir.

"""Geliştirme ortamını doğrular ve sürüm raporunu env_reports/<makine>.txt'ye yazar.

Tez için yazılım/donanım sürümlerinin kaydı bu rapordan alınabilir.
Kullanım:  python scripts/check_env.py
"""

from __future__ import annotations

import datetime as dt
import importlib
import os
import platform
import socket
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
LLAMA_DIR = ROOT / "third_party" / "llama.cpp"
LLAMA_BIN = LLAMA_DIR / "build" / "bin"
LLAMA_TOOLS = ["llama-quantize", "llama-perplexity", "llama-bench", "llama-completion"]

lines: list[str] = []
problems: list[str] = []


def report(key: str, value: object) -> None:
    line = f"{key:<22}: {value}"
    lines.append(line)
    print(line)


def fail(msg: str) -> None:
    problems.append(msg)
    print(f"  !! {msg}")


def sh(*cmd: str) -> str:
    try:
        out = subprocess.run(cmd, capture_output=True, text=True, timeout=30)
        return (out.stdout + out.stderr).strip()
    except (OSError, subprocess.TimeoutExpired) as e:
        return f"<{e}>"


# --- sistem
report("tarih", dt.datetime.now().isoformat(timespec="seconds"))
report("makine", socket.gethostname())
report("işletim sistemi", platform.platform())
cpu = next((l.split(":", 1)[1].strip() for l in open("/proc/cpuinfo") if l.startswith("model name")), "?")
report("cpu", f"{cpu} ({os.cpu_count()} iş parçacığı)")
mem_kb = next(int(l.split()[1]) for l in open("/proc/meminfo") if l.startswith("MemTotal"))
report("ram", f"{mem_kb / 2**20:.1f} GiB")
report("python", sys.version.split()[0])

# --- pytorch
try:
    import torch

    report("torch", torch.__version__)
    report("torch cuda/hip", torch.version.cuda or getattr(torch.version, "hip", None) or "yok (CPU)")
    if torch.cuda.is_available():
        p = torch.cuda.get_device_properties(0)
        report("gpu", f"{p.name}, {p.total_memory / 2**30:.1f} GiB, sm_{p.major}{p.minor}")
        report("bf16 desteği", torch.cuda.is_bf16_supported())
        try:
            a = torch.randn(256, 256, device="cuda")
            err = (a @ a.T - (a.cpu() @ a.cpu().T).cuda()).abs().max().item()
            report("gpu matmul testi", f"tamam (maks. fark {err:.1e})")
        except RuntimeError as e:
            fail(f"GPU'da işlem çalışmadı: {e}. TORCH_BACKEND=cu126 ./setup.sh dene.")
    else:
        report("gpu", "PyTorch GPU görmüyor; eğitim CPU'da çalışır (yalnızca küçük testler için uygun)")
except ImportError as e:
    fail(f"torch içe aktarılamadı: {e}")

# --- diğer paketler
for mod in ["numpy", "sentencepiece", "transformers", "safetensors", "datasets", "yaml", "pandas", "matplotlib"]:
    try:
        report(mod, getattr(importlib.import_module(mod), "__version__", "?"))
    except ImportError as e:
        fail(f"{mod} içe aktarılamadı: {e}")

try:
    import gguf

    has_tq = all(hasattr(gguf.GGMLQuantizationType, t) for t in ("TQ1_0", "TQ2_0"))
    report("gguf-py", f"{Path(gguf.__file__).parent} (TQ1_0/TQ2_0: {'var' if has_tq else 'YOK'})")
    if not has_tq:
        fail("gguf-py üç değerli tipleri tanımıyor")
except ImportError as e:
    fail(f"gguf içe aktarılamadı: {e}")

# --- llama.cpp
if (LLAMA_DIR / ".git").exists():
    ref = sh("git", "-C", str(LLAMA_DIR), "describe", "--tags", "--always")
    commit = sh("git", "-C", str(LLAMA_DIR), "rev-parse", "--short", "HEAD")
    report("llama.cpp", f"{ref} ({commit})")
else:
    fail("third_party/llama.cpp bulunamadı")

missing = [t for t in LLAMA_TOOLS if not (LLAMA_BIN / t).exists()]
if missing:
    fail(f"derlenmemiş llama.cpp araçları: {', '.join(missing)}")
else:
    help_text = sh(str(LLAMA_BIN / "llama-quantize"), "--help")
    ok = "TQ1_0" in help_text and "TQ2_0" in help_text
    report("llama-quantize", f"TQ1_0/TQ2_0: {'var' if ok else 'YOK'}")
    if not ok:
        fail("llama-quantize üç değerli tipleri listelemiyor")
    report("derleyici", sh("c++", "--version").splitlines()[0])

# --- rapor
out_dir = ROOT / "env_reports"
out_dir.mkdir(exist_ok=True)
out_file = out_dir / f"{socket.gethostname()}.txt"
out_file.write_text("\n".join(lines) + "\n")
print(f"\nRapor: {out_file.relative_to(ROOT)}")

if problems:
    print(f"\n{len(problems)} sorun bulundu:")
    for p in problems:
        print(f"  - {p}")
    sys.exit(1)
print("Ortam hazır.")

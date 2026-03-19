# AIserver — llama.cpp on TrueNAS ElectricEel

Self-hosted LLM inference server running llama.cpp inside a Ubuntu VM on TrueNAS SCALE, with dual NVIDIA GPU passthrough.

---

## System Overview

```
TrueNAS SCALE (ElectricEel-24.10.2.2)
├── Host GPU: AMD Radeon (Ryzen 7600X iGPU) — reserved for TrueNAS
├── Isolated GPUs: 2× NVIDIA RTX 4060 Ti 16GB — passed to VM
└── VM: "AIserver" (Ubuntu Server 24.04 LTS)
    ├── llama-server (systemd service, starts on boot)
    ├── Model: Qwen 3.5 27B (Q4_K_M or Q6_K GGUF)
    └── OpenAI-compatible API on port 8080
```

### Boot Chain

TrueNAS boots → VM "AIserver" auto-starts → systemd starts `llama-server` → API available at `http://<VM-IP>:8080/v1/`

---

## Hardware

| Component | Details |
|-----------|---------|
| CPU | AMD Ryzen 5 7600X (6 cores / 12 threads) |
| RAM | 64 GB DDR5 |
| GPU 0 | NVIDIA RTX 4060 Ti 16GB (`0000:01:00.0`) — isolated for VM |
| GPU 1 | NVIDIA RTX 4060 Ti 16GB (`0000:11:00.0`) — isolated for VM |
| iGPU | AMD Radeon (Raphael, `0000:12:00.0`) — used by TrueNAS host |
| Total VRAM | 32,760 MiB (~32 GB) across both GPUs |

### VRAM Budget

Usable VRAM after CUDA overhead: ~30 GB. Budget by quantization:

| Quant | Model Size | VRAM Left for KV Cache | Max Context (approx) |
|-------|-----------|----------------------|---------------------|
| Q4_K_M | ~16.5 GB | ~14 GB | ~98K tokens |
| Q6_K | ~22 GB | ~8 GB | ~32K tokens |
| Q8_0 | ~28.6 GB | ~1.5 GB | Risky, not recommended |

---

## TrueNAS Configuration

### BIOS Settings (Required)

These must be set in the motherboard BIOS before TrueNAS can do GPU passthrough:

- **Integrated Graphics / IGFX Multi-Monitor**: Enabled / Force
- **Initial Display Output / Primary Display**: iGPU / Integrated Graphics
- **IOMMU / AMD-Vi**: Enabled
- **SVM Mode**: Enabled
- **Above 4G Decoding**: Enabled
- **Re-Size BAR Support**: Enabled

### GPU Isolation

Location: **System → Advanced Settings → Isolated GPU Device(s) → Configure**

Both RTX 4060 Ti cards are isolated. The AMD Raphael iGPU is NOT isolated (kept for TrueNAS host). A reboot is required after changing GPU isolation.

**Warning:** Isolated GPUs are unavailable to TrueNAS Apps (e.g., Ollama containers). If you need GPUs for Apps, you must un-isolate them and remove them from the VM.

### VM Configuration ("AIserver")

Location: **Virtualization → Virtual Machines → AIserver**

| Setting | Value |
|---------|-------|
| Guest OS | Linux |
| Start on Boot | Yes |
| Boot Loader | UEFI |
| Virtual CPUs | 1 |
| Cores | 4 |
| Threads | 2 |
| CPU Mode | Host Passthrough |
| Memory | 32 GiB |
| Disk | 200 GiB VirtIO zvol at `unprotectedStorage/virtualMachines` |
| NIC | VirtIO on `enp6s0` |
| GPUs | Both RTX 4060 Ti (isolated) |
| Hide from MSR | Yes |
| Ensure Display Device | Yes |
| Display | SPICE (for console access during setup) |

---

## VM Internal Configuration

### OS

Ubuntu Server 24.04 LTS. SSH enabled. User: `daryl`.

### NVIDIA Driver

Installed via Ubuntu repository:

```bash
sudo apt install -y ubuntu-drivers-common
sudo ubuntu-drivers devices          # lists available drivers
sudo apt install -y nvidia-driver-580-open   # installed version
```

Verify: `nvidia-smi` should show both GPUs with 16,380 MiB each.

### CUDA Toolkit

```bash
sudo apt install -y nvidia-cuda-toolkit
```

Verify: `nvcc --version`

### llama.cpp

Built from source with CUDA support:

```bash
cd ~/llama.cpp
git clone https://github.com/ggml-org/llama.cpp.git  # if fresh install
cmake -B build -DGGML_CUDA=ON
cmake --build build --config Release -j$(nproc)
```

Binaries are in `~/llama.cpp/build/bin/`:
- `llama-server` — HTTP server with OpenAI-compatible API
- `llama-cli` — interactive CLI
- `llama-bench` — benchmarking tool

To update llama.cpp:

```bash
cd ~/llama.cpp
git pull
cmake --build build --config Release -j$(nproc)
sudo systemctl restart llama-server
```

### Models

Stored in `~/models/`. Currently downloaded:

| File | Quant | Size |
|------|-------|------|
| `Qwen_Qwen3.5-27B-Q4_K_M.gguf` | Q4_K_M | ~16.5 GB |
| `Qwen_Qwen3.5-27B-Q6_K.gguf` | Q6_K | ~22 GB |

Source: [bartowski/Qwen_Qwen3.5-27B-GGUF](https://huggingface.co/bartowski/Qwen_Qwen3.5-27B-GGUF)

To download a new model:

```bash
cd ~/models
wget https://huggingface.co/<repo>/resolve/main/<filename>.gguf
```

---

## llama-server Service

### Configuration File

**`/etc/llama-server.conf`**

```ini
MODEL_PATH=/home/daryl/models/Qwen_Qwen3.5-27B-Q4_K_M.gguf
GPU_LAYERS=99
HOST=0.0.0.0
PORT=8080
CTX_SIZE=98304
```

| Variable | Description |
|----------|-------------|
| `MODEL_PATH` | Absolute path to the GGUF model file |
| `GPU_LAYERS` | Number of layers to offload to GPU. `99` = all layers |
| `HOST` | Listen address. `0.0.0.0` = accessible from network |
| `PORT` | HTTP port for the API |
| `CTX_SIZE` | Context window in tokens. See VRAM budget table above |

### Service File

**`/etc/systemd/system/llama-server.service`**

```ini
[Unit]
Description=llama.cpp Server
After=network.target

[Service]
Type=simple
User=daryl
EnvironmentFile=/etc/llama-server.conf
ExecStart=/home/daryl/llama.cpp/build/bin/llama-server \
    -m ${MODEL_PATH} \
    -ngl ${GPU_LAYERS} \
    --host ${HOST} \
    --port ${PORT} \
    -c ${CTX_SIZE} \
    --flash-attn on
Restart=on-failure
RestartSec=10

[Install]
WantedBy=multi-user.target
```

### Common Commands

```bash
# Check status
sudo systemctl status llama-server

# View live logs (shows tokens/sec during inference)
sudo journalctl -u llama-server -f

# Restart after config change
sudo systemctl restart llama-server

# Stop the server
sudo systemctl stop llama-server

# Disable auto-start
sudo systemctl disable llama-server
```

### Switching Models

```bash
# Edit the config
sudo nano /etc/llama-server.conf
# Change MODEL_PATH and CTX_SIZE as needed

# Restart to apply
sudo systemctl restart llama-server
```

Remember to adjust `CTX_SIZE` when switching quants — Q4_K_M supports ~98K, Q6_K supports ~32K.

---

## API Usage

The server exposes an OpenAI-compatible API at `http://<VM-IP>:8080/v1/`.

### Chat Completions

```bash
curl http://<VM-IP>:8080/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{
    "messages": [{"role": "user", "content": "Hello!"}],
    "max_tokens": 200
  }'
```

### From Python (using openai library)

```python
from openai import OpenAI

client = OpenAI(base_url="http://<VM-IP>:8080/v1", api_key="unused")

response = client.chat.completions.create(
    model="qwen3.5-27b",  # model name is ignored, uses whatever is loaded
    messages=[{"role": "user", "content": "Hello!"}],
    max_tokens=200,
)
print(response.choices[0].message.content)
```

### Web UI

llama.cpp includes a built-in web UI at `http://<VM-IP>:8080/` for interactive chat.

### Health Check

```bash
curl http://<VM-IP>:8080/health
```

---

## Troubleshooting

### Server won't start

```bash
sudo journalctl -u llama-server --no-pager -n 50
```

Common causes:
- **CUDA OOM**: Reduce `CTX_SIZE` in `/etc/llama-server.conf`
- **Model not found**: Check `MODEL_PATH` is correct
- **Argument errors**: Check llama-server docs for flag changes after updates (e.g., `--flash-attn` now requires `on`/`off`/`auto`)

### nvidia-smi shows no GPUs

- Check that GPUs are still isolated in TrueNAS Advanced Settings
- Check that the VM has GPUs assigned (VM → Edit → GPU section)
- Reboot the VM
- Reinstall drivers: `sudo apt install --reinstall nvidia-driver-580-open`

### VM won't start in TrueNAS

- Check that GPU isolation is still configured after TrueNAS updates
- TrueNAS updates can reset GPU isolation — re-isolate and reboot
- Check VM logs in TrueNAS UI for specific errors

### Slow inference / only one GPU used

- Verify both GPUs are loaded: `nvidia-smi` should show memory usage on both
- llama.cpp auto-splits layers proportionally by free VRAM
- Use `-ts 1,1` flag for forced even split (add to service file ExecStart)

### Disk full

```bash
df -h /
```

To expand: increase the zvol size in TrueNAS Datasets, then inside VM:

```bash
sudo growpart /dev/vda 3
sudo pvresize /dev/vda3
sudo lvextend -l +100%FREE /dev/ubuntu-vg/ubuntu-lv
sudo resize2fs /dev/ubuntu-vg/ubuntu-lv
```

### VM networking issues

- If VM has no internet: try enabling "Trust Guest Filters" on the VM NIC device in TrueNAS
- To access TrueNAS storage from VM: set up a network bridge (see TrueNAS docs for "Accessing NAS from VM")

---

## Expansion Ideas

### Add more models

Drop any GGUF file into `~/models/` and update `/etc/llama-server.conf`.

### Run multiple models simultaneously

Not recommended with current VRAM. Options:
- Run a small model (≤4B) on CPU only (`-ngl 0`) on a separate port
- Add a second service file pointing to a different port and config

### Upgrade to larger models

With 32 GB total VRAM, max practical model sizes:
- Q4_K_M: up to ~70B parameters (would need ~38 GB, partial CPU offload)
- Q8_0: up to ~27B parameters
- For 70B+ models fully on GPU, you'd need additional/larger GPUs

### Performance optimization

- Install `libnccl-dev` and rebuild llama.cpp for better multi-GPU communication
- Use `-sm row` split mode for potentially better multi-GPU utilization
- Use `--cache-type-k q8_0 --cache-type-v q8_0` to compress KV cache and fit more context
- Pin CPU cores to VM for more consistent performance

### Reverse proxy with HTTPS

Install nginx on the VM or on another machine:

```nginx
server {
    listen 443 ssl;
    server_name ai.yourdomain.com;
    ssl_certificate /path/to/cert.pem;
    ssl_certificate_key /path/to/key.pem;
    location / {
        proxy_pass http://localhost:8080;
    }
}
```

---

## Key File Locations

| File | Purpose |
|------|---------|
| `/etc/llama-server.conf` | Server configuration (model path, context size, port) |
| `/etc/systemd/system/llama-server.service` | Systemd service definition |
| `~/llama.cpp/` | llama.cpp source and build |
| `~/llama.cpp/build/bin/` | Compiled binaries |
| `~/models/` | GGUF model files |

## Relevant Documentation

- [TrueNAS 24.10 VM Documentation](https://www.truenas.com/docs/scale/24.10/scaletutorials/virtualization/)
- [TrueNAS GPU Isolation](https://www.truenas.com/docs/scale/24.10/scaletutorials/systemsettings/advanced/managegpuscale/)
- [llama.cpp Build Docs](https://github.com/ggml-org/llama.cpp/blob/master/docs/build.md)
- [llama.cpp Server Docs](https://github.com/ggml-org/llama.cpp/blob/master/examples/server/README.md)
- [Qwen 3.5 27B GGUFs (bartowski)](https://huggingface.co/bartowski/Qwen_Qwen3.5-27B-GGUF)
- [Qwen 3.5 27B GGUFs (unsloth)](https://huggingface.co/unsloth/Qwen3.5-27B-GGUF)
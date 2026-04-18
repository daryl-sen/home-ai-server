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
    ├── Model: Qwen 3.6 35B-A3B (Q4_K_M GGUF) + vision mmproj
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

### VRAM Budget (Qwen 3.6 35B-A3B Q4_K_M + mmproj)

The model file is ~19.9 GiB. Model weights use ~20,117 MiB across both GPUs plus ~273 MiB on CPU. The vision projector (mmproj-BF16) adds ~861 MiB to GPU 0, plus a ~248 MiB vision compute buffer.

This is a hybrid architecture (Gated Delta Net + MoE) — only 10 of 40 layers use traditional KV-cache attention. KV cache scales at roughly **19.5 MiB per 1K tokens**.

| Context Size | KV Cache | GPU 0 Free | GPU 1 Free | Notes |
|-------------|----------|-----------|-----------|-------|
| 60K | ~1,175 MiB | ~2,990 MiB | ~4,508 MiB | Comfortable headroom |
| 130K (current) | ~2,540 MiB | ~2,162 MiB | ~4,000 MiB | Stable, room for vision |
| 150K | ~2,930 MiB | ~1,770 MiB | ~3,610 MiB | Tight on GPU 0 with images |
| 190K (theoretical max) | ~3,710 MiB | ~990 MiB | ~2,830 MiB | Risky, likely OOM with images |

**Note:** GPU 0 is the bottleneck because it hosts the vision encoder and its compute buffer. Image processing causes temporary VRAM spikes on GPU 0.

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

| File | Type | Size |
|------|------|------|
| `Qwen_Qwen3.6-35B-A3B-Q4_K_M.gguf` | Main model (Q4_K_M) | ~19.9 GiB |
| `mmproj-BF16.gguf` | Vision projector (BF16) | ~861 MiB |
| `Qwen_Qwen3.5-27B-Q4_K_M.gguf` | Older model (Q4_K_M) | ~16.5 GB |
| `Qwen_Qwen3.5-27B-Q6_K.gguf` | Older model (Q6_K) | ~22 GB |

Sources:
- Qwen 3.6: [bartowski/Qwen_Qwen3.6-35B-A3B-GGUF](https://huggingface.co/bartowski/Qwen_Qwen3.6-35B-A3B-GGUF)
- Vision projector: [unsloth/Qwen3.6-35B-A3B-GGUF](https://huggingface.co/unsloth/Qwen3.6-35B-A3B-GGUF) (file: `mmproj-BF16.gguf`)
- Qwen 3.5: [bartowski/Qwen_Qwen3.5-27B-GGUF](https://huggingface.co/bartowski/Qwen_Qwen3.5-27B-GGUF)

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
MODEL_PATH=/home/daryl/models/Qwen_Qwen3.6-35B-A3B-Q4_K_M.gguf
MMPROJ_PATH=/home/daryl/models/mmproj-BF16.gguf
GPU_LAYERS=99
HOST=0.0.0.0
PORT=8080
CTX_SIZE=130000
```

| Variable | Description |
|----------|-------------|
| `MODEL_PATH` | Absolute path to the GGUF model file |
| `MMPROJ_PATH` | Absolute path to the vision projector GGUF |
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
    --mmproj ${MMPROJ_PATH} \
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

# Reload service file after editing llama-server.service
sudo systemctl daemon-reload
```

### Switching Models

```bash
# Edit the config
sudo nano /etc/llama-server.conf
# Change MODEL_PATH, MMPROJ_PATH, and CTX_SIZE as needed

# Restart to apply
sudo systemctl restart llama-server
```

When switching models, adjust `CTX_SIZE` based on model size and available VRAM. If the new model doesn't support vision, remove or comment out `MMPROJ_PATH` and remove the `--mmproj` line from the service file.

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

### Vision (Image Input)

```bash
# Using base64-encoded image
curl http://<VM-IP>:8080/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{
    "messages": [{
      "role": "user",
      "content": [
        {"type": "text", "text": "What is in this image?"},
        {"type": "image_url", "image_url": {"url": "data:image/png;base64,<BASE64_DATA>"}}
      ]
    }],
    "max_tokens": 500
  }'
```

### From Python (using openai library)

```python
from openai import OpenAI

client = OpenAI(base_url="http://<VM-IP>:8080/v1", api_key="unused")

response = client.chat.completions.create(
    model="qwen3.6-35b-a3b",  # model name is ignored, uses whatever is loaded
    messages=[{"role": "user", "content": "Hello!"}],
    max_tokens=200,
)
print(response.choices[0].message.content)
```

### Web UI

llama.cpp includes a built-in web UI at `http://<VM-IP>:8080/` for interactive chat. It supports image uploads via the attachment menu.

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
- **Model not found**: Check `MODEL_PATH` and `MMPROJ_PATH` are correct
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

### Vision not working / segfault on image

- Ensure `mmproj-BF16.gguf` is present and the path in the config is correct
- Check logs for "loaded multimodal model" confirmation at startup
- Update llama.cpp to the latest build — vision support for Qwen3.6 is very new
- Reduce `CTX_SIZE` if OOM occurs during image processing (images consume extra VRAM temporarily)

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

### Audio support

llama.cpp has experimental audio model support, but audio models (Ultravox, Voxtral, Qwen3-ASR) are separate models with their own text backbone — they can't be added to Qwen3.6 as a plugin. To add audio, run a second llama-server instance on CPU with a small audio model like Qwen3-ASR 1.7B on a separate port.

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
| `/etc/llama-server.conf` | Server configuration (model path, mmproj path, context size, port) |
| `/etc/systemd/system/llama-server.service` | Systemd service definition |
| `~/llama.cpp/` | llama.cpp source and build |
| `~/llama.cpp/build/bin/` | Compiled binaries |
| `~/models/` | GGUF model files and vision projector |

## Relevant Documentation

- [TrueNAS 24.10 VM Documentation](https://www.truenas.com/docs/scale/24.10/scaletutorials/virtualization/)
- [TrueNAS GPU Isolation](https://www.truenas.com/docs/scale/24.10/scaletutorials/systemsettings/advanced/managegpuscale/)
- [llama.cpp Build Docs](https://github.com/ggml-org/llama.cpp/blob/master/docs/build.md)
- [llama.cpp Server Docs](https://github.com/ggml-org/llama.cpp/blob/master/examples/server/README.md)
- [llama.cpp Multimodal Docs](https://github.com/ggml-org/llama.cpp/blob/master/docs/multimodal.md)
- [Qwen 3.6 35B-A3B (HuggingFace)](https://huggingface.co/Qwen/Qwen3.6-35B-A3B)
- [Qwen 3.6 35B-A3B GGUFs (bartowski)](https://huggingface.co/bartowski/Qwen_Qwen3.6-35B-A3B-GGUF)
- [Qwen 3.6 35B-A3B GGUFs (unsloth)](https://huggingface.co/unsloth/Qwen3.6-35B-A3B-GGUF)

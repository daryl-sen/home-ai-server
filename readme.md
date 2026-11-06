# home-ai-server

Context and setup for AI agents that manage a self-hosted LLM inference server: `llama.cpp` (router mode) on a Linux VM with 2× RTX 4060 Ti, serving two Qwen models via an OpenAI-compatible API.

The repo is the install location (the service reads its config from `~/home-ai-server/`) and `docs/history.md` keeps the full build + change log, so an agent handed this repo can maintain the setup, answer questions, make improvements — or rebuild the server from scratch if needed.

---

## What's in here

| Path | Purpose |
|------|---------|
| `AGENTS.md` | Orientation for AI agents: what's where, quick commands, gotchas. Read this first. |
| `model-switching/` | The llama-server service: systemd unit, per-model config (`models.preset.ini`, router mode), one-shot installer. See [`model-switching/README.md`](model-switching/README.md). |
| `docs/history.md` | Build log + change log: TrueNAS + dual-GPU passthrough, BIOS, VRAM budgeting, CUDA/llama.cpp installs, upgrade and router-migration history. |
| `docs/opencode-setup.md` | Client config for using the server from opencode (this workstation). |
| `common-commands.md` | Copy-paste commands: service, logs, model status/switching, API. |
| `personalize.sh` | One-shot placeholder substitution (`<user>`, `<server-ip>`, etc.) so docs and scripts reference your actual values. |

---

## Assumptions

- A Linux server (Ubuntu 24.04 tested) reachable over SSH, with at least one NVIDIA GPU.
- `llama.cpp` built with CUDA at `~/llama.cpp/build/bin/llama-server` (v0.9.0 or newer for router mode).
- GGUF model files placed flat in `~/models/` on the server.
- This repo cloned at `~/home-ai-server` on the server.

If your paths differ, edit `model-switching/models.preset.ini` and `model-switching/llama-server.service` to match.

---

## Quick start (new server)

On the **server**:

```bash
git clone <this-repo> ~/home-ai-server
cd ~/home-ai-server
./personalize.sh                                    # fill in user + server IP
./model-switching/install.sh                        # install the systemd service, start llama-server
```

That's it — `llama-server` is now running in router mode on port 8080 (27b auto-loads) and will start on boot. Switch models from the web UI (`http://<server-ip>:8080`) or the API (`POST /models/load`).

For the full from-scratch server build (VM, GPU passthrough, BIOS, CUDA, llama.cpp): [`docs/history.md`](docs/history.md).

On the **workstation** (optional, for using the server with opencode): see [`docs/opencode-setup.md`](docs/opencode-setup.md).

---

## Background

The original motivation was running a 35B-parameter Qwen MoE model with vision on a homelab TrueNAS box passing two RTX 4060 Ti's into a Ubuntu VM. The build log for that specific setup lives in [`docs/history.md`](docs/history.md) — hardware, BIOS, GPU passthrough, VRAM budgeting math, and the original `/etc/llama-server.conf` based service definition. The model-switching tooling here grew out of wanting to swap between a more accurate dense model and a faster (but less accurate) MoE model without manually editing config files and bouncing the service. Since 2026-11-06 llama.cpp's built-in router mode does that natively instead (see `docs/history.md` → "Upgrade Log").

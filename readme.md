# home-ai-server

Tooling for running a self-hosted LLM inference server with `llama.cpp` on a Linux box (bare metal or VM), plus helpers for connecting to it from a workstation.

This repo doesn't ship llama.cpp or any models — it provides the glue around a llama.cpp install you build yourself: a one-shot installer, a model-switcher, and a workstation-side connector for using the server with Claude Code over SSH.

---

## What's in here

| Path | Purpose |
|------|---------|
| `model-switching/` | Systemd user-service + `switch-model` script to run `llama-server` and hot-swap between two model configs with a single command. Releases GPU memory between switches. See [`model-switching/README.md`](model-switching/README.md). |
| `scripts/setup` | First-time workstation → server SSH bootstrap (key gen, `ssh_config` entry, `ssh-copy-id`). |
| `scripts/claude-vm` | Workstation helper to SSH into the server, attach a `tmux` session, and launch Claude Code in a chosen project directory. Supports a `--local` mode that points Claude at the local llama.cpp endpoint. |
| `personalize.sh` | One-shot placeholder substitution (`<user>`, `<server-ip>`, etc.) so docs and scripts reference your actual values. |
| `docs/history.md` | The author's original homelab build log — TrueNAS + dual-GPU passthrough, BIOS settings, VRAM budgeting, NVIDIA/CUDA install steps. Useful as a reference build but not required. |

---

## Assumptions

- A Linux server (Ubuntu 24.04 tested) reachable over SSH, with at least one NVIDIA GPU.
- `llama.cpp` built with CUDA at `~/llama.cpp/build/bin/llama-server` on the server.
- GGUF model files placed in `~/models/` on the server.
- This repo cloned at `~/home-ai-server` on the server.

If your paths differ, edit `model-switching/configs/*.conf` and `model-switching/llama-server.service` to match.

---

## Quick start

On the **server**:

```bash
git clone <this-repo> ~/home-ai-server
cd ~/home-ai-server
./personalize.sh                                    # fill in user + server IP
./model-switching/install.sh 35b                    # install the systemd service, start llama-server
```

That's it — `llama-server` is now running on port 8080 and will start on boot. Switch models with:

```bash
~/home-ai-server/model-switching/switch-model 27b
```

On the **workstation** (optional, for using the server with Claude Code):

```bash
./scripts/setup           # interactive SSH bootstrap
./scripts/claude-vm       # pick a project on the server and launch Claude Code in it
./scripts/claude-vm --local   # same, but point Claude at the local llama.cpp endpoint
```

---

## Background

The original motivation was running a 35B-parameter Qwen MoE model with vision on a homelab TrueNAS box passing two RTX 4060 Ti's into a Ubuntu VM. The build log for that specific setup lives in [`docs/history.md`](docs/history.md) — hardware, BIOS, GPU passthrough, VRAM budgeting math, and the original `/etc/llama-server.conf` based service definition. The model-switching tooling here grew out of wanting to swap between a fast dense model and a slower, more accurate MoE model without manually editing config files and bouncing the service.

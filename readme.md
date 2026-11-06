# home-ai-server

Tooling for running a self-hosted LLM inference server with `llama.cpp` on a Linux box (bare metal or VM), plus helpers for connecting to it from a workstation.

This repo doesn't ship llama.cpp or any models — it provides the glue around a llama.cpp install you build yourself: a one-shot installer, a model-switcher, and a workstation-side connector for using the server with Claude Code over SSH.

---

## What's in here

| Path | Purpose |
|------|---------|
| `model-switching/` | Systemd user-service + `switch-model` script running `llama-server` in **router mode** — both models known to one service, one loaded at a time, switched by API call (no restart; old model purged before the new one loads). See [`model-switching/README.md`](model-switching/README.md). |
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

If your paths differ, edit `model-switching/models.preset.ini` and `model-switching/llama-server.service` to match.

---

## Quick start

On the **server**:

```bash
git clone <this-repo> ~/home-ai-server
cd ~/home-ai-server
./personalize.sh                                    # fill in user + server IP
./model-switching/install.sh                        # install the systemd service, start llama-server
```

That's it — `llama-server` is now running in router mode on port 8080 (27b auto-loads) and will start on boot. Switch models with:

```bash
~/home-ai-server/model-switching/switch-model 27b   # or 35b — API call, no restart
```

On the **workstation** (optional, for using the server with Claude Code):

```bash
./scripts/setup           # interactive SSH bootstrap
./scripts/claude-vm       # pick a project on the server and launch Claude Code in it
./scripts/claude-vm --local   # same, but point Claude at the local llama.cpp endpoint
```

---

## Background

The original motivation was running a 35B-parameter Qwen MoE model with vision on a homelab TrueNAS box passing two RTX 4060 Ti's into a Ubuntu VM. The build log for that specific setup lives in [`docs/history.md`](docs/history.md) — hardware, BIOS, GPU passthrough, VRAM budgeting math, and the original `/etc/llama-server.conf` based service definition. The model-switching tooling here grew out of wanting to swap between a more accurate dense model and a faster (but less accurate) MoE model without manually editing config files and bouncing the service. Since 2026-11-06 it uses llama.cpp's built-in router mode instead of restarting the service per switch (see `docs/history.md` → "Upgrade Log").

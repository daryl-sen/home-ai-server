# AGENTS.md — context for AI agents working on this repo

## What this repo is

Context + setup for AI agents that manage a home AI server: `llama.cpp` (router mode) in a Linux VM with 2× RTX 4060 Ti, serving two Qwen models via an OpenAI-compatible API. The goal: an agent handed this repo should be able to perform maintenance, answer questions about the setup, make improvements, and — if needed — rebuild the server from scratch. `docs/history.md` is the build/change log (debugging + from-scratch reference).

## The server

- **SSH alias:** `local-ai` (→ `100.89.219.6`, user `daryl`, key `~/.ssh/id_ed25519`)
- **OS:** Ubuntu 24.04 VM (TrueNAS) with 2× RTX 4060 Ti 16GB (32GB VRAM total) passed through
- **llama.cpp:** `~/llama.cpp` (detached HEAD, currently v0.9.0), binaries in `~/llama.cpp/build/bin/`
- **Models:** `~/models/` — flat `.gguf` files; model ID = filename without `.gguf`
  - 27b: `Qwen3.8-27B-Q4_K_M` (dense, more accurate, boot default)
  - 35b: `Qwen_Qwen3.6-35B-A3B-Q4_K_M` (MoE, faster)
  - Both train at 256K context natively; the server runs them pinned lower (see preset) to leave vision headroom
- **Service:** user-level systemd `llama-server` (no sudo) — `~/.config/systemd/user/llama-server.service` — llama.cpp **router mode** (since 2026-11-06): one service knows both models, one resident at a time (`--models-max 1`); a switch purges the old model then loads the new (~40–60s, no service restart)
- **API:** `http://100.89.219.6:8080/v1/` (OpenAI-compatible; the `model` field is required). **Web UI:** `http://100.89.219.6:8080` — switch models from there (model list → load).
- **Per-model config:** `model-switching/models.preset.ini` (single source of truth; `[*]` = shared flags) — hot reload: `curl "http://100.89.219.6:8080/models?reload=1"`
- **Client:** this workstation's opencode (`~/.config/opencode/opencode.json`) points at the API; both models are listed so `/model` switches between them (first request after a switch waits for the ~40–60s load)

## Quick commands

```bash
ssh local-ai 'systemctl --user status llama-server'
ssh local-ai 'journalctl --user -u llama-server -f'
ssh local-ai 'curl -s http://100.89.219.6:8080/models | jq -r ".data[] | .id + \"  [\" + .status.value + \"]\""'
# load / unload a model:
ssh local-ai 'curl -s -X POST http://100.89.219.6:8080/models/load -H "Content-Type: application/json" -d "{\"model\":\"Qwen_Qwen3.6-35B-A3B-Q4_K_M\"}"'
# chat test (from the workstation):
curl -s http://100.89.219.6:8080/v1/chat/completions -d '{"model":"Qwen3.8-27B-Q4_K_M","messages":[{"role":"user","content":"ping"}],"max_tokens":100}'
```

Qwen3 models are thinking models — small `max_tokens` is consumed by reasoning, leaving `content` empty; use ≥100–200 for tests.

## Gotchas

- Requests **must** send the exact model ID (missing/unknown → 400). Temporary aliases `my-model`/`llama-cpp/my-model` → 27b exist for pre-migration clients; remove from the preset once unused.
- A client that keeps sending the other model's name re-triggers a load of it on its next request (purges the currently loaded model).
- `ctx-size` is pinned in the preset deliberately (VRAM budget: vision spikes on GPU 0). `--fit` caps at the 256K trained size and only shrinks — don't "fix" the pins without re-reading the VRAM table in `docs/history.md`.
- llama.cpp binaries carry an absolute `RUNPATH=/home/daryl/llama.cpp/build/bin` — rollbacks are full-directory restores only; see "Upgrade Log" in `docs/history.md`.
- The router listens on `0.0.0.0` with no API key — LAN/Tailscale only; never expose it.

## Rebuilding from scratch

`docs/history.md` holds the full build log: hardware, TrueNAS + GPU passthrough, BIOS settings, VRAM budgeting, NVIDIA/CUDA install, llama.cpp build. Service install: `model-switching/install.sh`. Client config: `docs/opencode-setup.md`.

## Rollback points

- llama.cpp v0.8-era binaries: `~/llama-server-bin-backup-pre-v090` (restore into `~/llama.cpp/build/bin`)
- Pre-router service unit: `~/.llama-server.service.pre-router.bak` (+ legacy configs restorable from git history)
- Details: `docs/history.md` → "Upgrade Log"

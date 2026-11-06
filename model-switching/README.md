# llama-server service (llama.cpp router mode)

The AI server runs a single `llama-server` process in llama.cpp **router mode** (since 2026-11-06): one service knows both models, one loaded at a time. Models are loaded on demand via the built-in web UI or the API — no service restart.

The repo is the install location: files are read in place from `~/home-ai-server/model-switching/`.

## How it works

A user-level systemd service (`llama-server`, user `daryl`, no sudo):

```
llama-server --models-dir ~/models
             --models-preset ~/home-ai-server/model-switching/models.preset.ini
             --models-max 1 --host 0.0.0.0 --port 8080 --webui-mcp-proxy
```

- The **router** (the service) never touches the GPU. Each model runs in its own child process on a private port; OpenAI-compatible requests are routed by the `model` field.
- `--models-max 1`: only one model resident at a time (both models don't fit in 32GB VRAM). A request for the unloaded model triggers a load: the loaded model is **purged first**, then the new one loads (~40–60s), and the request waits. A model that is mid-request is never unloaded.
- `load-on-startup = true` in the 27b preset → 27b auto-loads at boot.
- **Model IDs** are the flat `.gguf` filenames without extension: `Qwen3.8-27B-Q4_K_M`, `Qwen_Qwen3.6-35B-A3B-Q4_K_M`. Requests must send the exact ID (or an alias) — missing/unknown → 400.
- Per-model flags (ctx, KV cache type, mmproj) live in `models.preset.ini`; shared flags in the `[*]` section. Preset edits apply **without restart**: `curl "http://<server>:8080/models?reload=1"`.
- Model child processes share the journal with the router.

```
~/home-ai-server/model-switching/
├── models.preset.ini        (per-model flags — the single source of truth)
├── llama-server.service     (systemd user unit, router mode)
├── install.sh               (one-shot bootstrap)
└── README.md
```

## Switching models

Use the **built-in web UI**: open `http://<server>:8080`, pick the model from the model list and load it. The old model is purged and the new one loads (~40–60s); the API stays up throughout.

From the command line (equivalent):

```bash
# status
curl -s http://<server>:8080/models | jq -r '.data[] | .id + "  [" + .status.value + "]"'

# load / unload
curl -s -X POST http://<server>:8080/models/load  -H 'Content-Type: application/json' \
     -d '{"model":"Qwen_Qwen3.6-35B-A3B-Q4_K_M"}'
curl -s -X POST http://<server>:8080/models/unload -H 'Content-Type: application/json' \
     -d '{"model":"Qwen3.8-27B-Q4_K_M"}'
```

Note: a client that keeps sending the other model's name re-triggers a load of that model on its next request (with `--models-max 1` this purges the one you just loaded).

## Changing per-model flags / adding a model

1. Edit `models.preset.ini` (per-model section, or `[*]` for shared flags). Keys are CLI argument names (`ctx-size`, `cache-type-k`, `mmproj`, `ngl`, `flash-attn`, ...). Unknown keys are a hard error.
2. Apply without restart: `curl "http://<server>:8080/models?reload=1"`.
3. New model: drop the `.gguf` flat into `~/models/`, add a section named exactly after the filename (without `.gguf`), then `?reload=1`.

Notes:
- **Context sizes are pinned deliberately** (`ctx-size`): both models train at 256K natively, but the pins (131072 q8_0 KV for 27b, 130000 f16 KV for 35b) leave headroom for the vision encoder on GPU 0, which spikes temporarily on image processing. `--fit` (only active when `ctx-size` is unset) caps at the 256K trained size and only shrinks to fit a 1GiB margin per GPU — it would spend exactly the headroom the pins protect. See the VRAM budget table in `docs/history.md` before raising them.
- Vision: flat `mmproj*.gguf` files in `~/models/` are **not** auto-attached — each model must name its projector in the preset (`mmproj = /abs/path`).
- The router's memory measurements don't include mmproj — irrelevant with `--models-max 1` (the old model is fully purged before the new one loads).

## First-time setup (new server)

Prerequisites on the Ubuntu server:
- This repo cloned at `~/home-ai-server`
- `llama.cpp` built with CUDA at `~/llama.cpp/build/bin/llama-server` (v0.9.0 or newer for router mode — build instructions in `docs/history.md`)
- GGUF model files present flat in `~/models/` matching the section names in `models.preset.ini`

Then:

```bash
~/home-ai-server/model-switching/install.sh
```

`install.sh` does: copies `llama-server.service` into `~/.config/systemd/user/`, runs `sudo loginctl enable-linger $USER` (one-time, so the service starts at boot without login), and enables + starts the service — 27b loads automatically.

For the full from-scratch server build (TrueNAS VM, GPU passthrough, BIOS, CUDA, llama.cpp): [`docs/history.md`](../docs/history.md).

## Logs and debugging

```bash
journalctl --user -u llama-server -f               # live logs (router + model children)
journalctl --user -u llama-server --no-pager -n 50 # recent failures
systemctl --user status llama-server               # service state
```

A crashed model child does **not** take down the router; it is reported in the logs and the model returns to `unloaded` (reloads on next request).

## Persistence across reboots

- 27b auto-loads via `load-on-startup` (edit the preset to make 35b the boot model instead).
- `loginctl enable-linger` (set during install) makes the user service start at boot.

## Rollback to pre-router (single-model) mode

The pre-migration (2026-11-06) unit is backed up on the server:

```bash
cp ~/.llama-server.service.pre-router.bak ~/.config/systemd/user/llama-server.service
```

The legacy per-model configs were removed from the repo after the migration (still present on the server; restorable from git history, e.g. `git checkout 8d3b499 -- model-switching/configs`). Restore them plus an `active.conf` symlink pointing at one, then:

```bash
systemctl --user daemon-reload && systemctl --user restart llama-server
```

## Caveats

- The router listens on `0.0.0.0` with no API key (LAN/Tailscale only). llama.cpp warns "router mode enabled — do not expose to untrusted environments"; set `--api-key` if you ever expose it publicly.
- **Temporary aliases:** the 27b preset carries `alias = my-model,llama-cpp/my-model` so pre-migration clients (which send `my-model`) keep working. Remove that line + `?reload=1` once all clients use the canonical model IDs.
- `?reload=1` unloads and reloads any model whose preset changed — brief unavailability for that model.

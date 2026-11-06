# Model Switching (27B Dense ↔ 35B-A3B MoE) — router mode

One `llama-server` process (llama.cpp **router mode**, since 2026-11-06) knows both models and loads them on demand. Switching is an API call — **no service restart** — takes ~40–60s (old model purged, new model loaded).

The repo itself is the install location — files are read in-place from `~/home-ai-server/model-switching/`.

---

## How It Works

A user-level systemd service runs `llama-server` in router mode:

```
llama-server --models-dir ~/models \
             --models-preset ~/home-ai-server/model-switching/models.preset.ini \
             --models-max 1 --host 0.0.0.0 --port 8080 --webui-mcp-proxy
```

- The **router** (the service) never touches the GPU. Each model runs in its own child process on a private port; OpenAI-compatible requests are routed by the `model` field.
- `--models-max 1`: only one model resident at a time (2× ~18–20GB models don't fit in 32GB VRAM). When a request targets the other model, the loaded one is **purged first**, then the new one loads; the triggering request waits for the load. A model that is mid-request is never unloaded.
- `load-on-startup = true` in the 27b preset → 27b auto-loads at boot.
- **Model IDs** are the flat `.gguf` filenames without extension: `Qwen3.8-27B-Q4_K_M` and `Qwen_Qwen3.6-35B-A3B-Q4_K_M`. Clients must send the exact ID (or an alias) — a missing or unknown name is a 400.
- Per-model flags (ctx, KV cache type, mmproj) live in `models.preset.ini`; shared flags in the `[*]` section. Preset edits apply **without restart**: `curl "http://<server>:8080/models?reload=1"`.
- Each model's child process logs into the same journal as the router.

```
~/home-ai-server/model-switching/
├── models.preset.ini        (per-model flags — the single source of truth)
├── switch-model             (server-side switcher: load + status)
├── llama-server.service     (systemd user unit, router mode)
├── install.sh               (one-shot bootstrap)
├── configs/                 (LEGACY pre-router configs, kept for rollback reference)
└── README.md
```

---

## First-Time Setup

Prerequisites on the Ubuntu server:
- Repo cloned at `~/home-ai-server`
- `llama.cpp` built at `~/llama.cpp/build/bin/llama-server` (v0.9.0 or newer for router mode)
- GGUF model files present flat in `~/models/` matching the section names in `models.preset.ini` (edit that file if your filenames differ)

Then:

```bash
~/home-ai-server/model-switching/install.sh
```

`install.sh` does:
1. Makes `switch-model` executable.
2. Copies `llama-server.service` into `~/.config/systemd/user/`.
3. Runs `sudo loginctl enable-linger $USER` (one-time) so the service starts at boot without login.
4. Enables and starts the systemd user service — 27b loads automatically.

When it finishes, the server is on `http://<server-ip>:8080/v1/`.

### Optional: convenience alias

```bash
echo 'alias switch-model=~/home-ai-server/model-switching/switch-model' >> ~/.bashrc
```

---

## Switching Models

On the **server**:

```bash
~/home-ai-server/model-switching/switch-model 27b       # dense, more accurate (default)
~/home-ai-server/model-switching/switch-model 35b       # MoE, faster
~/home-ai-server/model-switching/switch-model status    # which model is loaded
```

From the **workstation** (also re-points this machine's opencode at the new model):

```bash
./scripts/switch-ai-model 27b | 35b | status
```

Under the hood a switch is `POST /models/load` with the target model ID; the script then polls `GET /models` until `status.value == "loaded"`. The API stays up the whole time; only the model changes.

### Other router endpoints

```bash
curl -s http://<server>:8080/models                      # list + status of all models
curl -s -X POST http://<server>:8080/models/unload \
     -H 'Content-Type: application/json' \
     -d '{"model":"Qwen3.8-27B-Q4_K_M"}'                 # unload a model
curl -s "http://<server>:8080/models?reload=1"           # re-read models.preset.ini
```

---

## Changing Per-Model Flags / Adding a Model

1. Edit `models.preset.ini` (per-model section, or `[*]` for shared flags). Keys are CLI argument names (`ctx-size`, `cache-type-k`, `mmproj`, `ngl`, `flash-attn`, ...). Unknown keys are a hard error.
2. Apply without restart: `curl "http://<server>:8080/models?reload=1"`. A model whose preset changed is reloaded on next use.
3. New model: drop the `.gguf` flat into `~/models/`, add a section named exactly after the filename (without `.gguf`), then `?reload=1`.

Notes:
- Vision: flat `mmproj*.gguf` files in `~/models/` are **not** auto-attached — each model must name its projector in the preset (`mmproj = /abs/path`).
- `ctx-size` pins the context (disables `--fit` auto-sizing) — intentional here.
- The router's memory measurements don't include mmproj — irrelevant with `--models-max 1` (the old model is fully purged before the new one loads), but size `--models-memory-margin` generously if you ever allow 2 resident.

---

## Logs and Debugging

```bash
journalctl --user -u llama-server -f               # live logs (router + model children)
journalctl --user -u llama-server --no-pager -n 50 # recent failures
systemctl --user status llama-server               # service state
```

A crashed model child does **not** take down the router; it is reported in the logs and the model returns to `unloaded` (reload on next request).

---

## Persistence Across Reboots

- 27b auto-loads via `load-on-startup` (edit the preset to make 35b the boot model instead).
- `loginctl enable-linger` (set during install) makes the user service start at boot.

---

## Rollback to pre-router (single-model) mode

The pre-migration (2026-11-06) unit is backed up on the server and the legacy `active.conf` symlink + `configs/` are intact:

```bash
cp ~/.llama-server.service.pre-router.bak ~/.config/systemd/user/llama-server.service
systemctl --user daemon-reload
systemctl --user restart llama-server
```

---

## Caveats

- The router listens on `0.0.0.0` with no API key (same exposure as before the migration — LAN/Tailscale only). llama.cpp warns "router mode enabled — do not expose to untrusted environments"; set `--api-key` if you ever expose it publicly.
- **Temporary aliases:** the 27b preset carries `alias = my-model,llama-cpp/my-model` so the pre-migration opencode session (which sends `my-model`) keeps working. Remove that line + `?reload=1` once all clients use the canonical model IDs.
- `?reload=1` unloads and reloads any model whose preset changed — brief unavailability for that model.

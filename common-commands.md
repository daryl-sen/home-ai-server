# Common commands (run on the AI server — `ssh local-ai`)

The llama server runs as a **user-level** systemd service (`llama-server`, user `daryl`) — no `sudo` needed. It runs in llama.cpp **router mode**: one service knows both models, but only one is loaded at a time (`--models-max 1`).

## Model switching

Preferred: the **web UI** at `http://100.89.219.6:8080` — pick the model you want from the model list and load it. The old model is purged and the new one loads (~40–60s); the API stays up throughout.

From the command line:

```bash
# status
curl -s http://100.89.219.6:8080/models | jq -r '.data[] | .id + "  [" + .status.value + "]"'

# load / unload
curl -s -X POST http://100.89.219.6:8080/models/load  -H 'Content-Type: application/json' \
     -d '{"model":"Qwen_Qwen3.6-35B-A3B-Q4_K_M"}'
curl -s -X POST http://100.89.219.6:8080/models/unload -H 'Content-Type: application/json' \
     -d '{"model":"Qwen3.8-27B-Q4_K_M"}'
```

Per-model flags (ctx, KV cache type, mmproj) live in `model-switching/models.preset.ini`. Edit it, then apply **without** a restart:

```bash
curl "http://100.89.219.6:8080/models?reload=1"
```

## Service management

```bash
# Status
systemctl --user status llama-server

# Restart
systemctl --user restart llama-server

# Live logs
journalctl --user -u llama-server -f

# Today's logs
journalctl --user -u llama-server --since today

# Logs from the previous run (after a crash/restart)
journalctl --user -u llama-server -b -1
```

## API

```bash
curl -s http://100.89.219.6:8080/health
```

Chat/completion requests **must** set `model` to the exact model ID (missing or unknown → 400):

```bash
curl -s http://100.89.219.6:8080/v1/chat/completions \
  -H 'Content-Type: application/json' \
  -d '{"model":"Qwen3.8-27B-Q4_K_M","messages":[{"role":"user","content":"hi"}],"max_tokens":100}'
```

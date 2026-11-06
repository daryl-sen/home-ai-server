# Common commands (run on the AI server — `ssh local-ai`)

The llama server runs as a **user-level** systemd service (`llama-server`, user `daryl`) — no `sudo` needed. It runs in llama.cpp **router mode**: one service knows both models, but only one is loaded at a time (`--models-max 1`).

## Model switching

```bash
# Switch model (loads the new one, purges the old; ~40-60s, no service restart)
~/home-ai-server/model-switching/switch-model 27b   # dense, more accurate (default)
~/home-ai-server/model-switching/switch-model 35b   # MoE, faster

# Check which model is loaded
~/home-ai-server/model-switching/switch-model status
```

From the workstation (also updates this machine's opencode model):

```bash
./scripts/switch-ai-model 27b | 35b | status
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
curl -s http://100.89.219.6:8080/models | jq -r '.data[] | .id + "  [" + .status.value + "]"'
# router management:
curl -s -X POST http://100.89.219.6:8080/models/load  -H 'Content-Type: application/json' -d '{"model":"Qwen_Qwen3.6-35B-A3B-Q4_K_M"}'
curl -s -X POST http://100.89.219.6:8080/models/unload -H 'Content-Type: application/json' -d '{"model":"Qwen3.8-27B-Q4_K_M"}'
```

Chat/completion requests **must** set `model` to the exact model ID (missing or unknown → 400):

```bash
curl -s http://100.89.219.6:8080/v1/chat/completions \
  -H 'Content-Type: application/json' \
  -d '{"model":"Qwen3.8-27B-Q4_K_M","messages":[{"role":"user","content":"hi"}],"max_tokens":16}'
```

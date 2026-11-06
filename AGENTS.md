# AGENTS.md — context for AI agents working on this repo

## AI Server SSH
- **SSH alias:** `local-ai` (→ `100.89.219.6`, user `daryl`, key `~/.ssh/id_ed25519`)
- **Remote repo path:** `~/home-ai-server`
- **Model switching:** llama.cpp **router mode** (since 2026-11-06) — one service, both models known, one resident at a time (`--models-max 1`); a switch purges the old model then loads the new (~40-60s, no service restart)
- **Models:** 27b (`Qwen3.8-27B-Q4_K_M`, dense, more accurate, boot default) ↔ 35b (`Qwen_Qwen3.6-35B-A3B-Q4_K_M`, MoE, faster)

## Quick commands
- Switch to 27b (accurate): `./scripts/switch-ai-model 27b` (workstation — also updates opencode's model)
- Switch to 35b (fast):     `./scripts/switch-ai-model 35b`
- From the server:          `ssh local-ai ~/home-ai-server/model-switching/switch-model 35b`
- Check loaded model:       `ssh local-ai ~/home-ai-server/model-switching/switch-model status`

## API
- Endpoint: `http://100.89.219.6:8080/v1/`
- Router mode: requests **must** send the exact model ID (`Qwen3.8-27B-Q4_K_M` or `Qwen_Qwen3.6-35B-A3B-Q4_K_M`); missing/unknown → 400
- Model list/status: `GET /models` (`status.value`: `unloaded`/`loading`/`loaded`)
- Temporary aliases `my-model` and `llama-cpp/my-model` route to 27b (pre-migration clients) — remove from the preset once unused
- Chat via curl: `curl -s http://100.89.219.6:8080/v1/chat/completions -d '{"model":"Qwen3.8-27B-Q4_K_M","messages":[...]}'`

## Per-model config
- Single source of truth: `model-switching/models.preset.ini` (per-model ctx/KV/mmproj; shared flags in `[*]`)
- Edit + apply without restart: `curl "http://100.89.219.6:8080/models?reload=1"`

## Service (on local-ai)
- User systemd service `llama-server` (no sudo): `~/.config/systemd/user/llama-server.service` (router mode)
- Pre-migration rollback: `cp ~/.llama-server.service.pre-router.bak ~/.config/systemd/user/llama-server.service && systemctl --user daemon-reload && systemctl --user restart llama-server`
- Logs: `journalctl --user -u llama-server -f` (router + model children share the journal)

## llama.cpp build (on local-ai)
- **Current:** v0.9.0 (b12110, commit `cd959bae9`) — upgraded 2026-11-05 from b10819 (Sep 5)
- Router mode verified working in this build (`--models-dir`/`--models-preset`/`--models-max`, presets, aliases, `load-on-startup`, `?reload=1`)
- Repo: `~/llama.cpp` (detached HEAD at the v0.9.0 tag), binaries in `~/llama.cpp/build/bin/`
- Pre-upgrade backup (rollback point): `~/llama-server-bin-backup-pre-v090`
- Safe upgrade procedure, rollback steps, and the RUNPATH gotcha: `docs/history.md` → "Upgrade Log"

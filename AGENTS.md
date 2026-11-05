# AGENTS.md — context for AI agents working on this repo

## AI Server SSH
- **SSH alias:** `local-ai` (→ `100.89.219.6`, user `daryl`, key `~/.ssh/id_ed25519`)
- **Remote repo path:** `~/home-ai-server`
- **Model switching script:** `~/home-ai-server/model-switching/switch-model`
- **Models:** 27b (`Qwen3.8-27B-Q4_K_M.gguf`, dense, more accurate) ↔ 35b (`Qwen_Qwen3.6-35B-A3B-Q4_K_M.gguf`, MoE, faster)

## Quick commands
- Switch to 27b (accurate): `ssh local-ai ~/home-ai-server/model-switching/switch-model 27b`
- Switch to 35b (fast):     `ssh local-ai ~/home-ai-server/model-switching/switch-model 35b`
- Check current model:      `ssh local-ai ~/home-ai-server/model-switching/switch-model status`
- Convenience script:       `./scripts/switch-ai-model 35b`

## llama.cpp build (on local-ai)
- **Current:** v0.9.0 (b12110, commit `cd959bae9`) — upgraded 2026-11-05 from b10819 (Sep 5)
- Repo: `~/llama.cpp` (detached HEAD at the v0.9.0 tag), binaries in `~/llama.cpp/build/bin/`
- Pre-upgrade backup (rollback point): `~/llama-server-bin-backup-pre-v090`
- Safe upgrade procedure, rollback steps, and the RUNPATH gotcha: `docs/history.md` → "Upgrade Log"

## API
- Endpoint: `http://100.89.219.6:8080/v1/`

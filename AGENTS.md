# AGENTS.md — context for AI agents working on this repo

## AI Server SSH
- **SSH alias:** `local-ai` (→ `100.89.219.6`, user `daryl`, key `~/.ssh/id_ed25519`)
- **Remote repo path:** `~/home-ai-server`
- **Model switching script:** `~/home-ai-server/model-switching/switch-model`
- **Models:** 27b (fast dense) ↔ 35b (MoE, more accurate)

## Quick commands
- Switch to 35b (accurate): `ssh local-ai ~/home-ai-server/model-switching/switch-model 35b`
- Switch to 27b (fast):    `ssh local-ai ~/home-ai-server/model-switching/switch-model 27b`
- Check current model:      `ssh local-ai ~/home-ai-server/model-switching/switch-model status`
- Convenience script:       `./scripts/switch-ai-model 35b`

## API
- Endpoint: `http://100.89.219.6:8080/v1/`

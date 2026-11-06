# Open Code setup for the local llama.cpp server

Config file: `~/.config/opencode/opencode.json`

The server runs in llama.cpp **router mode**, so the model key must be the exact model ID (filename without `.gguf`). The switcher (`./scripts/switch-ai-model`) rewrites this key when you switch models.

Content (27b active):

```json
{
  "$schema": "https://opencode.ai/config.json",
  "provider": {
    "llama-cpp": {
      "npm": "@ai-sdk/openai-compatible",
      "name": "llama.cpp (local)",
      "options": {
        "baseURL": "http://100.89.219.6:8080/v1"
      },
      "models": {
        "Qwen3.8-27B-Q4_K_M": {
          "name": "local model (27b)",
          "tool_call": true,
          "limit": {
            "context": 130000,
            "output": 8192
          },
          "modalities": {
            "input": ["text", "image"],
            "output": ["text"]
          }
        }
      }
    }
  },
  "mcp": {
    "searxng": {
      "type": "local",
      "command": ["npx", "-y", "mcp-searxng"],
      "environment": {
        "SEARXNG_URL": "http://home-server.goblin-stairs.ts.net:30053"
      }
    }
  }
}
```

## Model switching

```bash
./scripts/switch-ai-model 35b    # loads the model on the server AND rewrites the key above
```

- An **already-running** opencode session keeps sending the model name it started with; the router auto-loads it on demand (with `--models-max 1` that purges whichever model is active). Start a new session to pick up the config change cleanly.
- The pre-migration model key was `my-model` (ignored in single-model mode). A temporary preset alias (`my-model`, `llama-cpp/my-model` → 27b) keeps any stale client working until it is removed from `model-switching/models.preset.ini`.

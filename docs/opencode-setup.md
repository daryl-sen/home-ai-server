# Open Code setup for the local llama.cpp server

Config file: `~/.config/opencode/opencode.json`

The server runs in llama.cpp **router mode**, so the model keys must be the exact model IDs (filenames without `.gguf`). Both models are listed, so you can switch between them with opencode's `/model` command — the router auto-loads the selected model on the next request (with `--models-max 1` that purges the other model first; expect a ~40–60s wait on the first request after switching).

Content (27b currently selected):

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
          "name": "Qwen 3.8 27B (dense, accurate)",
          "tool_call": true,
          "limit": {
            "context": 130000,
            "output": 8192
          },
          "modalities": {
            "input": ["text", "image"],
            "output": ["text"]
          }
        },
        "Qwen_Qwen3.6-35B-A3B-Q4_K_M": {
          "name": "Qwen 3.6 35B-A3B (MoE, fast)",
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

## Notes

- `/model` takes effect for the current session immediately (the next request uses the selected model; the router loads it if needed).
- The pre-migration model key was `my-model` (ignored in single-model mode). A temporary preset alias (`my-model`, `llama-cpp/my-model` → 27b) in `model-switching/models.preset.ini` keeps any stale client working until it is removed.
- Keep `limit.context` at or below the server's pinned `ctx-size` (see `model-switching/models.preset.ini`).

Config file: `~/.config/opencode/opencode.json`

Content:

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
        "my-model": {
          "name": "qwen3.6:35b",
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

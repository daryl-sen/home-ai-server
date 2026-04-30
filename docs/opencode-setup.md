Config file: `~/.config/opencode/opencode.json`

Content:

```json
{
  "$schema": "https://opencode.ai/config.json",
  "provider": {
    "llama-local": {
      "name": "Llama.cpp Local",
      "npm": "@ai-sdk/openai-compatible",
      "options": {
        "baseURL": "http://100.89.219.6:8080/v1"
      },
      "models": {
        "local": {
          "name": "Local Model",
          "modalities": {
            "input": ["text", "image"],
            "output": ["text"]
          }
        }
      }
    }
  }
}
```

curl -X POST "http://localhost:9200/_plugins/_ml/models/_register" \
  -H 'Content-Type: application/json' \
  -d '{
    "name": "OpenAI Text Embedding 3 Small",
    "function_name": "remote",
    "description": "Remote model for OpenAI embeddings via OpenRouter",
    "connector_id": "<YOUR_CONNECTOR_ID_FROM_PREVIOUS_STEP>"
  }
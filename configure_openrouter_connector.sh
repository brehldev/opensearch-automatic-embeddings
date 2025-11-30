curl -X POST "http://localhost:9200/_plugins/_ml/connectors/_create" \
  -H 'Content-Type: application/json' \
  -d '{
  "name": "OpenRouter Connector",
  "version": "1",
  "protocol": "http",
  "parameters": {
    "endpoint": "openrouter.ai",
    "model": "openai/text-embedding-3-small"
  },
  "credential": {
    "openRouter_key": "YOUR_API_KEY"
  },
  "actions": [
    {
      "action_type": "PREDICT",
      "method": "POST",
      "url": "https://${parameters.endpoint}/api/v1/embeddings",
      "headers": {
        "Authorization": "Bearer ${credential.openRouter_key}",
        "Content-Type": "application/json"
      },
      "request_body": "{ \"model\": \"${parameters.model}\", \"input\": ${parameters.input} }",
      "post_process_function": "connector.post_process.openai.embedding"
    }
  ]
}
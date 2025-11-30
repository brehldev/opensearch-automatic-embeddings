curl -X PUT "http://localhost:9200/_cluster/settings" \
  -H "Content-Type: application/json" \
  -d '{
    "persistent": {
      "plugins.ml_commons.trusted_connector_endpoints_regex": [
        "^https://openrouter\\.ai/.*$",
        "^https://api\\.openai\\.com/.*$",
        "^https://router\\.huggingface\\.co/.*$"
      ]
    }
  }'
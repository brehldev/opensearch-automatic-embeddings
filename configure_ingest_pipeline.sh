curl -X PUT "http://localhost:9200/_ingest/pipeline/docling-ingest-pipeline" \
  -H 'Content-Type: application/json' \
  -d '{
  "description": "Pipeline for automatic embedding generation",
  "processors": [
    {
      "text_embedding": {
        "model_id": "<YOUR_DEPLOYED_MODEL_ID>",
        "field_map": {
          "content": "content_embedding"
        }
      }
    }
  ]
}'
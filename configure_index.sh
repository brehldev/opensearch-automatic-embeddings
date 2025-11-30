curl -X PUT "http://localhost:9200/open-ai-3-small-documents-6" \
  -H 'Content-Type: application/json' \
  -d '{
  "settings": {
    "index.knn": true,
    "default_pipeline": "docling-ingest-pipeline"
  },
  "mappings": {
    "properties": {
      "content_embedding": {
        "type": "knn_vector",
        "dimension": 1536
      },
      "content": { "type": "text" }
    }
  }
}'
curl -X POST "http://localhost:9200/_plugins/_ml/models/<YOUR_MODEL_ID>/_deploy" \
  -H 'Content-Type: application/json'
  -d '{}'
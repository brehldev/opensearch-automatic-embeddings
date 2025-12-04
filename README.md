# Learn how to setup automatic embeddings using OpenSearch and OpenRouter API for automatic RAG enabled data.

You have data. You want that data to be searchable by meaning, not just by keyword. That means you need vector embeddings.

Usually, getting those embeddings turns into a massive DevOps project. You find yourself spinning up a dedicated embedding microservice, managing heavy model weights in memory, managing ML resources and writing brittle glue code just to intercept data before it hits its final destination. It’s expensive, and it’s one more service to maintain.

Stop building middleware if you are using OpenSearch, you already have the tools to handle this.

You can configure OpenSearch to run these [ingest pipelines](https://docs.opensearch.org/latest/ingest-pipelines/) automatically. This guide shows you exactly how to wire up OpenSearch’s native ml-commons plugin to fetch and generate vectors from an external provider in the background. We will build a pipeline that transforms raw text into vector-search-ready documents on the fly, meaning any application saving data to your cluster effectively becomes an AI application, with zero extra code.


## The Goal: Zero-Drama Vector Embeddings
In this OpenSearch automatic embedding tutorial, we are building an architecture where your "Write Path" looks exactly like a standard database insert. Instead of managing vectors in your application code, we will configure the cluster to automatically enrich your data in the background.

Your application sends this:

```json
{
  "title": "My Document",
  "content": "A really long paragraph from my ETL pipeline."
}
```

And OpenSearch automatically stores this:

```json
{
  "title": "My Document",
  "content": "A really long paragraph from my ETL pipeline",
  "content_embedding": [0.012, -0.045, 0.881, ... ]
}
```

To achieve this, we need to configure five specific components inside the cluster:

1. Cluster Settings: To allow outbound traffic to the API provider.
2. The Connector: To define how the cluster talks to OpenRouter.
3. The Model: To register the connector as a usable resource.
4. The Ingest Pipeline: To define the logic of when and how to embed data.
5. The Index: To enforce the pipeline on every new document.

## Phase 1: Configure Trusted Endpoints

OpenSearch has a secure default posture. Out of the box, the machine learning plugin (`ml-commons`) is firewalled; it cannot make outbound HTTP requests to the internet. If you try to connect to an external API without configuration, the request will simply fail because the cluster doesn't trust the destination.

We need to update the cluster settings to explicitly whitelist the domains we intend to use. In this case, since we are using OpenRouter (which acts as a gateway to OpenAI, Anthropic, Mistral, etc.), we need to trust openrouter.ai.

Run the following command to update the persistent cluster settings:

```shell
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
  }
```

We also included OpenAI and Hugging Face in the list above. This is good practice if you think you might switch providers later; it prevents you from having to re-run admin commands against the cluster settings in the future.

This setting is dynamic, meaning you do not need to restart your nodes for it to take effect.

## Phase 2: Create the Connector

The Connector is the most detailed part of the setup. Think of the Connector as the "driver" for the API. It tells OpenSearch exactly how to format the HTTP request, what headers to include, and—crucially—how to parse the JSON response that comes back.

We are going to define a connector for OpenRouter. We will configure it to use the OpenAI-compatible endpoint structure, as most embedding models on OpenRouter follow this pattern.

### Critical Configuration for OpenRouter:

**Endpoint**: [openrouter.ai](https://openrouter.ai) provides an OpenAI-compatible endpoint at `https://openrouter.ai/v1/embeddings`.

**Model**: `openai/text-embedding-3-small`. We are hardcoding this as our default, though you can create an unlimited number ingest pipelines depending on your use case.

### Why the Post-Process Function Matters
When the API replies, it sends a nested JSON object. OpenSearch needs a flat array of floats. You could write a custom generic script (using Painless) to traverse the JSON, but OpenSearch provides a built-in function specifically for OpenAI-compatible responses. Using `connector.post_process.openai.embedding` ensures that the vector is extracted correctly without you writing custom parsing logic.

### The Create Connector Command

Replace YOUR_API_KEY with your actual OpenRouter credential (usually starting with sk-or-...).

```shell
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
```

This command will return a JSON object containing a connector_id.

```json
{"connector_id": "AbCdEfGhIjKlMnOp"}
```

Copy this ID. You cannot proceed without it.

## Phase 3: Register and Deploy the Model

In OpenSearch, the resource that performs the work is called a Model. Even though the actual neural network is running on whoever OpenRouter's servers call, OpenSearch creates a logical representation of that model internally to manage access, tasks, and throttling.

This is a two-step process: Register (create the definition) and Deploy (load it into memory/active state).

### Step 3a: Register the Model

We register a "Remote Model" that points to the connector we just created.

```shell
curl -X POST "http://localhost:9200/_plugins/_ml/models/_register" \
  -H 'Content-Type: application/json' \
  -d '{
    "name": "OpenAI Text Embedding 3 Small",
    "function_name": "remote",
    "description": "Remote model for OpenAI embeddings via OpenRouter",
    "connector_id": "<YOUR_CONNECTOR_ID_FROM_PREVIOUS_STEP>"
  }
```

This command returns a task_id, not the model ID directly. This is because model registration can sometimes handle large file uploads (for local models). For remote models, it is nearly instant, but it is still asynchronous.

```json
{"task_id": "QwErTyUiOpAsDfGh", "status": "CREATED"}
```

### Step 3b: Get the Model ID
You can query the task API, but usually, for remote models, the Model ID is generated immediately. If you want to be scripted and precise, check the task:

```shell
curl -X GET "http://localhost:9200/_plugins/_ml/tasks/<YOUR_TASK_ID>"
```


### Step 3c: Deploy the Model

Now we activate the model. This tells the ML nodes to be ready to route traffic for this specific ID.

```shell
curl -X POST "http://localhost:9200/_plugins/_ml/models/<YOUR_MODEL_ID>/_deploy" \
  -H 'Content-Type: application/json'
  -d '{}'
```

If you receive `{"status": "COMPLETED"}`, your OpenSearch cluster is now officially connected to OpenRouter.


## Phase 4: Create the Ingest Pipeline

We have the infrastructure (the Model). Now we need the logic (the Pipeline).

OpenSearch [Ingest Pipelines](https://docs.opensearch.org/latest/ingest-pipelines/) allow you to define a chain of processors that transform documents before they are written to the index. This is where the "automatic" magic happens.

We will create a pipeline named docling-ingest-pipeline. It uses the built-in [text_embedding processor](https://docs.opensearch.org/latest/ingest-pipelines/processors/text-embedding/).

```shell
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
```

### Configuration Breakdown:
- `model_id`: This is the ID of the model we deployed in Phase 3.
- `field_map`: This tells OpenSearch to read the `content` field from incoming documents and write the resulting embedding to a new field called `content_embedding`. You can
map multiple fields if needed.

## Phase 5: Create the Index

The final configuration step is creating the index where the data is stored. We need to do two things here:

1. **Configure the Mapping:** We must explicitly tell OpenSearch that the content_embedding field is a knn_vector. If we don't, OpenSearch will treat it as a standard array of numbers, and we won't be able to perform semantic search.

2. **Set the Default Pipeline:** We configure the index settings so that our docling-ingest-pipeline is the default. This ensures that any write request sent to this index, even if it doesn't specify a pipeline, triggers the embedding process.


```shell
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
```

## Try it out!!
Now that the pipeline is wired up, we can test it. We will insert a document that contains only text. We will not provide the vector.

```shell
curl -X POST "http://localhost:9200/open-ai-3-small-documents-6/_doc/1" \
  -H 'Content-Type: application/json' \
  -d '{
  "title": "Test Document",
  "content": "This is a test document to verify OpenSearch indexing and the embedding pipeline works correctly."
}'
```

If the configuration is correct, you will receive a standard 201 Created JSON response.


## Verify the Embedding was Created
To confirm that the embedding was generated and stored, we can retrieve the document we just inserted.

```shell
curl -X GET "http://localhost:9200/open-ai-3-small-documents-6/_doc/1"
```

In the response, look at the _source block. You will see your original content field, but you will also see the generated content_embedding.

```json
{

  "_index": "open-ai-3-small-documents-6",
  "_id": "1",
  "_source": {
    "title": "Test Document",
    "content": "This is a test document to verify OpenSearch indexing and the embedding pipeline works correctly.",
    "content_embedding": [
      -0.0012,
      0.0231,
      -0.0155,
      ...
    ]
  }
}
```

The vector is there. The text is there. Your application code remains unaware of the complexity that just occurred.

## Summary

By following this structure, you have removed the need for middleware "glue" code. Your OpenSearch cluster is now a self-contained vector search engine. It handles the secure connection to the external model provider, manages the embedding generation, and enforces the presence of vectors on your data.

This setup creates a robust, clean architecture where your application simply stores data, and the database makes that data intelligent. Your data is now fully ready for RAG!

[OpenRouter Models](https://openrouter.ai/docs/models) - A list of compatible models you can use with this connector setup.
[OpenSearch ML Commons](https://opensearch.org/docs/latest/ml-commons-plugin/cluster-settings/) - Official documentation for the ml-commons plugin.

This article can also be found on [LinkedIn](https://www.linkedin.com/pulse/building-native-ingestion-pipelines-rag-opensearch-torry-brelsford-whuye/?trackingId=e%2Fh5SK0lTsuxRVpzYZWfIg%3D%3D) & [brehl.dev](https://brehl.dev/blog/automatic-embeddings-with-opensearch/)

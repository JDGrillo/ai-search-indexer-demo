# Azure AI Search Indexer Demo

A Retrieval-Augmented Generation (RAG) chat application built on Azure. Upload PDF documents to blob storage, let Azure AI Search index them on a 5-minute schedule, and ask questions through a Streamlit chat UI backed by GPT-4o.

## Architecture

```
┌──────────────────┐         ┌──────────────────┐         ┌──────────────────┐
│    Streamlit     │  HTTP   │     FastAPI       │ Search  │  Azure AI Search │
│    Frontend      │────────▶│     Backend       │────────▶│ (documents-index)│
│                  │◀────────│                   │◀────────│                  │
└──────────────────┘         │  POST /api/chat   │         └────────┬─────────┘
                             │  GET  /api/status │                  │
                             │  POST /api/run    │                  │ Indexer
                             └────────┬──────────┘                  │ (every 5 min)
                                      │                             │
                                      │ RAG                         │
                                      ▼                             ▼
                             ┌──────────────────┐         ┌──────────────────┐
                             │   Azure OpenAI   │         │   Azure Blob     │
                             │   GPT-4o         │         │   Storage (PDFs) │
                             └──────────────────┘         └──────────────────┘
                                                                    ▲
                                                                    │ CRUD
                                                                    │
                                                          ┌──────────────────┐
                                                          │  Azure Functions │
                                                          │  /api/documents  │
                                                          └──────────────────┘
```

All service-to-service auth uses **Managed Identities** (no keys or connection strings).

## Components

### Infrastructure (`infra/`)

Terraform provisions all Azure resources:

| Resource | Purpose |
|---|---|
| Azure AI Search | Full-text search index + scheduled indexer |
| Azure Blob Storage | PDF document storage (soft-delete enabled) |
| Azure AI Services | GPT-4o model hosting |
| App Service (x2) | Backend API + Frontend UI (B1 Linux) |
| Function App | Document CRUD (Python 3.11, Premium plan) |
| Virtual Network | Private endpoints, NAT gateway, subnets |
| Application Insights | Logging and monitoring |
| Managed Identities | Passwordless RBAC for all services |

### Backend API (`backend/`)

FastAPI application serving the RAG pipeline.

| Endpoint | Method | Description |
|---|---|---|
| `/api/chat` | POST | Send a question, get a GPT-4o answer grounded in indexed documents |
| `/api/indexer/status` | GET | Check indexer status (last run, items processed/failed) |
| `/api/indexer/run` | POST | Manually trigger the indexer |

**Chat flow:** User question → Azure AI Search (top 5 results) → GPT-4o with document context → Answer with cited sources.

### Frontend UI (`frontend/`)

Streamlit web application with:

- **Chat interface** — Ask questions about indexed documents, view answers with expandable source citations
- **Sidebar** — Live indexer status, item counts, and a button to trigger a manual indexer run

### Function App (`function-app/`)

Azure Functions for document lifecycle management via HTTP triggers:

| Function | Route | Description |
|---|---|---|
| CreateDocument | `POST /api/documents` | Generate a PDF from title + content, upload to blob storage |
| UpdateDocument | `PUT /api/documents/{name}` | Replace an existing document with new content |
| DeleteDocument | `DELETE /api/documents/{name}` | Soft-delete a document (indexer auto-removes from index) |
| ListDocuments | `GET /api/documents` | List all documents with size and last-modified |

### Utility Scripts (`scripts/`)

| Script | Purpose |
|---|---|
| `generate_pdfs.py` | Create 3 sample PDFs in `sample-docs/` |
| `upload_docs.py` | Upload PDFs to blob storage |
| `setup_search.py` | Create the search index, data source, and indexer |
| `deploy_apps.sh` | Deploy backend, frontend, and function app to Azure |

## Prerequisites

- Python 3.11+
- [Azure CLI](https://learn.microsoft.com/cli/azure/install-azure-cli) (`az`)
- [Azure Functions Core Tools](https://learn.microsoft.com/azure/azure-functions/functions-run-local) (`func`)
- [Terraform](https://developer.hashicorp.com/terraform/install) (1.5+)
- An Azure subscription with access to Azure OpenAI

## Getting Started

### 1. Provision Infrastructure

```bash
cd infra
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars with your subscription ID and preferences
terraform init
terraform apply
```

### 2. Set Up Search Index

```bash
cd infra
terraform output -json | python ../scripts/setup_search.py --from-terraform
```

Or manually:

```bash
python scripts/setup_search.py \
  --search-endpoint https://srch-<your-name>.search.windows.net \
  --storage-resource-id /subscriptions/<sub-id>/resourceGroups/<rg>/providers/Microsoft.Storage/storageAccounts/<account>
```

### 3. Upload Sample Documents

```bash
python scripts/generate_pdfs.py
python scripts/upload_docs.py --storage-account <your-storage-account>
```

### 4. Configure Environment

```bash
cd backend
cp .env.example .env
# Edit .env with your resource endpoints (from terraform output)
```

### 5. Run Locally

**Backend** (terminal 1):

```bash
cd backend
pip install -r requirements.txt
uvicorn app.main:app --host 0.0.0.0 --port 8000
```

**Frontend** (terminal 2):

```bash
cd frontend
pip install -r requirements.txt
python -m streamlit run app.py --server.port 8501 --server.address 0.0.0.0
```

Open http://localhost:8501 in your browser.

**Function App** (terminal 3):

```bash
cd function-app
pip install -r requirements.txt
func host start
```

### 6. Deploy to Azure

```bash
# Get resource names from Terraform output
cd infra && terraform output

# Deploy all apps
./scripts/deploy_apps.sh <backend-app-name> <frontend-app-name> <function-app-name>
```

## Testing the RAG Pipeline

### End-to-End Test Flow

1. **Verify indexer is running:**
   - Open the frontend sidebar → check indexer status shows "Idle" or "Success"
   - Or call `GET /api/indexer/status`

2. **Ask a question about the sample docs:**
   ```
   "What is Contoso's remote work policy?"
   "What are the Widget Pro battery specifications?"
   "Describe the Project Aurora architecture."
   ```
   Answers should cite the relevant PDF source with a relevance score.

3. **Test document creation → indexing:**
   ```bash
   curl -X POST http://localhost:7071/api/documents \
     -H "Content-Type: application/json" \
     -d '{"filename": "test-doc.pdf", "title": "Test Document", "content": "This is test content for search indexing."}'
   ```
   Wait for the next indexer run (up to 5 minutes), then search for "test content" in the chat.

4. **Test document update → re-indexing:**
   ```bash
   curl -X PUT http://localhost:7071/api/documents/test-doc.pdf \
     -H "Content-Type: application/json" \
     -d '{"title": "Updated Document", "content": "This content has been updated with new information."}'
   ```
   After the next indexer run, the old content should be replaced by the updated content.

5. **Test document deletion → removal from index:**
   ```bash
   curl -X DELETE http://localhost:7071/api/documents/test-doc.pdf
   ```
   The indexer detects the soft-delete and removes the document from the search index.

6. **Trigger a manual indexer run** (skip the 5-minute wait):
   ```bash
   curl -X POST http://localhost:8000/api/indexer/run
   ```

### Verify Search Index Directly

```bash
# Check indexer status via the backend API
curl http://localhost:8000/api/indexer/status | python -m json.tool

# List documents in blob storage via the Function App
curl http://localhost:7071/api/documents | python -m json.tool
```

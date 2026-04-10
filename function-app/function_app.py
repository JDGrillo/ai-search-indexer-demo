"""
Azure Function App for document management.

Provides HTTP endpoints to create, update, list, and delete PDF documents
in Azure Blob Storage. Uses DefaultAzureCredential (user-assigned MI)
and fpdf2 for on-the-fly PDF generation from text content.
"""

import json
import os

import azure.functions as func
from azure.identity import DefaultAzureCredential
from azure.storage.blob import BlobServiceClient
from fpdf import FPDF

app = func.FunctionApp(http_auth_level=func.AuthLevel.ANONYMOUS)

credential = DefaultAzureCredential()
storage_account = os.environ["STORAGE_ACCOUNT_NAME"]
container_name = os.environ.get("STORAGE_CONTAINER_NAME", "documents")

blob_service = BlobServiceClient(
    account_url=f"https://{storage_account}.blob.core.windows.net",
    credential=credential,
)
container_client = blob_service.get_container_client(container_name)


def _create_pdf(title: str, content: str) -> bytes:
    pdf = FPDF()
    pdf.add_page()
    pdf.set_font("Helvetica", "B", 16)
    pdf.cell(0, 10, title, new_x="LMARGIN", new_y="NEXT")
    pdf.ln(5)
    pdf.set_font("Helvetica", size=11)
    pdf.multi_cell(0, 6, content)
    return bytes(pdf.output())


def _json_response(body: dict, status_code: int = 200) -> func.HttpResponse:
    return func.HttpResponse(
        json.dumps(body),
        status_code=status_code,
        mimetype="application/json",
    )


@app.function_name(name="CreateDocument")
@app.route(route="documents", methods=["POST"])
def create_document(req: func.HttpRequest) -> func.HttpResponse:
    """Create a new PDF from JSON { filename, title, content }."""
    try:
        body = req.get_json()
    except ValueError:
        return _json_response({"error": "Invalid JSON body"}, 400)

    filename = body.get("filename", "")
    title = body.get("title", "")
    content = body.get("content", "")

    if not filename:
        return _json_response({"error": "filename is required"}, 400)

    if not filename.lower().endswith(".pdf"):
        filename += ".pdf"

    pdf_bytes = _create_pdf(title or filename, content)
    container_client.upload_blob(name=filename, data=pdf_bytes, overwrite=True)

    return _json_response({"message": f"Created {filename}", "filename": filename}, 201)


@app.function_name(name="UpdateDocument")
@app.route(route="documents/{name}", methods=["PUT"])
def update_document(req: func.HttpRequest) -> func.HttpResponse:
    """Update an existing PDF with new content { title, content }."""
    name = req.route_params.get("name")
    if not name:
        return _json_response({"error": "Document name is required"}, 400)

    try:
        body = req.get_json()
    except ValueError:
        return _json_response({"error": "Invalid JSON body"}, 400)

    title = body.get("title", "")
    content = body.get("content", "")

    pdf_bytes = _create_pdf(title or name, content)
    container_client.upload_blob(name=name, data=pdf_bytes, overwrite=True)

    return _json_response({"message": f"Updated {name}", "filename": name})


@app.function_name(name="DeleteDocument")
@app.route(route="documents/{name}", methods=["DELETE"])
def delete_document(req: func.HttpRequest) -> func.HttpResponse:
    """Delete a document from blob storage."""
    name = req.route_params.get("name")
    if not name:
        return _json_response({"error": "Document name is required"}, 400)

    blob_client = container_client.get_blob_client(name)
    blob_client.delete_blob()

    return _json_response({"message": f"Deleted {name}"})


@app.function_name(name="ListDocuments")
@app.route(route="documents", methods=["GET"])
def list_documents(req: func.HttpRequest) -> func.HttpResponse:
    """List all documents in the blob container."""
    blobs = container_client.list_blobs()
    documents = [
        {
            "name": blob.name,
            "size": blob.size,
            "last_modified": (
                blob.last_modified.isoformat() if blob.last_modified else None
            ),
        }
        for blob in blobs
    ]
    return _json_response({"documents": documents})

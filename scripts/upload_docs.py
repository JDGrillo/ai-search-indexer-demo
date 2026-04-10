"""
Upload sample documents to Azure Blob Storage using DefaultAzureCredential.

Usage:
    python scripts/upload_docs.py --storage-account stindexerdemo
    python scripts/upload_docs.py --storage-account stindexerdemo --container documents --docs-dir sample-docs
"""

import argparse
import glob
import os

from azure.identity import DefaultAzureCredential
from azure.storage.blob import BlobServiceClient


def main():
    parser = argparse.ArgumentParser(description="Upload sample docs to blob storage")
    parser.add_argument("--storage-account", required=True, help="Storage account name")
    parser.add_argument("--container", default="documents", help="Blob container name")
    parser.add_argument(
        "--docs-dir",
        default=os.path.join(os.path.dirname(__file__), "..", "sample-docs"),
        help="Directory containing PDF files to upload",
    )
    args = parser.parse_args()

    credential = DefaultAzureCredential()
    blob_service = BlobServiceClient(
        account_url=f"https://{args.storage_account}.blob.core.windows.net",
        credential=credential,
    )
    container = blob_service.get_container_client(args.container)

    pdf_files = sorted(glob.glob(os.path.join(args.docs_dir, "*.pdf")))
    if not pdf_files:
        print(f"No PDF files found in {os.path.abspath(args.docs_dir)}")
        print("Run 'python scripts/generate_pdfs.py' first to create sample documents.")
        return

    for pdf_path in pdf_files:
        filename = os.path.basename(pdf_path)
        print(f"  Uploading {filename}...")
        with open(pdf_path, "rb") as f:
            container.upload_blob(name=filename, data=f, overwrite=True)
        print(f"  [OK] {filename}")

    print(
        f"\nAll {len(pdf_files)} files uploaded to {args.storage_account}/{args.container}"
    )


if __name__ == "__main__":
    main()

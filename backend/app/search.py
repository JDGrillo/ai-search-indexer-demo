from azure.identity import DefaultAzureCredential
from azure.search.documents import SearchClient
from azure.search.documents.indexes import SearchIndexerClient

from .config import settings

_credential_kwargs = {}
if settings.azure_client_id:
    _credential_kwargs["managed_identity_client_id"] = settings.azure_client_id

credential = DefaultAzureCredential(**_credential_kwargs)

search_client = SearchClient(
    endpoint=settings.search_endpoint,
    index_name=settings.search_index_name,
    credential=credential,
)

indexer_client = SearchIndexerClient(
    endpoint=settings.search_endpoint,
    credential=credential,
)


def search_documents(query: str, top: int = 5) -> list[dict]:
    results = search_client.search(
        search_text=query,
        top=top,
        select=["content", "metadata_storage_name"],
    )
    return [
        {
            "content": r.get("content", ""),
            "source": r.get("metadata_storage_name", "unknown"),
            "score": r["@search.score"],
        }
        for r in results
    ]


def get_indexer_status() -> dict:
    status = indexer_client.get_indexer_status(settings.search_indexer_name)
    last_result = status.last_result
    return {
        "status": (
            status.status.value
            if hasattr(status.status, "value")
            else str(status.status)
        ),
        "last_run": (
            {
                "status": (
                    last_result.status.value
                    if hasattr(last_result.status, "value")
                    else str(last_result.status)
                ),
                "start_time": (
                    last_result.start_time.isoformat()
                    if last_result.start_time
                    else None
                ),
                "end_time": (
                    last_result.end_time.isoformat() if last_result.end_time else None
                ),
                "items_processed": last_result.item_count,
                "items_failed": last_result.failed_item_count,
            }
            if last_result
            else None
        ),
    }


def run_indexer() -> None:
    indexer_client.run_indexer(settings.search_indexer_name)

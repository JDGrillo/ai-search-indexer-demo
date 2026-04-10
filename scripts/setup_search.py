"""
Setup Azure AI Search index, data source, and indexer.

Creates the search index schema, configures a blob data source with managed
identity connection, and sets up an indexer with a 5-minute schedule and
native blob soft delete detection.

Usage:
    python scripts/setup_search.py \
        --search-endpoint https://srch-indexer-demo.search.windows.net \
        --storage-resource-id /subscriptions/.../storageAccounts/stindexerdemo

    Or read values from terraform output:
        cd infra && terraform output -json | python ../scripts/setup_search.py --from-terraform
"""

import argparse
import datetime
import json
import sys

from azure.identity import DefaultAzureCredential
from azure.search.documents.indexes import SearchIndexClient, SearchIndexerClient
from azure.search.documents.indexes.models import (
    DataDeletionDetectionPolicy,
    SearchField,
    SearchFieldDataType,
    SearchIndex,
    SearchIndexer,
    SearchIndexerDataContainer,
    SearchIndexerDataSourceConnection,
    IndexingSchedule,
)


def parse_args():
    parser = argparse.ArgumentParser(description="Setup Azure AI Search resources")
    parser.add_argument(
        "--from-terraform",
        action="store_true",
        help="Read config from terraform output JSON on stdin",
    )
    parser.add_argument("--search-endpoint", help="AI Search endpoint URL")
    parser.add_argument("--storage-resource-id", help="Storage account ARM resource ID")
    parser.add_argument("--container-name", default="documents")
    parser.add_argument("--index-name", default="documents-index")
    parser.add_argument("--indexer-name", default="documents-indexer")
    parser.add_argument("--datasource-name", default="blob-datasource")
    return parser.parse_args()


def read_terraform_output():
    """Read terraform output JSON from stdin."""
    data = json.load(sys.stdin)
    return {
        "search_endpoint": data["search_endpoint"]["value"],
        "storage_resource_id": data["storage_account_resource_id"]["value"],
        "container_name": data.get("storage_container_name", {}).get(
            "value", "documents"
        ),
    }


def main():
    args = parse_args()

    if args.from_terraform:
        tf = read_terraform_output()
        search_endpoint = tf["search_endpoint"]
        storage_resource_id = tf["storage_resource_id"]
        container_name = tf["container_name"]
    else:
        if not args.search_endpoint or not args.storage_resource_id:
            print(
                "Error: --search-endpoint and --storage-resource-id are required "
                "(or use --from-terraform)"
            )
            sys.exit(1)
        search_endpoint = args.search_endpoint
        storage_resource_id = args.storage_resource_id
        container_name = args.container_name

    credential = DefaultAzureCredential()

    # ── Create Search Index ──────────────────────────────────────────────────
    index_client = SearchIndexClient(endpoint=search_endpoint, credential=credential)

    fields = [
        SearchField(
            name="id", type=SearchFieldDataType.String, key=True, filterable=True
        ),
        SearchField(name="content", type=SearchFieldDataType.String, searchable=True),
        SearchField(
            name="metadata_storage_name",
            type=SearchFieldDataType.String,
            searchable=True,
            filterable=True,
            sortable=True,
        ),
        SearchField(
            name="metadata_storage_path",
            type=SearchFieldDataType.String,
            filterable=True,
        ),
        SearchField(
            name="metadata_storage_last_modified",
            type=SearchFieldDataType.DateTimeOffset,
            filterable=True,
            sortable=True,
        ),
        SearchField(
            name="metadata_storage_size",
            type=SearchFieldDataType.Int64,
            filterable=True,
            sortable=True,
        ),
    ]

    index = SearchIndex(name=args.index_name, fields=fields)
    index_client.create_or_update_index(index)
    print(f"[OK] Index '{args.index_name}' created/updated.")

    # ── Create Data Source (MI connection to blob storage) ────────────────────
    indexer_client = SearchIndexerClient(
        endpoint=search_endpoint, credential=credential
    )

    connection_string = f"ResourceId={storage_resource_id};"

    soft_delete_policy = DataDeletionDetectionPolicy()
    soft_delete_policy.odata_type = (
        "#Microsoft.Azure.Search.NativeBlobSoftDeleteDeletionDetectionPolicy"
    )

    data_source = SearchIndexerDataSourceConnection(
        name=args.datasource_name,
        type="azureblob",
        connection_string=connection_string,
        container=SearchIndexerDataContainer(name=container_name),
        data_deletion_detection_policy=soft_delete_policy,
    )
    indexer_client.create_or_update_data_source_connection(data_source)
    print(f"[OK] Data source '{args.datasource_name}' created/updated (MI connection).")

    # ── Create Indexer (5-minute schedule) ────────────────────────────────────
    indexer = SearchIndexer(
        name=args.indexer_name,
        data_source_name=args.datasource_name,
        target_index_name=args.index_name,
        schedule=IndexingSchedule(interval=datetime.timedelta(minutes=5)),
    )
    indexer_client.create_or_update_indexer(indexer)
    print(f"[OK] Indexer '{args.indexer_name}' created/updated with PT5M schedule.")
    print("\nSetup complete. The indexer will run automatically every 5 minutes.")


if __name__ == "__main__":
    main()

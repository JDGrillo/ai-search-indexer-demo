from pydantic_settings import BaseSettings


class Settings(BaseSettings):
    # Azure AI Search
    search_endpoint: str
    search_index_name: str = "documents-index"
    search_indexer_name: str = "documents-indexer"

    # Azure AI Foundry (OpenAI)
    openai_endpoint: str
    openai_deployment_name: str = "gpt-4o"
    openai_api_version: str = "2024-10-21"

    # Optional: User-assigned managed identity client ID
    # Set this when running with a user-assigned MI; leave unset for az login locally.
    azure_client_id: str | None = None

    model_config = {"env_file": ".env", "extra": "ignore"}


settings = Settings()

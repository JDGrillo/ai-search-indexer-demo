from azure.identity import DefaultAzureCredential, get_bearer_token_provider
from openai import AzureOpenAI

from .config import settings

_credential_kwargs = {}
if settings.azure_client_id:
    _credential_kwargs["managed_identity_client_id"] = settings.azure_client_id

credential = DefaultAzureCredential(**_credential_kwargs)

token_provider = get_bearer_token_provider(
    credential, "https://cognitiveservices.azure.com/.default"
)

client = AzureOpenAI(
    azure_endpoint=settings.openai_endpoint,
    azure_ad_token_provider=token_provider,
    api_version=settings.openai_api_version,
)

SYSTEM_PROMPT = (
    "You are a helpful assistant that answers questions based on the provided documents. "
    "Use only the information from the provided context to answer. If the context doesn't "
    "contain relevant information, say so. Always cite which document(s) your answer comes from."
)


def generate_rag_response(query: str, search_results: list[dict]) -> str:
    context = "\n\n".join(
        f"[Source: {r['source']}]\n{r['content'][:3000]}" for r in search_results
    )

    response = client.chat.completions.create(
        model=settings.openai_deployment_name,
        messages=[
            {"role": "system", "content": SYSTEM_PROMPT},
            {"role": "user", "content": f"Context:\n{context}\n\nQuestion: {query}"},
        ],
        max_tokens=1000,
        temperature=0.7,
    )
    return response.choices[0].message.content

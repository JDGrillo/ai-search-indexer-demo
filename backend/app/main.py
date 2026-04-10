from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel

from . import openai_client, search

app = FastAPI(title="Indexer Demo API")

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["*"],
    allow_headers=["*"],
)


class ChatRequest(BaseModel):
    question: str


class ChatResponse(BaseModel):
    answer: str
    sources: list[dict]


@app.post("/api/chat", response_model=ChatResponse)
def chat(request: ChatRequest):
    results = search.search_documents(request.question)
    if not results:
        return ChatResponse(
            answer="No relevant documents found in the index.",
            sources=[],
        )
    answer = openai_client.generate_rag_response(request.question, results)
    return ChatResponse(answer=answer, sources=results)


@app.get("/api/indexer/status")
def indexer_status():
    return search.get_indexer_status()


@app.post("/api/indexer/run")
def run_indexer():
    search.run_indexer()
    return {"message": "Indexer run triggered"}

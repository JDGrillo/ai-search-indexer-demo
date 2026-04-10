"""
Streamlit RAG chat frontend for the Azure AI Search Indexer Demo.

Provides a chat interface for querying indexed documents, a sidebar for
document management (upload/delete), and indexer status monitoring.

Start with:
    cd frontend && streamlit run app.py
"""

import os

import streamlit as st
import requests

BACKEND_URL = os.environ.get("BACKEND_URL", "http://localhost:8000")

st.set_page_config(page_title="Indexer Demo - RAG Chat", layout="wide")
st.title("Azure AI Search Indexer Demo")

# ─── Sidebar: Document Management & Indexer Status ─────────────────────────
with st.sidebar:
    st.header("Indexer Status")
    try:
        status_resp = requests.get(f"{BACKEND_URL}/api/indexer/status", timeout=10)
        if status_resp.ok:
            status = status_resp.json()
            st.write(f"**Status:** {status.get('status', 'unknown')}")
            last_run = status.get("last_run")
            if last_run:
                st.write(f"**Last run:** {last_run.get('status', 'N/A')}")
                st.write(f"**Time:** {last_run.get('end_time', 'N/A')}")
                st.write(
                    f"**Items:** {last_run.get('items_processed', 0)} processed, "
                    f"{last_run.get('items_failed', 0)} failed"
                )
    except requests.ConnectionError:
        st.warning("Backend not reachable")

    if st.button("Trigger Indexer Run"):
        try:
            resp = requests.post(f"{BACKEND_URL}/api/indexer/run", timeout=10)
            if resp.ok:
                st.success("Indexer run triggered!")
            else:
                st.error(f"Failed: {resp.text}")
        except requests.ConnectionError:
            st.error("Backend not reachable")

# ─── Chat Interface ────────────────────────────────────────────────────────
if "messages" not in st.session_state:
    st.session_state.messages = []

for msg in st.session_state.messages:
    with st.chat_message(msg["role"]):
        st.markdown(msg["content"])
        if msg.get("sources"):
            with st.expander("Sources"):
                for s in msg["sources"]:
                    st.write(f"**{s['source']}** (score: {s['score']:.2f})")

if prompt := st.chat_input("Ask a question about your documents..."):
    st.session_state.messages.append({"role": "user", "content": prompt})
    with st.chat_message("user"):
        st.markdown(prompt)

    with st.chat_message("assistant"):
        with st.spinner("Searching and generating answer..."):
            try:
                resp = requests.post(
                    f"{BACKEND_URL}/api/chat",
                    json={"question": prompt},
                    timeout=60,
                )
                if resp.ok:
                    data = resp.json()
                    st.markdown(data["answer"])
                    sources = data.get("sources", [])
                    if sources:
                        with st.expander("Sources"):
                            for s in sources:
                                st.write(f"**{s['source']}** (score: {s['score']:.2f})")
                    st.session_state.messages.append(
                        {
                            "role": "assistant",
                            "content": data["answer"],
                            "sources": sources,
                        }
                    )
                else:
                    error_msg = f"Error: {resp.text}"
                    st.error(error_msg)
                    st.session_state.messages.append(
                        {"role": "assistant", "content": error_msg}
                    )
            except requests.ConnectionError:
                error_msg = "Cannot reach the backend. Make sure the API is running."
                st.error(error_msg)
                st.session_state.messages.append(
                    {"role": "assistant", "content": error_msg}
                )

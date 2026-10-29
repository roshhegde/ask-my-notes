"""Ask: answer a question using the most relevant chunks of your notes.

POST /ask {"question": "..."} -> {"answer": "...", "sources": [...]}
"""

import json
import math
import os

import boto3
from botocore.config import Config

s3 = boto3.client("s3")
# Back off instead of failing when a new account's low Bedrock quota is hit.
bedrock = boto3.client(
    "bedrock-runtime",
    config=Config(retries={"max_attempts": 6, "mode": "adaptive"}),
)

BUCKET = os.environ["NOTES_BUCKET"]
EMBED_MODEL_ID = os.environ.get("EMBED_MODEL_ID", "amazon.titan-embed-text-v2:0")
EMBED_DIMENSIONS = int(os.environ.get("EMBED_DIMENSIONS", "256"))
CHAT_MODEL_ID = os.environ.get("CHAT_MODEL_ID", "amazon.nova-micro-v1:0")
TOP_K = 4
MAX_QUESTION_CHARS = 500  # cost guard: long prompts cost more tokens

SYSTEM_PROMPT = (
    "You answer questions using only the notes provided. "
    "If the notes don't contain the answer, say you don't know. "
    "Keep answers short and mention which source you used."
)

# Survives between warm invocations, so we only re-download index files
# whose ETag changed.
_index_cache = {}


def load_index():
    """Return every chunk as {"source", "text", "vector"}, refreshing changed files."""
    seen = set()
    paginator = s3.get_paginator("list_objects_v2")
    for page in paginator.paginate(Bucket=BUCKET, Prefix="index/"):
        for obj in page.get("Contents", []):
            key, etag = obj["Key"], obj["ETag"]
            seen.add(key)
            if _index_cache.get(key, {}).get("etag") != etag:
                doc = json.loads(s3.get_object(Bucket=BUCKET, Key=key)["Body"].read())
                chunks = [{"source": doc["source"], **c} for c in doc["chunks"]]
                _index_cache[key] = {"etag": etag, "chunks": chunks}
    for key in list(_index_cache):
        if key not in seen:
            del _index_cache[key]
    return [c for entry in _index_cache.values() for c in entry["chunks"]]


def cosine(a, b):
    dot = sum(x * y for x, y in zip(a, b))
    norm = math.sqrt(sum(x * x for x in a)) * math.sqrt(sum(y * y for y in b))
    return dot / norm if norm else 0.0


def top_chunks(query_vector, chunks, k=TOP_K):
    scored = sorted(chunks, key=lambda c: cosine(query_vector, c["vector"]), reverse=True)
    return scored[:k]


def build_prompt(question, chunks):
    context = "\n\n".join(
        f"[{i + 1}] (source: {c['source']})\n{c['text']}" for i, c in enumerate(chunks)
    )
    return f"Notes:\n{context}\n\nQuestion: {question}"


def embed(text):
    response = bedrock.invoke_model(
        modelId=EMBED_MODEL_ID,
        body=json.dumps(
            {"inputText": text, "dimensions": EMBED_DIMENSIONS, "normalize": True}
        ),
    )
    return json.loads(response["body"].read())["embedding"]


def respond(status, body):
    return {
        "statusCode": status,
        "headers": {"Content-Type": "application/json"},
        "body": json.dumps(body),
    }


def handler(event, context):
    try:
        question = json.loads(event.get("body") or "{}").get("question", "").strip()
    except json.JSONDecodeError:
        return respond(400, {"error": "Body must be JSON"})
    if not question:
        return respond(400, {"error": 'Send {"question": "..."}'})
    if len(question) > MAX_QUESTION_CHARS:
        return respond(400, {"error": f"Keep questions under {MAX_QUESTION_CHARS} characters"})

    chunks = load_index()
    if not chunks:
        return respond(200, {"answer": "No notes indexed yet. Upload a file to notes/ first.", "sources": []})

    best = top_chunks(embed(question), chunks)
    result = bedrock.converse(
        modelId=CHAT_MODEL_ID,
        system=[{"text": SYSTEM_PROMPT}],
        messages=[{"role": "user", "content": [{"text": build_prompt(question, best)}]}],
        inferenceConfig={"maxTokens": 400, "temperature": 0.2},
    )
    answer = result["output"]["message"]["content"][0]["text"]
    sources = sorted({c["source"] for c in best})
    print(json.dumps({"question_chars": len(question), "usage": result.get("usage")}))
    return respond(200, {"answer": answer, "sources": sources})

"""Ingest: turn an uploaded note into chunks + embeddings.

Triggered when a file lands in s3://<bucket>/notes/. Writes one JSON file
per note to s3://<bucket>/index/<same path>.json that the ask Lambda loads.
"""

import json
import os
import urllib.parse

import boto3

s3 = boto3.client("s3")
bedrock = boto3.client("bedrock-runtime")

EMBED_MODEL_ID = os.environ.get("EMBED_MODEL_ID", "amazon.titan-embed-text-v2:0")
# 256 dimensions is the smallest Titan V2 size: smaller index, same price.
EMBED_DIMENSIONS = int(os.environ.get("EMBED_DIMENSIONS", "256"))
CHUNK_SIZE = 1000  # characters, roughly 200 to 250 tokens
CHUNK_OVERLAP = 150  # so a sentence cut at a boundary still appears whole once
MAX_CHUNKS = 200  # cost guard: a huge upload can't run up a bill
SUPPORTED = (".txt", ".md")


def chunk_text(text, size=CHUNK_SIZE, overlap=CHUNK_OVERLAP):
    """Split text into overlapping windows, preferring to cut at whitespace."""
    text = " ".join(text.split())
    chunks, start = [], 0
    while start < len(text):
        end = min(start + size, len(text))
        if end < len(text):
            space = text.rfind(" ", start + size // 2, end)
            if space != -1:
                end = space
        chunks.append(text[start:end].strip())
        if end == len(text):
            break
        start = max(end - overlap, start + 1)
    return [c for c in chunks if c]


def embed(text):
    response = bedrock.invoke_model(
        modelId=EMBED_MODEL_ID,
        body=json.dumps(
            {"inputText": text, "dimensions": EMBED_DIMENSIONS, "normalize": True}
        ),
    )
    return json.loads(response["body"].read())["embedding"]


def index_key_for(note_key):
    return "index/" + note_key.removeprefix("notes/") + ".json"


def handler(event, context):
    results = []
    for record in event["Records"]:
        bucket = record["s3"]["bucket"]["name"]
        key = urllib.parse.unquote_plus(record["s3"]["object"]["key"])

        if not key.lower().endswith(SUPPORTED):
            print(f"Skipping {key}: only {SUPPORTED} are supported for now")
            continue

        body = s3.get_object(Bucket=bucket, Key=key)["Body"].read()
        chunks = chunk_text(body.decode("utf-8", errors="replace"))[:MAX_CHUNKS]

        entries = [{"text": c, "vector": embed(c)} for c in chunks]
        s3.put_object(
            Bucket=bucket,
            Key=index_key_for(key),
            Body=json.dumps({"source": key, "chunks": entries}),
            ContentType="application/json",
        )
        print(f"Indexed {key}: {len(entries)} chunks")
        results.append({"source": key, "chunks": len(entries)})
    return {"indexed": results}

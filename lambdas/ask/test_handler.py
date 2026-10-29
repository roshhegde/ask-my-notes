import os

os.environ.setdefault("NOTES_BUCKET", "test-bucket")
os.environ.setdefault("AWS_DEFAULT_REGION", "us-east-1")

from handler import build_prompt, cosine, handler, top_chunks  # noqa: E402


def test_cosine_identical_and_orthogonal():
    assert cosine([1, 0], [1, 0]) == 1
    assert cosine([1, 0], [0, 1]) == 0


def test_top_chunks_picks_closest():
    chunks = [
        {"source": "a", "text": "far", "vector": [0, 1]},
        {"source": "b", "text": "near", "vector": [1, 0.1]},
        {"source": "c", "text": "mid", "vector": [1, 1]},
    ]
    best = top_chunks([1, 0], chunks, k=2)
    assert [c["text"] for c in best] == ["near", "mid"]


def test_prompt_numbers_chunks_and_names_sources():
    prompt = build_prompt("What is S3?", [{"source": "notes/aws.md", "text": "S3 stores objects."}])
    assert "[1] (source: notes/aws.md)" in prompt
    assert prompt.endswith("Question: What is S3?")


def test_rejects_missing_and_long_questions():
    assert handler({"body": "{}"}, None)["statusCode"] == 400
    assert handler({"body": "not json"}, None)["statusCode"] == 400
    assert handler({"body": '{"question": "' + "x" * 501 + '"}'}, None)["statusCode"] == 400

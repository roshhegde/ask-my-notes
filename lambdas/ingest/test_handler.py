import os

os.environ.setdefault("AWS_DEFAULT_REGION", "us-east-1")

from handler import chunk_text, index_key_for  # noqa: E402


def test_short_text_is_one_chunk():
    assert chunk_text("hello   world\n") == ["hello world"]


def test_long_text_overlaps_and_covers_everything():
    words = [f"w{i}" for i in range(1000)]
    chunks = chunk_text(" ".join(words), size=200, overlap=50)
    assert len(chunks) > 1
    assert all(len(c) <= 200 for c in chunks)
    assert chunks[0].startswith("w0 ") and chunks[-1].endswith("w999")
    # Neighbouring chunks share some words.
    assert set(chunks[0].split()) & set(chunks[1].split())


def test_index_key_mirrors_note_path():
    assert index_key_for("notes/aws/lambda.md") == "index/aws/lambda.md.json"


def test_embed_uses_ollama_when_configured(monkeypatch):
    import json
    import threading
    from http.server import BaseHTTPRequestHandler, HTTPServer

    import handler

    seen = {}

    class FakeOllama(BaseHTTPRequestHandler):
        def do_POST(self):
            seen["path"] = self.path
            seen["body"] = json.loads(self.rfile.read(int(self.headers["Content-Length"])))
            body = json.dumps({"embeddings": [[0.1, 0.2, 0.3]]}).encode()
            self.send_response(200)
            self.end_headers()
            self.wfile.write(body)

        def log_message(self, *args):
            pass

    server = HTTPServer(("127.0.0.1", 0), FakeOllama)
    threading.Thread(target=server.handle_request, daemon=True).start()
    monkeypatch.setattr(handler, "EMBED_BACKEND", "ollama")
    monkeypatch.setattr(handler, "OLLAMA_URL", f"http://127.0.0.1:{server.server_port}")

    assert handler.embed("hello") == [0.1, 0.2, 0.3]
    assert seen["path"] == "/api/embed"
    assert seen["body"] == {"model": "nomic-embed-text", "input": "hello"}
    server.server_close()

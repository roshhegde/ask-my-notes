from handler import chunk_text, index_key_for


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

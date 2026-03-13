import hashlib
import logging
import os
import struct
import threading
from datetime import datetime, timezone
from pathlib import Path

import anthropic
from django.conf import settings

from .db import get_vec_db
from .models import Chunk, Note

logger = logging.getLogger(__name__)

_ingest_state = {
    "running": False,
    "total": 0,
    "done": 0,
    "current_file": "",
}
_lock = threading.Lock()

CHUNK_SIZE = 500  # characters per chunk
CHUNK_OVERLAP = 50


def get_status() -> dict:
    with _lock:
        return dict(_ingest_state)


def _split_chunks(text: str) -> list[str]:
    chunks = []
    start = 0
    while start < len(text):
        end = start + CHUNK_SIZE
        chunk = text[start:end]
        if chunk.strip():
            chunks.append(chunk.strip())
        start = end - CHUNK_OVERLAP
    return chunks


def _embed_texts(texts: list[str]) -> list[list[float]]:
    client = anthropic.Anthropic(api_key=settings.ANTHROPIC_API_KEY)
    batch_size = 20
    all_embeddings = []

    for i in range(0, len(texts), batch_size):
        batch = texts[i : i + batch_size]
        response = client.embeddings.create(
            model=settings.EMBEDDING_MODEL,
            input=batch,
        )
        for item in response.data:
            all_embeddings.append(item.embedding)

    return all_embeddings


def _float_list_to_bytes(floats: list[float]) -> bytes:
    return struct.pack(f"{len(floats)}f", *floats)


def ingest_folder(folder_path: str):
    with _lock:
        if _ingest_state["running"]:
            return
        _ingest_state["running"] = True
        _ingest_state["done"] = 0
        _ingest_state["current_file"] = ""

    try:
        _do_ingest(folder_path)
    finally:
        with _lock:
            _ingest_state["running"] = False


def _do_ingest(folder_path: str):
    md_files = list(Path(folder_path).rglob("*.md"))

    with _lock:
        _ingest_state["total"] = len(md_files)

    for md_file in md_files:
        file_path = str(md_file.resolve())
        with _lock:
            _ingest_state["current_file"] = md_file.name

        try:
            content = md_file.read_text(encoding="utf-8")
        except Exception as e:
            logger.warning(f"Failed to read {file_path}: {e}")
            with _lock:
                _ingest_state["done"] += 1
            continue

        note_id = Note.make_id(file_path)
        mtime = datetime.fromtimestamp(
            os.path.getmtime(file_path), tz=timezone.utc
        )

        existing = Note.objects.filter(id=note_id).first()
        if existing and existing.updated_at and existing.updated_at >= mtime:
            with _lock:
                _ingest_state["done"] += 1
            continue

        Note.objects.update_or_create(
            id=note_id,
            defaults={
                "path": file_path,
                "filename": md_file.name,
                "content": content,
            },
        )

        Chunk.objects.filter(note_id=note_id).delete()
        conn = get_vec_db()
        conn.execute("DELETE FROM vec_chunks WHERE chunk_id LIKE ?", (f"{note_id}_%",))
        conn.commit()

        chunks = _split_chunks(content)
        if not chunks:
            with _lock:
                _ingest_state["done"] += 1
            continue

        embeddings = _embed_texts(chunks)

        chunk_objs = []
        vec_rows = []
        for idx, (chunk_text, emb) in enumerate(zip(chunks, embeddings)):
            chunk_id = f"{note_id}_{idx}"
            chunk_objs.append(
                Chunk(
                    id=chunk_id,
                    note_id=note_id,
                    chunk_text=chunk_text,
                    chunk_index=idx,
                )
            )
            vec_rows.append((chunk_id, _float_list_to_bytes(emb)))

        Chunk.objects.bulk_create(chunk_objs)

        conn = get_vec_db()
        conn.executemany(
            "INSERT INTO vec_chunks(chunk_id, embedding) VALUES (?, ?)",
            vec_rows,
        )
        conn.commit()
        conn.close()

        with _lock:
            _ingest_state["done"] += 1

    logger.info(f"Ingest complete: {len(md_files)} files processed")

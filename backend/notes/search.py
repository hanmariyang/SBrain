import struct

import anthropic
from django.conf import settings

from .db import get_vec_db
from .models import Chunk


def _embed_query(query: str) -> list[float]:
    client = anthropic.Anthropic(api_key=settings.ANTHROPIC_API_KEY)
    response = client.embeddings.create(
        model=settings.EMBEDDING_MODEL,
        input=[query],
    )
    return response.data[0].embedding


def _float_list_to_bytes(floats: list[float]) -> bytes:
    return struct.pack(f"{len(floats)}f", *floats)


def vector_search(query: str, limit: int = 10) -> list[dict]:
    embedding = _embed_query(query)
    emb_bytes = _float_list_to_bytes(embedding)

    conn = get_vec_db()
    rows = conn.execute(
        """
        SELECT chunk_id, distance
        FROM vec_chunks
        WHERE embedding MATCH ?
        ORDER BY distance
        LIMIT ?
        """,
        (emb_bytes, limit),
    ).fetchall()
    conn.close()

    results = []
    for chunk_id, distance in rows:
        chunk = Chunk.objects.select_related("note").filter(id=chunk_id).first()
        if not chunk:
            continue
        results.append(
            {
                "note_id": chunk.note_id,
                "filename": chunk.note.filename,
                "path": chunk.note.path,
                "chunk_text": chunk.chunk_text,
                "score": 1.0 - distance,
            }
        )

    return results

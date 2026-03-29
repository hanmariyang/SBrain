"""
Brain Graph — compute 2D positions (PCA) and synapse connections
between notes based on their average embedding vectors.
"""
import math
import struct

from .db import get_vec_db
from .models import Chunk, Note


def _bytes_to_floats(data: bytes, dim: int) -> list[float]:
    return list(struct.unpack(f"{dim}f", data))


def _cosine_similarity(a: list[float], b: list[float]) -> float:
    dot = sum(x * y for x, y in zip(a, b))
    na = math.sqrt(sum(x * x for x in a))
    nb = math.sqrt(sum(x * x for x in b))
    if na == 0 or nb == 0:
        return 0.0
    return dot / (na * nb)


def _mean_vec(vectors: list[list[float]]) -> list[float]:
    if not vectors:
        return []
    dim = len(vectors[0])
    result = [0.0] * dim
    for v in vectors:
        for i in range(dim):
            result[i] += v[i]
    n = len(vectors)
    return [x / n for x in result]


def _pca_2d(vectors: list[list[float]]) -> list[tuple[float, float]]:
    """Simple PCA projection to 2D using power iteration."""
    if not vectors:
        return []
    n = len(vectors)
    dim = len(vectors[0])

    # Center the data
    mean = [0.0] * dim
    for v in vectors:
        for i in range(dim):
            mean[i] += v[i]
    mean = [m / n for m in mean]
    centered = [[v[i] - mean[i] for i in range(dim)] for v in vectors]

    # Power iteration for first principal component
    pc1 = [1.0 / math.sqrt(dim)] * dim
    for _ in range(50):
        new_pc = [0.0] * dim
        for v in centered:
            dot = sum(v[i] * pc1[i] for i in range(dim))
            for i in range(dim):
                new_pc[i] += dot * v[i]
        norm = math.sqrt(sum(x * x for x in new_pc)) or 1.0
        pc1 = [x / norm for x in new_pc]

    # Project onto PC1 and get residuals
    proj1 = [sum(v[i] * pc1[i] for i in range(dim)) for v in centered]

    residuals = [
        [centered[j][i] - proj1[j] * pc1[i] for i in range(dim)]
        for j in range(n)
    ]

    # Power iteration for second principal component
    pc2 = [1.0 / math.sqrt(dim)] * dim
    for _ in range(50):
        new_pc = [0.0] * dim
        for v in residuals:
            dot = sum(v[i] * pc2[i] for i in range(dim))
            for i in range(dim):
                new_pc[i] += dot * v[i]
        norm = math.sqrt(sum(x * x for x in new_pc)) or 1.0
        pc2 = [x / norm for x in new_pc]

    proj2 = [sum(v[i] * pc2[i] for i in range(dim)) for v in centered]

    # Normalize to 0..1
    min1 = min(proj1) if proj1 else 0
    max1 = max(proj1) if proj1 else 1
    min2 = min(proj2) if proj2 else 0
    max2 = max(proj2) if proj2 else 1
    r1 = (max1 - min1) or 1.0
    r2 = (max2 - min2) or 1.0

    return [
        ((proj1[i] - min1) / r1, (proj2[i] - min2) / r2) for i in range(n)
    ]


def _is_cloud_db() -> bool:
    """Railway(PostgreSQL) 환경인지 판별."""
    import os
    return bool(os.getenv("DATABASE_URL", ""))


def _tfidf_similarity(chunks_a: list[str], chunks_b: list[str]) -> float:
    """TF-IDF 기반 간이 유사도 (임베딩 없이)."""
    text_a = " ".join(chunks_a).lower()
    text_b = " ".join(chunks_b).lower()
    words_a = set(text_a.split())
    words_b = set(text_b.split())
    if not words_a or not words_b:
        return 0.0
    intersection = words_a & words_b
    union = words_a | words_b
    return len(intersection) / len(union)  # Jaccard similarity


def _build_cloud_graph(notes, similarity_threshold: float) -> dict:
    """Railway 환경: 임베딩 없이 청크 텍스트 기반 그래프 생성."""
    # 노트별 청크 수집
    note_chunks: dict[str, list[str]] = {}
    for note in notes:
        chunks = list(
            Chunk.objects.filter(note=note).values_list("chunk_text", flat=True)
        )
        if chunks:
            note_chunks[note.id] = chunks

    active_notes = [n for n in notes if n.id in note_chunks]
    if not active_notes:
        # 청크가 없어도 노트 자체로 뉴런 생성
        active_notes = notes
        for note in notes:
            note_chunks[note.id] = [note.content[:500]] if note.content else []

    # Fibonacci Sphere 분포 (클라이언트와 동일한 3D 레이아웃)
    n = len(active_notes)
    golden = (1 + math.sqrt(5)) / 2
    positions = []
    for i in range(n):
        theta = math.acos(1 - 2 * (i + 0.5) / max(n, 1))
        phi = 2 * math.pi * i / golden
        x = (phi % (2 * math.pi)) / (2 * math.pi)
        y = theta / math.pi
        positions.append((round(x, 4), round(y, 4)))

    # 뉴런 생성
    neurons = []
    for i, note in enumerate(active_notes):
        x, y = positions[i] if i < len(positions) else (0.5, 0.5)
        preview_lines = (note.content or "").strip().splitlines()
        preview = preview_lines[0][:100] if preview_lines else ""
        neurons.append({
            "id": note.id,
            "filename": note.filename,
            "preview": preview,
            "x": x,
            "y": y,
            "chunk_count": len(note_chunks.get(note.id, [])),
        })

    # 시냅스 생성 (TF-IDF Jaccard 유사도)
    synapses = []
    for i in range(len(active_notes)):
        for j in range(i + 1, len(active_notes)):
            sim = _tfidf_similarity(
                note_chunks.get(active_notes[i].id, []),
                note_chunks.get(active_notes[j].id, []),
            )
            if sim >= similarity_threshold:
                synapses.append({
                    "source": active_notes[i].id,
                    "target": active_notes[j].id,
                    "strength": round(sim, 4),
                })

    return {"neurons": neurons, "synapses": synapses}


def build_brain_graph(similarity_threshold: float = 0.5) -> dict:
    """
    Returns:
      {
        "neurons": [{ "id", "filename", "preview", "x", "y", "chunk_count" }],
        "synapses": [{ "source", "target", "strength" }]
      }
    """
    from django.conf import settings

    notes = list(Note.objects.all())
    if not notes:
        return {"neurons": [], "synapses": []}

    # Railway(PostgreSQL): sqlite-vec 사용 불가 → TF-IDF 기반
    if _is_cloud_db():
        return _build_cloud_graph(notes, similarity_threshold)

    # 로컬(SQLite): sqlite-vec 임베딩 기반
    try:
        conn = get_vec_db()
    except Exception:
        # sqlite-vec 로드 실패 시 TF-IDF 폴백
        return _build_cloud_graph(notes, similarity_threshold)

    dim = settings.EMBEDDING_DIMENSION

    # Collect average embedding per note
    note_embeddings: dict[str, list[float]] = {}
    note_chunk_counts: dict[str, int] = {}

    for note in notes:
        chunk_ids = list(
            Chunk.objects.filter(note=note).values_list("id", flat=True)
        )
        if not chunk_ids:
            continue

        vectors = []
        for cid in chunk_ids:
            row = conn.execute(
                "SELECT embedding FROM vec_chunks WHERE chunk_id = ?", (cid,)
            ).fetchone()
            if row:
                vectors.append(_bytes_to_floats(row[0], dim))

        if vectors:
            note_embeddings[note.id] = _mean_vec(vectors)
            note_chunk_counts[note.id] = len(vectors)

    conn.close()

    # Filter notes that have embeddings
    active_notes = [n for n in notes if n.id in note_embeddings]
    if not active_notes:
        # 임베딩이 없으면 TF-IDF 폴백
        return _build_cloud_graph(notes, similarity_threshold)

    # PCA 2D projection
    vecs = [note_embeddings[n.id] for n in active_notes]
    positions = _pca_2d(vecs)

    # Build neurons
    neurons = []
    for i, note in enumerate(active_notes):
        x, y = positions[i] if i < len(positions) else (0.5, 0.5)
        preview_lines = note.content.strip().splitlines()
        preview = preview_lines[0][:100] if preview_lines else ""
        neurons.append(
            {
                "id": note.id,
                "filename": note.filename,
                "preview": preview,
                "x": round(x, 4),
                "y": round(y, 4),
                "chunk_count": note_chunk_counts.get(note.id, 0),
            }
        )

    # Build synapses (edges between similar notes)
    synapses = []
    for i in range(len(active_notes)):
        for j in range(i + 1, len(active_notes)):
            sim = _cosine_similarity(
                note_embeddings[active_notes[i].id],
                note_embeddings[active_notes[j].id],
            )
            if sim >= similarity_threshold:
                synapses.append(
                    {
                        "source": active_notes[i].id,
                        "target": active_notes[j].id,
                        "strength": round(sim, 4),
                    }
                )

    return {"neurons": neurons, "synapses": synapses}

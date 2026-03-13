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

    conn = get_vec_db()
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
        return {"neurons": [], "synapses": []}

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

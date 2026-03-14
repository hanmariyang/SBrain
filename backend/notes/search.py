import math
import re

from .models import Note


def search(query: str, limit: int = 10) -> list[dict]:
    """Local keyword search with TF-IDF-like scoring.

    No external API required. Searches note content stored in the DB.
    """
    query_terms = _tokenize(query)
    if not query_terms:
        return []

    notes = Note.objects.all()
    if not notes.exists():
        return []

    total_docs = notes.count()
    scored: list[tuple] = []

    for note in notes:
        content = (note.content or "").lower()
        if not content:
            continue

        words = content.split()
        doc_len = max(len(words), 1)
        score = 0.0
        best_context = ""

        for term in query_terms:
            count = content.count(term)
            if count == 0:
                continue

            # TF-IDF: term frequency normalized by doc length * log(N)
            tf = count / doc_len
            idf = math.log(total_docs + 1)
            score += tf * idf

            # Extract context around first match
            if not best_context:
                idx = content.find(term)
                start = max(0, idx - 60)
                end = min(len(content), idx + len(term) + 140)
                # Try to start at word boundary
                if start > 0:
                    space = content.rfind(" ", start - 20, start + 10)
                    if space > 0:
                        start = space + 1
                best_context = content[start:end].strip()

        if score > 0:
            scored.append((note, score, best_context))

    if not scored:
        return []

    # Sort by score descending
    scored.sort(key=lambda x: x[1], reverse=True)
    scored = scored[:limit]

    # Normalize scores to 0~1
    max_score = scored[0][1]
    results = []
    for note, raw_score, context in scored:
        normalized = min(raw_score / max_score, 1.0) if max_score > 0 else 0.0
        results.append(
            {
                "note_id": note.id,
                "filename": note.filename,
                "path": note.path,
                "chunk_text": context or (note.content or "")[:200],
                "score": round(normalized, 3),
            }
        )

    return results


def _tokenize(text: str) -> list[str]:
    """Split query into lowercase search terms."""
    text = text.lower().strip()
    # Split by whitespace and filter short terms
    terms = [t for t in re.split(r"\s+", text) if len(t) >= 1]
    return terms

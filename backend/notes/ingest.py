import hashlib
import logging
import os
import threading
from datetime import datetime, timezone
from pathlib import Path

from django.conf import settings

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

# Supported file extensions
SUPPORTED_EXTENSIONS = ("*.md", "*.html", "*.htm")


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
    root = Path(folder_path)
    all_files = []
    for ext in SUPPORTED_EXTENSIONS:
        all_files.extend(root.rglob(ext))

    with _lock:
        _ingest_state["total"] = len(all_files)

    for file_path_obj in all_files:
        file_path = str(file_path_obj.resolve())
        with _lock:
            _ingest_state["current_file"] = file_path_obj.name

        try:
            content = file_path_obj.read_text(encoding="utf-8")
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

        # Save note content to DB
        Note.objects.update_or_create(
            id=note_id,
            defaults={
                "path": file_path,
                "filename": file_path_obj.name,
                "content": content,
            },
        )

        # Save chunks (for future vector search upgrade)
        Chunk.objects.filter(note_id=note_id).delete()
        chunks = _split_chunks(content)

        if chunks:
            chunk_objs = []
            for idx, chunk_text in enumerate(chunks):
                chunk_id = f"{note_id}_{idx}"
                chunk_objs.append(
                    Chunk(
                        id=chunk_id,
                        note_id=note_id,
                        chunk_text=chunk_text,
                        chunk_index=idx,
                    )
                )
            Chunk.objects.bulk_create(chunk_objs)

        with _lock:
            _ingest_state["done"] += 1

    logger.info(f"Ingest complete: {len(all_files)} files processed")


def partial_ingest_files(paths: list[str], deleted_paths: list[str]) -> dict:
    """변경된 파일만 부분 인덱싱. 동기 실행 (파일 수가 적으므로)."""
    updated = 0
    deleted = 0
    errors = []

    # 1. 삭제된 파일 처리
    for file_path in deleted_paths:
        try:
            note_id = Note.make_id(file_path)
            Chunk.objects.filter(note_id=note_id).delete()
            Note.objects.filter(id=note_id).delete()
            deleted += 1
        except Exception as e:
            errors.append({"path": file_path, "error": str(e)})

    # 2. 추가/수정된 파일 처리
    for file_path in paths:
        try:
            file_path_obj = Path(file_path)
            if not file_path_obj.exists():
                continue

            content = file_path_obj.read_text(encoding="utf-8")
            note_id = Note.make_id(file_path)

            # Note upsert
            Note.objects.update_or_create(
                id=note_id,
                defaults={
                    "path": file_path,
                    "filename": file_path_obj.name,
                    "content": content,
                },
            )

            # 기존 Chunk 삭제 후 재생성
            Chunk.objects.filter(note_id=note_id).delete()
            chunks = _split_chunks(content)

            if chunks:
                chunk_objs = [
                    Chunk(
                        id=f"{note_id}_{idx}",
                        note_id=note_id,
                        chunk_text=chunk_text,
                        chunk_index=idx,
                    )
                    for idx, chunk_text in enumerate(chunks)
                ]
                Chunk.objects.bulk_create(chunk_objs)

            updated += 1
        except Exception as e:
            errors.append({"path": file_path, "error": str(e)})

    logger.info("Partial ingest: updated=%d, deleted=%d, errors=%d", updated, deleted, len(errors))
    return {"updated": updated, "deleted": deleted, "errors": errors}

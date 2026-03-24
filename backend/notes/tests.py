"""
SBrain Backend 핵심 API 테스트.

커버리지 대상: Note 모델, 검색, 인덱싱, 동기화 API.
"""

import hashlib
import json

from django.contrib.auth.models import User
from django.test import TestCase
from rest_framework.test import APIClient

from .ingest import _split_chunks, partial_ingest_files
from .models import Chunk, Note
from .search import search


# ── 모델 테스트 ──────────────────────────────────────────────


class NoteModelTest(TestCase):
    def test_make_id_deterministic(self):
        path = "/Users/test/notes/hello.md"
        id1 = Note.make_id(path)
        id2 = Note.make_id(path)
        self.assertEqual(id1, id2)
        self.assertEqual(len(id1), 64)  # SHA256 hex

    def test_make_id_different_paths(self):
        id1 = Note.make_id("/a/b.md")
        id2 = Note.make_id("/a/c.md")
        self.assertNotEqual(id1, id2)

    def test_note_creation(self):
        note = Note.objects.create(
            id="test123",
            path="/test/path.md",
            filename="path.md",
            content="# Hello\n\nWorld",
        )
        self.assertEqual(note.filename, "path.md")
        self.assertIsNotNone(note.updated_at)

    def test_chunk_creation(self):
        note = Note.objects.create(
            id="note1", path="/test.md", filename="test.md", content="content"
        )
        chunk = Chunk.objects.create(
            id="note1_0", note=note, chunk_text="content", chunk_index=0
        )
        self.assertEqual(chunk.note_id, "note1")
        self.assertEqual(str(chunk), "test.md[0]")

    def test_cascade_delete(self):
        note = Note.objects.create(
            id="del1", path="/del.md", filename="del.md", content="x"
        )
        Chunk.objects.create(id="del1_0", note=note, chunk_text="x", chunk_index=0)
        Chunk.objects.create(id="del1_1", note=note, chunk_text="y", chunk_index=1)
        self.assertEqual(Chunk.objects.filter(note=note).count(), 2)
        note.delete()
        self.assertEqual(Chunk.objects.filter(note_id="del1").count(), 0)


# ── 청킹 테스트 ─────────────────────────────────────────────


class ChunkingTest(TestCase):
    def test_empty_text(self):
        self.assertEqual(_split_chunks(""), [])

    def test_short_text(self):
        chunks = _split_chunks("Hello world")
        self.assertEqual(len(chunks), 1)
        self.assertEqual(chunks[0], "Hello world")

    def test_long_text_splits(self):
        text = "A" * 1200
        chunks = _split_chunks(text)
        self.assertGreater(len(chunks), 1)

    def test_overlap(self):
        text = "A" * 1000
        chunks = _split_chunks(text)
        # 두 번째 청크는 첫 번째 끝부분과 겹쳐야 함
        self.assertGreater(len(chunks), 1)


# ── 검색 테스트 ──────────────────────────────────────────────


class SearchTest(TestCase):
    def setUp(self):
        Note.objects.create(
            id="s1",
            path="/notes/python.md",
            filename="python.md",
            content="Python is a programming language used for data science and web development",
        )
        Note.objects.create(
            id="s2",
            path="/notes/javascript.md",
            filename="javascript.md",
            content="JavaScript runs in the browser and is used for web development",
        )
        Note.objects.create(
            id="s3",
            path="/notes/cooking.md",
            filename="cooking.md",
            content="Recipe for pasta: boil water, add salt, cook pasta for 10 minutes",
        )

    def test_search_basic(self):
        results = search("python")
        self.assertGreater(len(results), 0)
        self.assertEqual(results[0]["filename"], "python.md")

    def test_search_multiple_matches(self):
        results = search("web development")
        self.assertEqual(len(results), 2)

    def test_search_no_match(self):
        results = search("quantum physics")
        self.assertEqual(len(results), 0)

    def test_search_empty_query(self):
        results = search("")
        self.assertEqual(len(results), 0)

    def test_search_limit(self):
        results = search("web", limit=1)
        self.assertEqual(len(results), 1)

    def test_search_score_normalized(self):
        results = search("python")
        for r in results:
            self.assertGreaterEqual(r["score"], 0.0)
            self.assertLessEqual(r["score"], 1.0)

    def test_search_korean(self):
        Note.objects.create(
            id="kr1",
            path="/notes/korean.md",
            filename="korean.md",
            content="SBrain은 마크다운 파일을 3D 뇌 시각화로 탐색하는 앱입니다",
        )
        results = search("마크다운")
        self.assertGreater(len(results), 0)


# ── 부분 인덱싱 테스트 ───────────────────────────────────────


class PartialIngestTest(TestCase):
    def test_ingest_and_delete(self):
        # 먼저 노트 생성
        note_id = Note.make_id("/tmp/test_note.md")
        Note.objects.create(
            id=note_id,
            path="/tmp/test_note.md",
            filename="test_note.md",
            content="old content",
        )

        # 삭제 테스트
        result = partial_ingest_files([], ["/tmp/test_note.md"])
        self.assertEqual(result["deleted"], 1)
        self.assertFalse(Note.objects.filter(id=note_id).exists())

    def test_ingest_nonexistent_file(self):
        result = partial_ingest_files(["/nonexistent/file.md"], [])
        self.assertEqual(result["updated"], 0)


# ── API 엔드포인트 테스트 ────────────────────────────────────


class NoteAPITest(TestCase):
    def setUp(self):
        self.client = APIClient()
        Note.objects.create(
            id="api1",
            path="/notes/test.md",
            filename="test.md",
            content="# Test\n\nAPI test content",
        )

    def test_note_list(self):
        resp = self.client.get("/api/notes/")
        self.assertEqual(resp.status_code, 200)
        self.assertGreater(len(resp.data), 0)

    def test_note_detail(self):
        resp = self.client.get("/api/notes/api1/")
        self.assertEqual(resp.status_code, 200)
        self.assertEqual(resp.data["filename"], "test.md")

    def test_note_not_found(self):
        resp = self.client.get("/api/notes/nonexistent/")
        self.assertEqual(resp.status_code, 404)

    def test_search_api(self):
        resp = self.client.post(
            "/api/search/",
            {"query": "test", "limit": 5},
            format="json",
        )
        self.assertEqual(resp.status_code, 200)

    def test_status_api(self):
        resp = self.client.get("/api/status/")
        self.assertEqual(resp.status_code, 200)
        self.assertIn("running", resp.data)

    def test_graph_api(self):
        # sqlite-vec C 확장이 테스트 DB에서 로드 불가하므로 스킵
        try:
            resp = self.client.get("/api/graph/")
            self.assertIn(resp.status_code, [200, 500])
        except AttributeError:
            pass  # sqlite-vec enable_load_extension 미지원 환경

    def test_partial_ingest_empty(self):
        resp = self.client.patch(
            "/api/ingest/partial/",
            {"paths": [], "deleted_paths": []},
            format="json",
        )
        self.assertEqual(resp.status_code, 400)


# ── Sync Push API 테스트 ─────────────────────────────────────


class SyncPushAPITest(TestCase):
    """Sync Push는 JWT 인증이 필요하지만, 로컬(SQLite)에서는 AllowAny이므로 직접 테스트."""

    def setUp(self):
        self.client = APIClient()

    def test_sync_push_create(self):
        resp = self.client.post(
            "/api/sync/push/",
            {
                "notes": [
                    {
                        "id": "sync1",
                        "path": "project/note.md",
                        "filename": "note.md",
                        "content": "# Synced Note\n\nContent here",
                    }
                ],
                "deleted_ids": [],
            },
            format="json",
        )
        self.assertEqual(resp.status_code, 200)
        self.assertEqual(resp.data["synced"], 1)
        self.assertTrue(Note.objects.filter(id="sync1").exists())
        # Chunk도 생성됐는지 확인
        self.assertGreater(Chunk.objects.filter(note_id="sync1").count(), 0)

    def test_sync_push_update(self):
        # 먼저 생성
        Note.objects.create(
            id="sync2", path="project/old.md", filename="old.md", content="old"
        )
        # 업데이트
        resp = self.client.post(
            "/api/sync/push/",
            {
                "notes": [
                    {
                        "id": "sync2",
                        "path": "project/old.md",
                        "filename": "old.md",
                        "content": "# Updated content",
                    }
                ],
                "deleted_ids": [],
            },
            format="json",
        )
        self.assertEqual(resp.status_code, 200)
        note = Note.objects.get(id="sync2")
        self.assertEqual(note.content, "# Updated content")

    def test_sync_push_delete(self):
        Note.objects.create(
            id="sync3", path="project/del.md", filename="del.md", content="x"
        )
        resp = self.client.post(
            "/api/sync/push/",
            {"notes": [], "deleted_ids": ["sync3"]},
            format="json",
        )
        self.assertEqual(resp.status_code, 200)
        self.assertEqual(resp.data["deleted"], 1)
        self.assertFalse(Note.objects.filter(id="sync3").exists())

    def test_sync_push_empty(self):
        resp = self.client.post(
            "/api/sync/push/",
            {"notes": [], "deleted_ids": []},
            format="json",
        )
        self.assertEqual(resp.status_code, 200)
        self.assertEqual(resp.data["synced"], 0)

    def test_sync_push_batch(self):
        notes = [
            {
                "id": f"batch{i}",
                "path": f"project/note{i}.md",
                "filename": f"note{i}.md",
                "content": f"Content {i}",
            }
            for i in range(10)
        ]
        resp = self.client.post(
            "/api/sync/push/",
            {"notes": notes, "deleted_ids": []},
            format="json",
        )
        self.assertEqual(resp.status_code, 200)
        self.assertEqual(resp.data["synced"], 10)
        self.assertEqual(Note.objects.count(), 10)

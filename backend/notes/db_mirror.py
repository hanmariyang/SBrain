"""
Mirror a remote PostgreSQL database into the local SBrain cache PG.
Uses pg_dump/pg_restore for a full database clone.
"""

import hashlib
import subprocess
import threading
import time
from urllib.parse import urlparse, urlunparse

import psycopg2
from django.conf import settings


# ── Status tracking ──────────────────────────────────────────

_status: dict = {
    "running": False,
    "phase": "",        # "dumping", "restoring", "done", "error"
    "progress": "",     # human-readable progress
    "remote_url": "",
    "local_db": "",
    "started_at": 0,
    "finished_at": 0,
    "error": None,
}
_lock = threading.Lock()


def get_status() -> dict:
    with _lock:
        s = dict(_status)
    if s["running"]:
        s["elapsed"] = round(time.time() - s["started_at"])
    return s


def _set_status(**kwargs):
    with _lock:
        _status.update(kwargs)


# ── Naming ───────────────────────────────────────────────────

def _db_hash(url: str) -> str:
    return hashlib.sha256(url.encode()).hexdigest()[:12]


def mirror_db_name(remote_url: str) -> str:
    """Deterministic local DB name for a given remote URL."""
    return f"sbrain_m_{_db_hash(remote_url)}"


# ── Cache PG connection (admin) ──────────────────────────────

def _cache_admin_url() -> str:
    """Connect to the cache PG server's 'postgres' DB for admin operations."""
    url = getattr(settings, "CACHE_DB_URL", "postgresql://sbrain:sbrain@localhost:5434/sbrain_cache")
    parsed = urlparse(url)
    return urlunparse(parsed._replace(path="/postgres"))


def _cache_server_url(dbname: str) -> str:
    """Build a URL to a specific DB on the cache PG server."""
    url = getattr(settings, "CACHE_DB_URL", "postgresql://sbrain:sbrain@localhost:5434/sbrain_cache")
    parsed = urlparse(url)
    return urlunparse(parsed._replace(path=f"/{dbname}"))


def _cache_pg_env() -> dict:
    """Extract host/port/user/password from CACHE_DB_URL for pg_restore."""
    url = getattr(settings, "CACHE_DB_URL", "postgresql://sbrain:sbrain@localhost:5434/sbrain_cache")
    parsed = urlparse(url)
    env = {}
    if parsed.hostname:
        env["PGHOST"] = parsed.hostname
    if parsed.port:
        env["PGPORT"] = str(parsed.port)
    if parsed.username:
        env["PGUSER"] = parsed.username
    if parsed.password:
        env["PGPASSWORD"] = parsed.password
    return env


# ── Mirror operations ────────────────────────────────────────

def get_local_url(remote_url: str) -> str | None:
    """Return local mirror URL if the mirror DB exists, else None."""
    db_name = mirror_db_name(remote_url)
    try:
        conn = psycopg2.connect(_cache_admin_url())
        conn.set_session(autocommit=True)
        with conn.cursor() as cur:
            cur.execute("SELECT 1 FROM pg_database WHERE datname = %s", [db_name])
            exists = cur.fetchone() is not None
        conn.close()
        if exists:
            return _cache_server_url(db_name)
    except Exception:
        pass
    return None


def start_download(remote_url: str):
    """Start a background thread to mirror the remote DB locally."""
    if _status["running"]:
        return

    db_name = mirror_db_name(remote_url)
    _set_status(
        running=True,
        phase="starting",
        progress="다운로드 준비 중...",
        remote_url=remote_url,
        local_db=db_name,
        started_at=time.time(),
        finished_at=0,
        error=None,
    )

    thread = threading.Thread(target=_do_download, args=(remote_url, db_name), daemon=True)
    thread.start()


def _do_download(remote_url: str, db_name: str):
    """Worker: pg_dump remote → pg_restore local."""
    import os

    try:
        # 1. Drop existing mirror DB if present
        _set_status(phase="preparing", progress="기존 미러 정리 중...")
        try:
            conn = psycopg2.connect(_cache_admin_url())
            conn.set_session(autocommit=True)
            with conn.cursor() as cur:
                # Terminate existing connections
                cur.execute("""
                    SELECT pg_terminate_backend(pid)
                    FROM pg_stat_activity
                    WHERE datname = %s AND pid <> pg_backend_pid()
                """, [db_name])
                cur.execute(f'DROP DATABASE IF EXISTS "{db_name}"')
            conn.close()
        except Exception as e:
            _set_status(running=False, phase="error", error=f"미러 정리 실패: {e}")
            return

        # 2. Create empty target DB
        _set_status(phase="preparing", progress="로컬 DB 생성 중...")
        try:
            conn = psycopg2.connect(_cache_admin_url())
            conn.set_session(autocommit=True)
            with conn.cursor() as cur:
                cur.execute(f'CREATE DATABASE "{db_name}"')
            conn.close()
        except Exception as e:
            _set_status(running=False, phase="error", error=f"로컬 DB 생성 실패: {e}")
            return

        # 3. pg_dump from remote
        _set_status(phase="dumping", progress="원격 DB 덤프 중...")
        env = dict(os.environ)
        dump_cmd = [
            "pg_dump",
            "--format=custom",
            "--no-owner",
            "--no-privileges",
            "--no-comments",
            remote_url,
        ]
        dump_proc = subprocess.Popen(
            dump_cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE, env=env
        )

        # 4. pg_restore to local
        _set_status(phase="restoring", progress="로컬 DB에 복원 중...")
        restore_env = dict(os.environ)
        restore_env.update(_cache_pg_env())

        restore_cmd = [
            "pg_restore",
            "--dbname", db_name,
            "--no-owner",
            "--no-privileges",
            "--single-transaction",
        ]
        restore_proc = subprocess.Popen(
            restore_cmd,
            stdin=dump_proc.stdout,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            env=restore_env,
        )

        # Close dump stdout in parent so restore gets EOF when dump finishes
        dump_proc.stdout.close()

        _, restore_err = restore_proc.communicate(timeout=600)
        dump_proc.wait(timeout=10)

        if dump_proc.returncode != 0:
            _, dump_err = dump_proc.communicate()
            err_msg = dump_err.decode(errors="replace").strip() if dump_err else "pg_dump failed"
            _set_status(running=False, phase="error", error=f"덤프 실패: {err_msg}")
            return

        # pg_restore returns non-zero for warnings too, check for actual errors
        if restore_proc.returncode != 0:
            err_text = restore_err.decode(errors="replace").strip() if restore_err else ""
            # Ignore common warnings (e.g., role doesn't exist)
            if "FATAL" in err_text or "could not connect" in err_text:
                _set_status(running=False, phase="error", error=f"복원 실패: {err_text[:300]}")
                return

        # 5. Verify
        _set_status(phase="verifying", progress="검증 중...")
        try:
            local_url = _cache_server_url(db_name)
            conn = psycopg2.connect(local_url)
            with conn.cursor() as cur:
                cur.execute("""
                    SELECT COUNT(*) FROM information_schema.tables
                    WHERE table_schema NOT IN ('pg_catalog', 'information_schema', 'pg_toast')
                      AND table_type IN ('BASE TABLE', 'VIEW')
                """)
                table_count = cur.fetchone()[0]
            conn.close()
            _set_status(
                running=False,
                phase="done",
                progress=f"완료: {table_count}개 테이블 복제됨",
                finished_at=time.time(),
            )
        except Exception as e:
            _set_status(running=False, phase="error", error=f"검증 실패: {e}")

    except subprocess.TimeoutExpired:
        _set_status(running=False, phase="error", error="타임아웃 (10분 초과)")
    except Exception as e:
        _set_status(running=False, phase="error", error=str(e))


def delete_mirror(remote_url: str):
    """Delete the local mirror database."""
    db_name = mirror_db_name(remote_url)
    try:
        conn = psycopg2.connect(_cache_admin_url())
        conn.set_session(autocommit=True)
        with conn.cursor() as cur:
            cur.execute("""
                SELECT pg_terminate_backend(pid)
                FROM pg_stat_activity
                WHERE datname = %s AND pid <> pg_backend_pid()
            """, [db_name])
            cur.execute(f'DROP DATABASE IF EXISTS "{db_name}"')
        conn.close()
    except Exception:
        pass

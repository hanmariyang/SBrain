import sqlite3

import sqlite_vec
from django.conf import settings


def get_vec_db() -> sqlite3.Connection:
    db_path = str(settings.DATABASES["default"]["NAME"])
    conn = sqlite3.connect(db_path)
    conn.enable_load_extension(True)
    sqlite_vec.load(conn)
    conn.enable_load_extension(False)
    return conn


def init_vec_table():
    conn = get_vec_db()
    dim = settings.EMBEDDING_DIMENSION
    conn.execute(
        f"""
        CREATE VIRTUAL TABLE IF NOT EXISTS vec_chunks USING vec0(
            chunk_id TEXT PRIMARY KEY,
            embedding FLOAT[{dim}]
        )
        """
    )
    conn.commit()
    conn.close()

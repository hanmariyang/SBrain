"""
PostgreSQL read-only database browser.
If a local mirror exists (via db_mirror), queries go to the local copy.
Otherwise, queries go directly to the remote DB (read-only).
"""

import math

import psycopg2
import psycopg2.extras
from psycopg2 import sql

from . import db_mirror


def _resolve_url(remote_url: str) -> tuple[str, bool]:
    """Return (url_to_query, is_local). Prefer local mirror if available."""
    local = db_mirror.get_local_url(remote_url)
    if local:
        return local, True
    return remote_url, False


def _connect(connection_url: str, readonly: bool = True):
    """Open a connection. Read-only for remote, normal for local mirror."""
    conn = psycopg2.connect(connection_url)
    if readonly:
        conn.set_session(readonly=True, autocommit=True)
    else:
        conn.set_session(autocommit=True)
    with conn.cursor() as cur:
        cur.execute("SET statement_timeout = '10s';")
    return conn


# ── Connection test ──────────────────────────────────────────

def test_connection(connection_url: str) -> dict:
    try:
        conn = _connect(connection_url)
        with conn.cursor() as cur:
            cur.execute("SELECT version(), current_database();")
            row = cur.fetchone()
        conn.close()

        # Check if local mirror exists
        local_url = db_mirror.get_local_url(connection_url)

        return {
            "ok": True,
            "server_version": row[0],
            "database": row[1],
            "error": None,
            "has_local_mirror": local_url is not None,
        }
    except Exception as e:
        return {
            "ok": False, "server_version": None, "database": None,
            "error": str(e), "has_local_mirror": False,
        }


# ── Schema list ──────────────────────────────────────────────

def list_schemas(connection_url: str) -> list[dict]:
    url, is_local = _resolve_url(connection_url)
    conn = _connect(url, readonly=not is_local)
    with conn.cursor(cursor_factory=psycopg2.extras.RealDictCursor) as cur:
        cur.execute("""
            SELECT s.schema_name AS name,
                   COUNT(t.table_name) AS table_count
            FROM information_schema.schemata s
            LEFT JOIN information_schema.tables t
                ON t.table_schema = s.schema_name
                AND t.table_type IN ('BASE TABLE', 'VIEW')
            WHERE s.schema_name NOT IN ('pg_catalog', 'information_schema', 'pg_toast')
              AND s.schema_name NOT LIKE 'pg_temp_%'
            GROUP BY s.schema_name
            ORDER BY s.schema_name;
        """)
        rows = cur.fetchall()
    conn.close()
    return [dict(r) for r in rows]


# ── Table list ───────────────────────────────────────────────

def list_tables(connection_url: str, schema: str = "public") -> list[dict]:
    url, is_local = _resolve_url(connection_url)
    conn = _connect(url, readonly=not is_local)
    with conn.cursor(cursor_factory=psycopg2.extras.RealDictCursor) as cur:
        cur.execute("""
            SELECT t.table_name AS name,
                   t.table_schema AS schema,
                   t.table_type AS type,
                   (SELECT COUNT(*) FROM information_schema.columns c
                    WHERE c.table_schema = t.table_schema AND c.table_name = t.table_name
                   ) AS column_count,
                   COALESCE(pg_c.reltuples, 0)::bigint AS row_estimate
            FROM information_schema.tables t
            LEFT JOIN pg_catalog.pg_class pg_c
                ON pg_c.relname = t.table_name
                AND pg_c.relnamespace = (
                    SELECT oid FROM pg_catalog.pg_namespace WHERE nspname = t.table_schema
                )
            WHERE t.table_schema = %s
              AND t.table_type IN ('BASE TABLE', 'VIEW')
            ORDER BY t.table_name;
        """, [schema])
        rows = cur.fetchall()
    conn.close()
    return [dict(r) for r in rows]


# ── Column list ──────────────────────────────────────────────

def list_columns(connection_url: str, schema: str, table: str) -> list[dict]:
    url, is_local = _resolve_url(connection_url)
    conn = _connect(url, readonly=not is_local)
    with conn.cursor(cursor_factory=psycopg2.extras.RealDictCursor) as cur:
        cur.execute("""
            SELECT column_name AS name,
                   data_type AS type,
                   (is_nullable = 'YES') AS nullable,
                   column_default AS "default",
                   ordinal_position AS ordinal
            FROM information_schema.columns
            WHERE table_schema = %s AND table_name = %s
            ORDER BY ordinal_position;
        """, [schema, table])
        rows = cur.fetchall()
    conn.close()
    return [dict(r) for r in rows]


# ── Row data ─────────────────────────────────────────────────

MAX_LIMIT = 1000
DEFAULT_LIMIT = 200


def fetch_rows(connection_url: str, schema: str, table: str,
               limit: int = DEFAULT_LIMIT, offset: int = 0) -> dict:
    limit = max(1, min(limit, MAX_LIMIT))
    offset = max(0, offset)

    url, is_local = _resolve_url(connection_url)
    conn = _connect(url, readonly=not is_local)
    ident = sql.SQL("{}.{}").format(sql.Identifier(schema), sql.Identifier(table))

    with conn.cursor() as cur:
        cur.execute(
            sql.SQL("SELECT reltuples::bigint FROM pg_class WHERE relname = {} AND relnamespace = "
                     "(SELECT oid FROM pg_namespace WHERE nspname = {})").format(
                sql.Literal(table), sql.Literal(schema)
            )
        )
        est_row = cur.fetchone()
        total_estimate = est_row[0] if est_row else 0

        cur.execute(
            sql.SQL("SELECT column_name FROM information_schema.columns "
                     "WHERE table_schema = {} AND table_name = {} ORDER BY ordinal_position").format(
                sql.Literal(schema), sql.Literal(table)
            )
        )
        columns = [r[0] for r in cur.fetchall()]

        cur.execute(
            sql.SQL("SELECT * FROM {} LIMIT {} OFFSET {}").format(
                ident, sql.Literal(limit), sql.Literal(offset)
            )
        )
        rows = cur.fetchall()

    conn.close()

    safe_rows = []
    for row in rows:
        safe_rows.append([_to_json(v) for v in row])

    return {
        "columns": columns,
        "rows": safe_rows,
        "total_estimate": max(0, total_estimate),
        "limit": limit,
        "offset": offset,
        "is_local": is_local,
    }


def _to_json(value):
    if value is None:
        return None
    if isinstance(value, (int, float, bool, str)):
        return value
    if isinstance(value, bytes):
        return f"<bytes:{len(value)}>"
    return str(value)


# ── Brain Graph for DB tables ────────────────────────────────

def build_db_graph(connection_url: str) -> dict:
    url, is_local = _resolve_url(connection_url)
    conn = _connect(url, readonly=not is_local)
    database = ""
    with conn.cursor() as cur:
        cur.execute("SELECT current_database();")
        database = cur.fetchone()[0]

    with conn.cursor(cursor_factory=psycopg2.extras.RealDictCursor) as cur:
        cur.execute("""
            SELECT t.table_schema AS schema, t.table_name AS name,
                   t.table_type AS type,
                   (SELECT COUNT(*) FROM information_schema.columns c
                    WHERE c.table_schema = t.table_schema AND c.table_name = t.table_name
                   ) AS column_count,
                   COALESCE(pg_c.reltuples, 0)::bigint AS row_estimate
            FROM information_schema.tables t
            LEFT JOIN pg_catalog.pg_class pg_c
                ON pg_c.relname = t.table_name
                AND pg_c.relnamespace = (
                    SELECT oid FROM pg_catalog.pg_namespace WHERE nspname = t.table_schema
                )
            WHERE t.table_schema NOT IN ('pg_catalog', 'information_schema', 'pg_toast')
              AND t.table_schema NOT LIKE 'pg_temp_%%'
              AND t.table_type IN ('BASE TABLE', 'VIEW')
            ORDER BY t.table_schema, t.table_name;
        """)
        tables = [dict(r) for r in cur.fetchall()]

    with conn.cursor(cursor_factory=psycopg2.extras.RealDictCursor) as cur:
        cur.execute("""
            SELECT
                tc.table_schema AS from_schema,
                tc.table_name AS from_table,
                ccu.table_schema AS to_schema,
                ccu.table_name AS to_table
            FROM information_schema.table_constraints tc
            JOIN information_schema.constraint_column_usage ccu
                ON tc.constraint_name = ccu.constraint_name
                AND tc.constraint_schema = ccu.constraint_schema
            WHERE tc.constraint_type = 'FOREIGN KEY'
              AND tc.table_schema NOT IN ('pg_catalog', 'information_schema');
        """)
        fk_rows = [dict(r) for r in cur.fetchall()]

    conn.close()

    schemas = {}
    for t in tables:
        schemas.setdefault(t["schema"], []).append(t)

    schema_list = sorted(schemas.keys())
    schema_count = len(schema_list)

    neurons = []
    neuron_ids = set()
    golden_ratio = (1.0 + math.sqrt(5.0)) / 2.0

    for schema_idx, schema_name in enumerate(schema_list):
        schema_tables = schemas[schema_name]
        total_in_schema = len(schema_tables)

        if schema_count <= 1:
            scx, scy, scz = 0.0, 0.0, 0.0
            radius = 1.0
        else:
            angle = (schema_idx / schema_count) * 2.0 * math.pi
            scx = math.cos(angle) * 0.5
            scy = 0.0
            scz = math.sin(angle) * 0.5
            radius = 0.6 / math.sqrt(schema_count)

        for idx, tbl in enumerate(schema_tables):
            nid = f"db:{schema_name}.{tbl['name']}"
            neuron_ids.add(nid)

            i = float(idx)
            n = float(max(total_in_schema, 1))
            y = 1.0 - (i / max(n - 1, 1)) * 2.0
            r_at_y = math.sqrt(max(0, 1.0 - y * y))
            theta = 2.0 * math.pi * i / golden_ratio
            fx = math.cos(theta) * r_at_y
            fz = math.sin(theta) * r_at_y

            neurons.append({
                "id": nid,
                "filename": tbl["name"],
                "preview": _get_column_preview(tbl),
                "x": scx + fx * radius,
                "y": scy + y * radius,
                "z": scz + fz * radius,
                "chunk_count": tbl["column_count"],
                "project_tag": f"db:{database}",
            })

    synapses = []
    seen_edges = set()
    for fk in fk_rows:
        src = f"db:{fk['from_schema']}.{fk['from_table']}"
        tgt = f"db:{fk['to_schema']}.{fk['to_table']}"
        if src in neuron_ids and tgt in neuron_ids:
            edge_key = tuple(sorted([src, tgt]))
            if edge_key not in seen_edges:
                seen_edges.add(edge_key)
                synapses.append({"source": src, "target": tgt, "strength": 0.9})

    for schema_name in schema_list:
        schema_tables = schemas[schema_name]
        ids = [f"db:{schema_name}.{t['name']}" for t in schema_tables]
        if len(ids) <= 10:
            for i in range(len(ids)):
                for j in range(i + 1, len(ids)):
                    edge_key = tuple(sorted([ids[i], ids[j]]))
                    if edge_key not in seen_edges:
                        seen_edges.add(edge_key)
                        synapses.append({"source": ids[i], "target": ids[j], "strength": 0.3})
        else:
            for i in range(len(ids)):
                nxt = (i + 1) % len(ids)
                edge_key = tuple(sorted([ids[i], ids[nxt]]))
                if edge_key not in seen_edges:
                    seen_edges.add(edge_key)
                    synapses.append({"source": ids[i], "target": ids[nxt], "strength": 0.3})

    return {"neurons": neurons, "synapses": synapses}


# ── Search (always queries current source — local or remote) ─

def search_db(connection_url: str, query: str, limit: int = 50) -> list[dict]:
    url, _ = _resolve_url(connection_url)
    conn = _connect(url, readonly=True)
    results = []

    with conn.cursor(cursor_factory=psycopg2.extras.RealDictCursor) as cur:
        cur.execute("""
            SELECT table_schema, table_name, column_name
            FROM information_schema.columns
            WHERE table_schema NOT IN ('pg_catalog', 'information_schema', 'pg_toast')
              AND table_schema NOT LIKE 'pg_temp_%%'
              AND data_type IN ('character varying', 'text', 'character', 'name', 'uuid')
            ORDER BY table_schema, table_name, ordinal_position;
        """)
        text_columns = [dict(r) for r in cur.fetchall()]

    table_cols: dict[tuple, list] = {}
    for col in text_columns:
        key = (col["table_schema"], col["table_name"])
        table_cols.setdefault(key, []).append(col["column_name"])

    like_pattern = f"%{query}%"
    for (schema, table), cols in table_cols.items():
        if len(results) >= limit:
            break
        conditions = sql.SQL(" OR ").join(
            sql.SQL("{} ILIKE {}").format(sql.Identifier(c), sql.Literal(like_pattern))
            for c in cols
        )
        ident = sql.SQL("{}.{}").format(sql.Identifier(schema), sql.Identifier(table))
        q = sql.SQL("SELECT * FROM {} WHERE {} LIMIT {}").format(
            ident, conditions, sql.Literal(min(5, limit - len(results)))
        )
        try:
            with conn.cursor(cursor_factory=psycopg2.extras.RealDictCursor) as cur:
                cur.execute(q)
                rows = cur.fetchall()
                for row in rows:
                    row_dict = {k: str(v) if v is not None else "" for k, v in dict(row).items()}
                    for col_name in cols:
                        val = row_dict.get(col_name, "")
                        if query.lower() in val.lower():
                            results.append({
                                "schema": schema,
                                "table": table,
                                "column": col_name,
                                "value": val[:200],
                                "row_preview": {k: v[:100] for k, v in row_dict.items()},
                            })
                            if len(results) >= limit:
                                break
                    if len(results) >= limit:
                        break
        except Exception:
            continue

    conn.close()
    return results


def _get_column_preview(tbl: dict) -> str:
    return f"{tbl['schema']}.{tbl['name']} ({tbl['column_count']} cols, ~{tbl['row_estimate']} rows)"

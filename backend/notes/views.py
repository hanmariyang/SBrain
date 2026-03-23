import threading

from rest_framework import status
from rest_framework.decorators import api_view
from rest_framework.response import Response

from .ingest import get_status, ingest_folder, partial_ingest_files
from .models import Note
from .serializers import (
    IngestRequestSerializer,
    NoteDetailSerializer,
    NoteListSerializer,
    SearchRequestSerializer,
    SearchResultSerializer,
)
from .graph import build_brain_graph
from .search import search as do_search
from . import db_browser


@api_view(["GET"])
def brain_graph(request):
    threshold = float(request.query_params.get("threshold", 0.5))
    data = build_brain_graph(similarity_threshold=threshold)
    return Response(data)


@api_view(["POST"])
def ingest(request):
    serializer = IngestRequestSerializer(data=request.data)
    serializer.is_valid(raise_exception=True)
    folder_path = serializer.validated_data["folder_path"]

    current = get_status()
    if current["running"]:
        return Response(
            {"detail": "Ingestion already in progress"},
            status=status.HTTP_409_CONFLICT,
        )

    thread = threading.Thread(
        target=ingest_folder, args=(folder_path,), daemon=True
    )
    thread.start()

    return Response({"detail": "Ingestion started", "folder_path": folder_path})


@api_view(["GET"])
def note_list(request):
    notes = Note.objects.all()
    serializer = NoteListSerializer(notes, many=True)
    return Response(serializer.data)


@api_view(["GET"])
def note_detail(request, note_id):
    try:
        note = Note.objects.get(id=note_id)
    except Note.DoesNotExist:
        return Response(
            {"detail": "Note not found"}, status=status.HTTP_404_NOT_FOUND
        )
    serializer = NoteDetailSerializer(note)
    return Response(serializer.data)


@api_view(["POST"])
def search(request):
    serializer = SearchRequestSerializer(data=request.data)
    serializer.is_valid(raise_exception=True)

    query = serializer.validated_data["query"]
    limit = serializer.validated_data["limit"]

    results = do_search(query, limit)
    result_serializer = SearchResultSerializer(results, many=True)
    return Response(result_serializer.data)


@api_view(["PATCH"])
def partial_ingest(request):
    """변경된 파일만 부분 재인덱싱."""
    paths = request.data.get("paths", [])
    deleted_paths = request.data.get("deleted_paths", [])

    if not paths and not deleted_paths:
        return Response(
            {"error": "paths or deleted_paths is required"},
            status=status.HTTP_400_BAD_REQUEST,
        )

    result = partial_ingest_files(paths, deleted_paths)
    return Response(result)


@api_view(["GET"])
def ingest_status(request):
    return Response(get_status())


# ── Database Browser ─────────────────────────────────────────

@api_view(["POST"])
def db_connect(request):
    url = request.data.get("connection_url", "")
    if not url:
        return Response({"error": "connection_url is required"}, status=status.HTTP_400_BAD_REQUEST)
    return Response(db_browser.test_connection(url))


@api_view(["GET"])
def db_schemas(request):
    url = request.query_params.get("url", "")
    if not url:
        return Response({"error": "url param required"}, status=status.HTTP_400_BAD_REQUEST)
    try:
        return Response(db_browser.list_schemas(url))
    except Exception as e:
        return Response({"error": str(e)}, status=status.HTTP_500_INTERNAL_SERVER_ERROR)


@api_view(["GET"])
def db_tables(request):
    url = request.query_params.get("url", "")
    schema = request.query_params.get("schema", "public")
    if not url:
        return Response({"error": "url param required"}, status=status.HTTP_400_BAD_REQUEST)
    try:
        return Response(db_browser.list_tables(url, schema))
    except Exception as e:
        return Response({"error": str(e)}, status=status.HTTP_500_INTERNAL_SERVER_ERROR)


@api_view(["GET"])
def db_columns(request):
    url = request.query_params.get("url", "")
    schema = request.query_params.get("schema", "public")
    table = request.query_params.get("table", "")
    if not url or not table:
        return Response({"error": "url and table params required"}, status=status.HTTP_400_BAD_REQUEST)
    try:
        return Response(db_browser.list_columns(url, schema, table))
    except Exception as e:
        return Response({"error": str(e)}, status=status.HTTP_500_INTERNAL_SERVER_ERROR)


@api_view(["GET"])
def db_rows(request):
    url = request.query_params.get("url", "")
    schema = request.query_params.get("schema", "public")
    table = request.query_params.get("table", "")
    limit = int(request.query_params.get("limit", "200"))
    offset = int(request.query_params.get("offset", "0"))
    if not url or not table:
        return Response({"error": "url and table params required"}, status=status.HTTP_400_BAD_REQUEST)
    try:
        return Response(db_browser.fetch_rows(url, schema, table, limit, offset))
    except Exception as e:
        return Response({"error": str(e)}, status=status.HTTP_500_INTERNAL_SERVER_ERROR)


@api_view(["POST"])
def db_search(request):
    url = request.data.get("connection_url", "")
    query = request.data.get("query", "")
    limit = int(request.data.get("limit", 50))
    if not url or not query:
        return Response({"error": "connection_url and query required"}, status=status.HTTP_400_BAD_REQUEST)
    try:
        return Response(db_browser.search_db(url, query, limit))
    except Exception as e:
        return Response({"error": str(e)}, status=status.HTTP_500_INTERNAL_SERVER_ERROR)


@api_view(["GET"])
def db_graph(request):
    url = request.query_params.get("url", "")
    if not url:
        return Response({"error": "url param required"}, status=status.HTTP_400_BAD_REQUEST)
    try:
        return Response(db_browser.build_db_graph(url))
    except Exception as e:
        return Response({"error": str(e)}, status=status.HTTP_500_INTERNAL_SERVER_ERROR)

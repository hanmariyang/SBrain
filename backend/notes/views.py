import threading

from rest_framework import status
from rest_framework.decorators import api_view
from rest_framework.response import Response

from .ingest import get_status, ingest_folder
from .models import Note
from .serializers import (
    IngestRequestSerializer,
    NoteDetailSerializer,
    NoteListSerializer,
    SearchRequestSerializer,
    SearchResultSerializer,
)
from .graph import build_brain_graph
from .search import vector_search


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

    results = vector_search(query, limit)
    result_serializer = SearchResultSerializer(results, many=True)
    return Response(result_serializer.data)


@api_view(["GET"])
def ingest_status(request):
    return Response(get_status())

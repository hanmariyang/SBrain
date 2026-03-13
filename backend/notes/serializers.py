from rest_framework import serializers

from .models import Note


class NoteListSerializer(serializers.ModelSerializer):
    preview = serializers.SerializerMethodField()

    class Meta:
        model = Note
        fields = ["id", "filename", "path", "updated_at", "preview"]

    def get_preview(self, obj: Note) -> str:
        lines = obj.content.strip().splitlines()
        return lines[0][:200] if lines else ""


class NoteDetailSerializer(serializers.ModelSerializer):
    class Meta:
        model = Note
        fields = ["id", "filename", "path", "content", "updated_at"]


class SearchRequestSerializer(serializers.Serializer):
    query = serializers.CharField()
    limit = serializers.IntegerField(default=10, min_value=1, max_value=50)


class IngestRequestSerializer(serializers.Serializer):
    folder_path = serializers.CharField()


class SearchResultSerializer(serializers.Serializer):
    note_id = serializers.CharField()
    filename = serializers.CharField()
    path = serializers.CharField()
    chunk_text = serializers.CharField()
    score = serializers.FloatField()

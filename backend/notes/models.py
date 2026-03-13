import hashlib

from django.db import models


class Note(models.Model):
    id = models.CharField(max_length=64, primary_key=True)
    path = models.TextField()
    filename = models.CharField(max_length=512)
    content = models.TextField()
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        ordering = ["-updated_at"]

    def __str__(self):
        return self.filename

    @staticmethod
    def make_id(file_path: str) -> str:
        return hashlib.sha256(file_path.encode()).hexdigest()


class Chunk(models.Model):
    id = models.CharField(max_length=128, primary_key=True)
    note = models.ForeignKey(Note, on_delete=models.CASCADE, related_name="chunks")
    chunk_text = models.TextField()
    chunk_index = models.IntegerField(default=0)

    class Meta:
        ordering = ["note", "chunk_index"]

    def __str__(self):
        return f"{self.note.filename}[{self.chunk_index}]"

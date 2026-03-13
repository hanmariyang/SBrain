from django.urls import path

from . import views

urlpatterns = [
    path("ingest/", views.ingest, name="ingest"),
    path("notes/", views.note_list, name="note-list"),
    path("notes/<str:note_id>/", views.note_detail, name="note-detail"),
    path("search/", views.search, name="search"),
    path("status/", views.ingest_status, name="status"),
    path("graph/", views.brain_graph, name="brain-graph"),
]

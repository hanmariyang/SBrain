from django.urls import path

from . import views

urlpatterns = [
    path("ingest/", views.ingest, name="ingest"),
    path("notes/", views.note_list, name="note-list"),
    path("notes/<str:note_id>/", views.note_detail, name="note-detail"),
    path("search/", views.search, name="search"),
    path("status/", views.ingest_status, name="status"),
    path("graph/", views.brain_graph, name="brain-graph"),
    # Database browser
    path("db/connect/", views.db_connect, name="db-connect"),
    path("db/schemas/", views.db_schemas, name="db-schemas"),
    path("db/tables/", views.db_tables, name="db-tables"),
    path("db/columns/", views.db_columns, name="db-columns"),
    path("db/rows/", views.db_rows, name="db-rows"),
    path("db/search/", views.db_search, name="db-search"),
    path("db/graph/", views.db_graph, name="db-graph"),
    # DB mirror (download/sync)
    path("db/download/", views.db_download, name="db-download"),
    path("db/download/status/", views.db_download_status, name="db-download-status"),
    path("db/mirror/delete/", views.db_delete_mirror, name="db-mirror-delete"),
]

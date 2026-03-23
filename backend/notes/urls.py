from django.urls import path

from . import views

urlpatterns = [
    path("ingest/", views.ingest, name="ingest"),
    path("ingest/partial/", views.partial_ingest, name="partial-ingest"),
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
]

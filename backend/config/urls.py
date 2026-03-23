from django.urls import include, path

urlpatterns = [
    path("api/", include("notes.urls")),
    path("api/", include("integrations.urls")),
]

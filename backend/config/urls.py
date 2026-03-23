from django.urls import include, path

from integrations.oauth_callback import google_calendar_callback

urlpatterns = [
    # OAuth 콜백 — DRF 완전 우회, 순수 Django 뷰
    path("api/calendar/auth/callback/", google_calendar_callback, name="calendar-auth-callback"),
    # DRF API
    path("api/", include("notes.urls")),
    path("api/", include("integrations.urls")),
]

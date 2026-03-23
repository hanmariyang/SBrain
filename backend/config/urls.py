from django.urls import include, path

from integrations.calendar_views import calendar_auth_callback

urlpatterns = [
    # OAuth 콜백 — DRF 미들웨어 우회 (브라우저 직접 호출)
    path("api/calendar/auth/callback/", calendar_auth_callback, name="calendar-auth-callback"),
    # DRF API
    path("api/", include("notes.urls")),
    path("api/", include("integrations.urls")),
]

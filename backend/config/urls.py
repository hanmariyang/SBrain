import os

import requests as req
from django.http import HttpResponse
from django.urls import include, path

from integrations.oauth_callback import google_calendar_callback, slack_oauth_callback


def appcast_xml(request):
    """GitHub main 브랜치의 appcast.xml을 프록시 (private repo 대응)."""
    try:
        github_token = os.getenv("GITHUB_TOKEN", "")
        headers = {}
        if github_token:
            headers["Authorization"] = f"token {github_token}"
        resp = req.get(
            "https://raw.githubusercontent.com/hanmariyang/SBrain/main/appcast.xml",
            headers=headers,
            timeout=10,
        )
        return HttpResponse(
            resp.content,
            content_type="application/xml; charset=utf-8",
            status=resp.status_code,
        )
    except Exception:
        return HttpResponse("<error>Failed</error>", content_type="application/xml", status=502)


urlpatterns = [
    # Sparkle appcast (private repo 프록시)
    path("appcast.xml", appcast_xml, name="appcast"),
    # OAuth 콜백 — DRF 완전 우회, 순수 Django 뷰
    path("api/calendar/auth/callback/", google_calendar_callback, name="calendar-auth-callback"),
    path("api/slack/auth/callback/", slack_oauth_callback, name="slack-auth-callback"),
    # DRF API
    path("api/", include("notes.urls")),
    path("api/", include("integrations.urls")),
]

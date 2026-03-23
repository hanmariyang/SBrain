import os

import requests as req
from django.http import HttpResponse
from django.urls import include, path

from integrations.oauth_callback import google_calendar_callback, slack_oauth_callback


def appcast_xml(request):
    """GitHub main 브랜치의 appcast.xml을 프록시 (private repo 대응).
    DMG URL을 Railway 프록시 경로로 치환하여 Sparkle이 다운로드할 수 있게 한다.
    """
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
        # DMG URL을 Railway 프록시 경로로 치환
        from django.conf import settings as django_settings
        server_url = getattr(django_settings, "SERVER_URL", "") or "http://localhost:8765"
        content = resp.content.decode("utf-8")
        content = content.replace(
            "https://github.com/hanmariyang/SBrain/releases/download/",
            f"{server_url}/releases/download/",
        )
        return HttpResponse(
            content,
            content_type="application/xml; charset=utf-8",
            status=resp.status_code,
        )
    except Exception:
        return HttpResponse("<error>Failed</error>", content_type="application/xml", status=502)


def release_download(request, tag, filename):
    """GitHub Release asset 다운로드 프록시 (private repo 대응)."""
    try:
        github_token = os.getenv("GITHUB_TOKEN", "")
        headers = {"Accept": "application/octet-stream"}
        if github_token:
            headers["Authorization"] = f"token {github_token}"

        # GitHub API로 release asset 조회
        api_url = f"https://api.github.com/repos/hanmariyang/SBrain/releases/tags/{tag}"
        release_resp = req.get(api_url, headers={"Authorization": f"token {github_token}"} if github_token else {}, timeout=10)
        if release_resp.status_code != 200:
            return HttpResponse("Release not found", status=404)

        assets = release_resp.json().get("assets", [])
        asset = next((a for a in assets if a["name"] == filename), None)
        if not asset:
            return HttpResponse("Asset not found", status=404)

        # asset URL에서 실제 바이너리 다운로드
        download_resp = req.get(asset["url"], headers=headers, stream=True, timeout=120)

        response = HttpResponse(
            download_resp.iter_content(chunk_size=65536),
            content_type="application/octet-stream",
            status=download_resp.status_code,
        )
        response["Content-Disposition"] = f'attachment; filename="{filename}"'
        if "Content-Length" in download_resp.headers:
            response["Content-Length"] = download_resp.headers["Content-Length"]
        return response
    except Exception as e:
        return HttpResponse(f"Download failed: {e}", status=502)


urlpatterns = [
    # Sparkle appcast + DMG 다운로드 프록시 (private repo 대응)
    path("appcast.xml", appcast_xml, name="appcast"),
    path("releases/download/<str:tag>/<str:filename>", release_download, name="release-download"),
    # OAuth 콜백 — DRF 완전 우회, 순수 Django 뷰
    path("api/calendar/auth/callback/", google_calendar_callback, name="calendar-auth-callback"),
    path("api/slack/auth/callback/", slack_oauth_callback, name="slack-auth-callback"),
    # DRF API
    path("api/", include("notes.urls")),
    path("api/", include("integrations.urls")),
]

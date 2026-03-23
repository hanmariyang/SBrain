"""
OAuth 콜백 핸들러 (Google Calendar + Slack).

브라우저에서 직접 호출되므로 DRF를 사용하지 않는 순수 Django 뷰.
"""

import logging
import os

import requests
from django.http import HttpResponse
from django.views.decorators.csrf import csrf_exempt

from . import calendar_service, slack_service

logger = logging.getLogger(__name__)


@csrf_exempt
def google_calendar_callback(request):
    """Google OAuth 콜백. 브라우저에서 리디렉트되어 호출됨."""
    code = request.GET.get("code", "")

    if not code:
        return HttpResponse(
            _html_page("인증 실패", "Authorization code가 없습니다.", success=False),
            content_type="text/html; charset=utf-8",
        )

    try:
        result = calendar_service.exchange_code(code)
        if result:
            return HttpResponse(
                _html_page(
                    "Google Calendar 연동 완료",
                    "이 창을 닫고 SBrain으로 돌아가세요.",
                    success=True,
                ),
                content_type="text/html; charset=utf-8",
            )
        else:
            return HttpResponse(
                _html_page("인증 실패", "토큰 교환에 실패했습니다.", success=False),
                content_type="text/html; charset=utf-8",
            )
    except Exception as e:
        return HttpResponse(
            _html_page("오류 발생", str(e), success=False),
            content_type="text/html; charset=utf-8",
            status=500,
        )


@csrf_exempt
def slack_oauth_callback(request):
    """Slack OAuth 콜백. 사용자 identity를 가져와 설정."""
    code = request.GET.get("code", "")

    if not code:
        return HttpResponse(
            _html_page("인증 실패", "Authorization code가 없습니다.", success=False),
            content_type="text/html; charset=utf-8",
        )

    try:
        from django.conf import settings as django_settings

        client_id = os.getenv("SLACK_CLIENT_ID", "")
        client_secret = os.getenv("SLACK_CLIENT_SECRET", "")
        server_url = getattr(django_settings, "SERVER_URL", "") or "http://localhost:8765"
        redirect_uri = f"{server_url}/api/slack/auth/callback/"

        # Authorization code → access token 교환
        resp = requests.post("https://slack.com/api/oauth.v2.access", data={
            "client_id": client_id,
            "client_secret": client_secret,
            "code": code,
            "redirect_uri": redirect_uri,
        })
        data = resp.json()

        if not data.get("ok"):
            error = data.get("error", "unknown")
            logger.error("Slack OAuth failed: %s", error)
            return HttpResponse(
                _html_page("Slack 인증 실패", f"에러: {error}", success=False),
                content_type="text/html; charset=utf-8",
            )

        # authed_user에서 사용자 ID 추출
        authed_user = data.get("authed_user", {})
        user_id = authed_user.get("id", "")

        if user_id:
            # 사용자 정보 저장
            user_info = slack_service.set_current_user(user_id)
            user_name = user_info.get("display_name") or user_info.get("real_name", user_id)
            return HttpResponse(
                _html_page(
                    "Slack 연동 완료",
                    f"{user_name}님으로 로그인되었습니다. 이 창을 닫고 SBrain으로 돌아가세요.",
                    success=True,
                ),
                content_type="text/html; charset=utf-8",
            )
        else:
            return HttpResponse(
                _html_page("Slack 인증 실패", "사용자 정보를 가져올 수 없습니다.", success=False),
                content_type="text/html; charset=utf-8",
            )

    except Exception as e:
        logger.error("Slack OAuth callback error: %s", e)
        return HttpResponse(
            _html_page("오류 발생", str(e), success=False),
            content_type="text/html; charset=utf-8",
            status=500,
        )


def _html_page(title: str, message: str, success: bool = True) -> str:
    color = "#1B2A4A" if success else "#D94F4F"
    return f"""<!DOCTYPE html>
<html lang="ko">
<head><meta charset="utf-8"><title>{title}</title></head>
<body style="font-family:system-ui;text-align:center;padding:80px 20px;background:#FAF8F5;">
  <h2 style="color:{color};margin-bottom:12px;">{title}</h2>
  <p style="color:#6B7B9A;">{message}</p>
  {"<script>setTimeout(()=>window.close(),2000)</script>" if success else ""}
</body>
</html>"""

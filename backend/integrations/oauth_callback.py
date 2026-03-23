"""
Google OAuth 콜백 핸들러.

브라우저에서 직접 호출되므로 DRF를 사용하지 않는 순수 Django 뷰.
"""

from django.http import HttpResponse
from django.views.decorators.csrf import csrf_exempt

from . import calendar_service


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

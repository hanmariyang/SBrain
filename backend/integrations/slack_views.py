"""
Slack 연동 API 뷰.

메시지 스캔, 분석 결과 조회, 답장, 채널 목록, 상태 확인, 필터 설정.
"""

import os

from rest_framework import status
from rest_framework.decorators import api_view
from rest_framework.response import Response

from . import slack_service
from .slack_analyzer import analyze_messages

# 최근 분석 결과 캐시
_last_analysis: list[dict] = []


@api_view(["POST"])
def slack_scan(request):
    """수동 스캔: 미처리 메시지를 가져와 AI 분석 수행."""
    global _last_analysis

    try:
        pending = slack_service.get_pending_messages()
        if not pending:
            return Response({
                "detail": "No pending messages",
                "count": 0,
                "results": [],
            })

        # 사용자 이름 resolve (캐시)
        user_cache = {}
        for msg in pending:
            uid = msg.get("user", "")
            if uid and uid not in user_cache:
                info = slack_service.get_user_info(uid)
                user_cache[uid] = info.get("display_name") or info.get("real_name", uid)

        # AI 분석
        results = analyze_messages(pending)

        # 분석 결과에 channel_name, user_name 추가
        for r in results:
            mid = r.get("message_id", "")
            original = next((m for m in pending if m["id"] == mid), {})
            r["channel"] = original.get("channel", "")
            r["channel_name"] = original.get("channel_name", r.get("channel", ""))
            r["user"] = original.get("user", "")
            r["user_name"] = user_cache.get(original.get("user", ""), "")
            r["timestamp"] = original.get("ts", "")
            r["thread_ts"] = original.get("thread_ts", "")
            r["text"] = original.get("text", "")
            r["id"] = mid

        # 분석된 메시지를 처리 완료로 표시
        processed_ids = [msg["id"] for msg in pending]
        slack_service.mark_processed(processed_ids)

        # 분석 결과 캐시
        _last_analysis = results

        return Response({
            "detail": "Scan completed",
            "count": len(results),
            "results": results,
        })

    except Exception as e:
        return Response(
            {"error": str(e)},
            status=status.HTTP_500_INTERNAL_SERVER_ERROR,
        )


@api_view(["GET"])
def slack_messages(request):
    """최근 분석된 메시지 결과 반환."""
    return Response({
        "count": len(_last_analysis),
        "results": _last_analysis,
    })


@api_view(["POST"])
def slack_reply(request):
    """승인된 답장을 Slack으로 전송."""
    channel = request.data.get("channel", "")
    thread_ts = request.data.get("thread_ts", "")
    text = request.data.get("text", "")

    if not channel or not text:
        return Response(
            {"error": "channel and text are required"},
            status=status.HTTP_400_BAD_REQUEST,
        )

    try:
        result = slack_service.send_reply(channel, thread_ts, text)
        if result["ok"]:
            return Response(result)
        else:
            return Response(result, status=status.HTTP_502_BAD_GATEWAY)
    except Exception as e:
        return Response(
            {"error": str(e)},
            status=status.HTTP_500_INTERNAL_SERVER_ERROR,
        )


@api_view(["GET"])
def slack_channels(request):
    """사용자의 Slack 채널 목록 반환."""
    try:
        channels = slack_service.get_channels()
        return Response({"channels": channels})
    except Exception as e:
        return Response(
            {"error": str(e)},
            status=status.HTTP_500_INTERNAL_SERVER_ERROR,
        )


@api_view(["GET"])
def slack_status(request):
    """Slack Socket Mode 연결 상태 반환."""
    return Response({
        "connected": slack_service.is_running(),
        "pending_count": len(slack_service.get_pending_messages()),
    })


@api_view(["GET"])
def slack_auth(request):
    """Slack OAuth 인증 URL 반환. 사용자 식별용."""
    from django.conf import settings as django_settings

    client_id = os.getenv("SLACK_CLIENT_ID", "")
    server_url = getattr(django_settings, "SERVER_URL", "") or "http://localhost:8765"
    redirect_uri = f"{server_url}/api/slack/auth/callback/"

    if not client_id:
        return Response(
            {"error": "SLACK_CLIENT_ID is not configured"},
            status=status.HTTP_400_BAD_REQUEST,
        )

    auth_url = (
        f"https://slack.com/oauth/v2/authorize"
        f"?client_id={client_id}"
        f"&user_scope=identity.basic"
        f"&redirect_uri={redirect_uri}"
    )
    return Response({"auth_url": auth_url})


@api_view(["GET"])
def slack_user(request):
    """현재 설정된 Slack 사용자 정보 반환."""
    user = slack_service.get_current_user()
    return Response({"user": user, "authenticated": bool(user.get("id"))})


@api_view(["GET", "PUT"])
def slack_settings(request):
    """필터 설정 조회(GET) 또는 업데이트(PUT)."""
    if request.method == "GET":
        settings = slack_service.get_filter_settings()
        return Response(settings)

    # PUT
    channels = request.data.get("channels")
    keywords = request.data.get("keywords")

    update = {}
    if channels is not None:
        if not isinstance(channels, list):
            return Response(
                {"error": "channels must be a list"},
                status=status.HTTP_400_BAD_REQUEST,
            )
        update["channels"] = channels
    if keywords is not None:
        if not isinstance(keywords, list):
            return Response(
                {"error": "keywords must be a list"},
                status=status.HTTP_400_BAD_REQUEST,
            )
        update["keywords"] = keywords

    if not update:
        return Response(
            {"error": "Provide channels and/or keywords"},
            status=status.HTTP_400_BAD_REQUEST,
        )

    result = slack_service.update_filter_settings(update)
    return Response(result)

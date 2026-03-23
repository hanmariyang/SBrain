"""
Google Calendar 연동 API 뷰.

OAuth 인증 플로우, 이벤트 CRUD.
"""

from django.http import HttpResponse
from rest_framework import status
from rest_framework.decorators import api_view
from rest_framework.response import Response

from . import calendar_service


@api_view(["GET"])
def calendar_auth(request):
    """Google OAuth 인증 URL 반환."""
    try:
        auth_url = calendar_service.get_auth_url()
        return Response({"auth_url": auth_url})
    except ValueError as e:
        return Response(
            {"error": str(e)},
            status=status.HTTP_400_BAD_REQUEST,
        )
    except Exception as e:
        return Response(
            {"error": str(e)},
            status=status.HTTP_500_INTERNAL_SERVER_ERROR,
        )


def calendar_auth_callback(request):
    """Google OAuth 콜백 처리. 브라우저에서 직접 호출되므로 HTML 반환."""
    code = request.GET.get("code", "")
    if not code:
        return HttpResponse(
            "<html><body><h2>인증 실패</h2><p>Authorization code가 없습니다.</p></body></html>",
            content_type="text/html",
        )

    try:
        success = calendar_service.exchange_code(code)
        if success:
            return HttpResponse(
                "<html><body style='font-family:system-ui;text-align:center;padding:60px;'>"
                "<h2 style='color:#1B2A4A;'>Google Calendar 연동 완료</h2>"
                "<p style='color:#6B7B9A;'>이 창을 닫고 SBrain으로 돌아가세요.</p>"
                "<script>setTimeout(()=>window.close(),2000)</script>"
                "</body></html>",
                content_type="text/html",
            )
        else:
            return HttpResponse(
                "<html><body><h2>인증 실패</h2><p>토큰 교환에 실패했습니다.</p></body></html>",
                content_type="text/html",
            )
    except Exception as e:
        return HttpResponse(
            f"<html><body><h2>오류 발생</h2><p>{e}</p></body></html>",
            content_type="text/html",
            status=500,
        )


@api_view(["GET"])
def calendar_status(request):
    """Google Calendar 인증 상태 확인."""
    return Response({
        "authenticated": calendar_service.is_authenticated(),
    })


@api_view(["GET", "POST"])
def calendar_events(request):
    """이벤트 목록 조회(GET) 또는 생성(POST)."""
    if request.method == "GET":
        start = request.query_params.get("start", "")
        end = request.query_params.get("end", "")

        if not start or not end:
            return Response(
                {"error": "start and end query params are required"},
                status=status.HTTP_400_BAD_REQUEST,
            )

        try:
            events = calendar_service.list_events(start, end)
            return Response({"events": events, "count": len(events)})
        except ValueError as e:
            return Response(
                {"error": str(e)},
                status=status.HTTP_401_UNAUTHORIZED,
            )
        except Exception as e:
            return Response(
                {"error": str(e)},
                status=status.HTTP_500_INTERNAL_SERVER_ERROR,
            )

    # POST — 이벤트 생성
    title = request.data.get("title", "")
    start = request.data.get("start", "")
    end = request.data.get("end", "")
    description = request.data.get("description", "")
    attendees = request.data.get("attendees", [])

    if not title or not start or not end:
        return Response(
            {"error": "title, start, and end are required"},
            status=status.HTTP_400_BAD_REQUEST,
        )

    try:
        event = calendar_service.create_event(
            title=title,
            start=start,
            end=end,
            description=description,
            attendees=attendees,
        )
        return Response(event, status=status.HTTP_201_CREATED)
    except ValueError as e:
        return Response(
            {"error": str(e)},
            status=status.HTTP_401_UNAUTHORIZED,
        )
    except Exception as e:
        return Response(
            {"error": str(e)},
            status=status.HTTP_500_INTERNAL_SERVER_ERROR,
        )


@api_view(["PUT", "DELETE"])
def calendar_event_detail(request, event_id):
    """이벤트 수정(PUT) 또는 삭제(DELETE)."""
    if request.method == "PUT":
        update_fields = {}
        for field in ("title", "start", "end", "description", "attendees"):
            if field in request.data:
                update_fields[field] = request.data[field]

        if not update_fields:
            return Response(
                {"error": "No fields to update"},
                status=status.HTTP_400_BAD_REQUEST,
            )

        try:
            event = calendar_service.update_event(event_id, **update_fields)
            return Response(event)
        except ValueError as e:
            return Response(
                {"error": str(e)},
                status=status.HTTP_401_UNAUTHORIZED,
            )
        except Exception as e:
            return Response(
                {"error": str(e)},
                status=status.HTTP_500_INTERNAL_SERVER_ERROR,
            )

    # DELETE
    try:
        calendar_service.delete_event(event_id)
        return Response(
            {"detail": "Event deleted"},
            status=status.HTTP_204_NO_CONTENT,
        )
    except ValueError as e:
        return Response(
            {"error": str(e)},
            status=status.HTTP_401_UNAUTHORIZED,
        )
    except Exception as e:
        return Response(
            {"error": str(e)},
            status=status.HTTP_500_INTERNAL_SERVER_ERROR,
        )

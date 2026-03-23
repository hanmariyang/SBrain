"""
Google Calendar 연동 API 뷰.

OAuth 인증 플로우, 이벤트 CRUD.
"""

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


@api_view(["GET"])
def calendar_auth_callback(request):
    """Google OAuth 콜백 처리. 인증 코드를 토큰으로 교환."""
    code = request.query_params.get("code", "")
    if not code:
        return Response(
            {"error": "Authorization code is required"},
            status=status.HTTP_400_BAD_REQUEST,
        )

    try:
        success = calendar_service.exchange_code(code)
        if success:
            return Response({"detail": "Google Calendar authenticated successfully"})
        else:
            return Response(
                {"error": "Failed to exchange authorization code"},
                status=status.HTTP_400_BAD_REQUEST,
            )
    except Exception as e:
        return Response(
            {"error": str(e)},
            status=status.HTTP_500_INTERNAL_SERVER_ERROR,
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

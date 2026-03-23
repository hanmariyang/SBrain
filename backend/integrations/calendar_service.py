"""
Google Calendar API 래퍼 서비스.

OAuth 인증 플로우, 토큰 관리, 이벤트 CRUD를 처리한다.
토큰은 backend/.google_tokens.json에 저장 (gitignore됨).
"""

import json
import logging
import os
from datetime import datetime
from pathlib import Path

from google.auth.transport.requests import Request
from google.oauth2.credentials import Credentials
from google_auth_oauthlib.flow import Flow
from googleapiclient.discovery import build
from googleapiclient.errors import HttpError

logger = logging.getLogger(__name__)

# 토큰 저장 경로
_TOKENS_PATH = Path(__file__).resolve().parent.parent / ".google_tokens.json"

# OAuth 스코프
_SCOPES = ["https://www.googleapis.com/auth/calendar"]

# OAuth 리다이렉트 URI (로컬 콜백)
_REDIRECT_URI = "http://localhost:8765/api/calendar/auth/callback/"


def _get_client_config() -> dict:
    """환경 변수에서 Google OAuth 클라이언트 설정 구성."""
    client_id = os.getenv("GOOGLE_CLIENT_ID", "")
    client_secret = os.getenv("GOOGLE_CLIENT_SECRET", "")

    if not client_id or not client_secret:
        raise ValueError("GOOGLE_CLIENT_ID and GOOGLE_CLIENT_SECRET are required")

    return {
        "web": {
            "client_id": client_id,
            "client_secret": client_secret,
            "auth_uri": "https://accounts.google.com/o/oauth2/auth",
            "token_uri": "https://oauth2.googleapis.com/token",
            "redirect_uris": [_REDIRECT_URI],
        }
    }


def _load_credentials() -> Credentials | None:
    """저장된 토큰 파일에서 Credentials 로드."""
    if not _TOKENS_PATH.exists():
        return None

    try:
        with open(_TOKENS_PATH, "r") as f:
            token_data = json.load(f)
        creds = Credentials.from_authorized_user_info(token_data, _SCOPES)
        return creds
    except Exception as e:
        logger.error("Failed to load Google credentials: %s", e)
        return None


def _save_credentials(creds: Credentials):
    """Credentials를 토큰 파일에 저장."""
    token_data = {
        "token": creds.token,
        "refresh_token": creds.refresh_token,
        "token_uri": creds.token_uri,
        "client_id": creds.client_id,
        "client_secret": creds.client_secret,
        "scopes": list(creds.scopes) if creds.scopes else _SCOPES,
    }
    with open(_TOKENS_PATH, "w") as f:
        json.dump(token_data, f, indent=2)
    logger.info("Google credentials saved to %s", _TOKENS_PATH)


def _get_service():
    """인증된 Google Calendar API 서비스 객체 반환."""
    creds = _load_credentials()
    if not creds:
        raise ValueError("Not authenticated. Please complete OAuth flow first.")

    # 토큰 만료 시 자동 갱신
    if creds.expired and creds.refresh_token:
        try:
            creds.refresh(Request())
            _save_credentials(creds)
        except Exception as e:
            logger.error("Failed to refresh Google token: %s", e)
            raise ValueError("Token refresh failed. Please re-authenticate.") from e

    if not creds.valid:
        raise ValueError("Invalid credentials. Please re-authenticate.")

    return build("calendar", "v3", credentials=creds)


# ── OAuth 플로우 ─────────────────────────────────────────────


def get_auth_url() -> str:
    """Google OAuth 인증 URL 생성."""
    client_config = _get_client_config()
    flow = Flow.from_client_config(
        client_config,
        scopes=_SCOPES,
        redirect_uri=_REDIRECT_URI,
    )
    auth_url, _ = flow.authorization_url(
        access_type="offline",
        include_granted_scopes="true",
        prompt="consent",
    )
    return auth_url


def exchange_code(code: str) -> bool:
    """OAuth 인증 코드를 토큰으로 교환하고 저장."""
    try:
        client_config = _get_client_config()
        flow = Flow.from_client_config(
            client_config,
            scopes=_SCOPES,
            redirect_uri=_REDIRECT_URI,
        )
        flow.fetch_token(code=code)
        creds = flow.credentials
        _save_credentials(creds)
        return True
    except Exception as e:
        logger.error("Failed to exchange OAuth code: %s", e)
        return False


def is_authenticated() -> bool:
    """유효한 Google 토큰 존재 여부 확인."""
    creds = _load_credentials()
    if not creds:
        return False

    # 만료되었지만 refresh_token이 있으면 갱신 시도
    if creds.expired and creds.refresh_token:
        try:
            creds.refresh(Request())
            _save_credentials(creds)
            return True
        except Exception:
            return False

    return creds.valid


# ── 이벤트 CRUD ──────────────────────────────────────────────


def list_events(start: str, end: str) -> list[dict]:
    """
    지정 기간의 캘린더 이벤트 목록 조회.

    Args:
        start: ISO 8601 형식 시작 시간 (예: 2024-01-01T00:00:00Z)
        end: ISO 8601 형식 종료 시간
    """
    try:
        service = _get_service()
        result = service.events().list(
            calendarId="primary",
            timeMin=start,
            timeMax=end,
            singleEvents=True,
            orderBy="startTime",
            maxResults=100,
        ).execute()

        events = []
        for item in result.get("items", []):
            events.append(_format_event(item))
        return events

    except HttpError as e:
        logger.error("Google Calendar API error: %s", e)
        raise
    except ValueError:
        raise


def create_event(
    title: str,
    start: str,
    end: str,
    description: str = "",
    attendees: list[str] | None = None,
) -> dict:
    """
    캘린더 이벤트 생성.

    Args:
        title: 이벤트 제목
        start: ISO 8601 시작 시간
        end: ISO 8601 종료 시간
        description: 설명 (선택)
        attendees: 참석자 이메일 리스트 (선택)
    """
    try:
        service = _get_service()
        body = {
            "summary": title,
            "start": _parse_datetime(start),
            "end": _parse_datetime(end),
        }
        if description:
            body["description"] = description
        if attendees:
            body["attendees"] = [{"email": email} for email in attendees]

        result = service.events().insert(
            calendarId="primary",
            body=body,
        ).execute()

        return _format_event(result)

    except HttpError as e:
        logger.error("Failed to create event: %s", e)
        raise
    except ValueError:
        raise


def update_event(event_id: str, **kwargs) -> dict:
    """
    캘린더 이벤트 업데이트.

    지원 필드: title, start, end, description, attendees
    """
    try:
        service = _get_service()

        # 기존 이벤트 조회
        event = service.events().get(
            calendarId="primary",
            eventId=event_id,
        ).execute()

        # 업데이트할 필드 적용
        if "title" in kwargs:
            event["summary"] = kwargs["title"]
        if "start" in kwargs:
            event["start"] = _parse_datetime(kwargs["start"])
        if "end" in kwargs:
            event["end"] = _parse_datetime(kwargs["end"])
        if "description" in kwargs:
            event["description"] = kwargs["description"]
        if "attendees" in kwargs:
            event["attendees"] = [
                {"email": email} for email in kwargs["attendees"]
            ]

        result = service.events().update(
            calendarId="primary",
            eventId=event_id,
            body=event,
        ).execute()

        return _format_event(result)

    except HttpError as e:
        logger.error("Failed to update event: %s", e)
        raise
    except ValueError:
        raise


def delete_event(event_id: str) -> bool:
    """캘린더 이벤트 삭제."""
    try:
        service = _get_service()
        service.events().delete(
            calendarId="primary",
            eventId=event_id,
        ).execute()
        return True
    except HttpError as e:
        logger.error("Failed to delete event: %s", e)
        raise
    except ValueError:
        raise


# ── 헬퍼 ─────────────────────────────────────────────────────


def _parse_datetime(dt_str: str) -> dict:
    """ISO 8601 문자열을 Google Calendar API 형식으로 변환."""
    # 날짜만 (YYYY-MM-DD)인 경우
    if len(dt_str) == 10:
        return {"date": dt_str}
    # datetime인 경우
    return {"dateTime": dt_str, "timeZone": "Asia/Seoul"}


def _format_event(item: dict) -> dict:
    """Google Calendar API 이벤트를 정리된 딕셔너리로 변환."""
    start = item.get("start", {})
    end = item.get("end", {})
    return {
        "id": item.get("id", ""),
        "title": item.get("summary", ""),
        "description": item.get("description", ""),
        "start": start.get("dateTime") or start.get("date", ""),
        "end": end.get("dateTime") or end.get("date", ""),
        "html_link": item.get("htmlLink", ""),
        "attendees": [
            a.get("email", "") for a in item.get("attendees", [])
        ],
        "status": item.get("status", ""),
    }

"""
Slack Socket Mode 실시간 메시지 수신 및 관리 서비스.

slack-bolt Socket Mode를 사용하여 WebSocket으로 메시지를 수신하고,
thread-safe 인메모리 저장소에 보관한다.
"""

import logging
import os
import threading
import uuid
from datetime import datetime, timezone

from slack_bolt import App
from slack_bolt.adapter.socket_mode import SocketModeHandler
from slack_sdk import WebClient
from slack_sdk.errors import SlackApiError

logger = logging.getLogger(__name__)

# ── 인메모리 메시지 저장소 (thread-safe) ──────────────────────

_lock = threading.Lock()
_messages: list[dict] = []  # 수신된 메시지 목록
_processed_ids: set[str] = set()  # 처리 완료된 메시지 ID

# ── 필터 설정 ────────────────────────────────────────────────

_settings_lock = threading.Lock()
_filter_settings: dict = {
    "channels": [],   # 빈 리스트 = 모든 채널
    "keywords": [],   # 빈 리스트 = 키워드 필터 없음
    "user_id": "",    # 연동된 Slack 사용자 ID
    "user_name": "",  # 사용자 이름
}

# ── Socket Mode 상태 ─────────────────────────────────────────

_socket_mode_running = False

# ── Slack App 초기화 ─────────────────────────────────────────


def _get_slack_app() -> App:
    """Slack Bolt App 인스턴스 생성."""
    bot_token = os.getenv("SLACK_BOT_TOKEN", "")
    signing_secret = os.getenv("SLACK_SIGNING_SECRET", "")
    app = App(
        token=bot_token,
        signing_secret=signing_secret,
    )

    @app.event("message")
    def handle_message(event, say):
        """채널/DM/그룹 메시지 수신 처리."""
        _store_message(event)

    @app.event("app_mention")
    def handle_mention(event, say):
        """앱 멘션 이벤트 처리."""
        _store_message(event, is_mention=True)

    return app


def _store_message(event: dict, is_mention: bool = False):
    """수신된 메시지를 인메모리 저장소에 추가."""
    # bot 메시지 무시
    if event.get("bot_id") or event.get("subtype") == "bot_message":
        return

    channel = event.get("channel", "")
    text = event.get("text", "")

    # 필터 적용
    with _settings_lock:
        allowed_channels = _filter_settings["channels"]
        keywords = _filter_settings["keywords"]
        my_user_id = _filter_settings["user_id"]

    # 사용자 ID가 설정된 경우: 멘션 또는 DM만 수집
    if my_user_id:
        is_dm = event.get("channel_type") == "im"
        is_my_mention = f"<@{my_user_id}>" in text
        has_keyword = keywords and any(kw.lower() in text.lower() for kw in keywords)

        if not (is_mention or is_dm or is_my_mention or has_keyword):
            return
    else:
        # 사용자 ID 미설정: 기존 로직 (채널/키워드 필터)
        if allowed_channels and channel not in allowed_channels:
            return
        if keywords and not any(kw.lower() in text.lower() for kw in keywords):
            return

    msg = {
        "id": str(uuid.uuid4()),
        "channel": channel,
        "user": event.get("user", ""),
        "text": text,
        "ts": event.get("ts", ""),
        "thread_ts": event.get("thread_ts", ""),
        "is_mention": is_mention,
        "received_at": datetime.now(timezone.utc).isoformat(),
    }

    with _lock:
        _messages.append(msg)

    logger.debug("Slack message stored: %s", msg["id"])


# ── 공개 함수 ────────────────────────────────────────────────


def start_socket_mode():
    """Socket Mode WebSocket 리스너를 시작한다 (blocking, 재시도 포함)."""
    global _socket_mode_running
    import time

    app_token = os.getenv("SLACK_APP_TOKEN", "")
    if not app_token:
        logger.error("SLACK_APP_TOKEN is not set")
        return

    max_retries = 5
    for attempt in range(max_retries):
        try:
            app = _get_slack_app()
            handler = SocketModeHandler(app, app_token)
            _socket_mode_running = True
            logger.info("Starting Slack Socket Mode (attempt %d)...", attempt + 1)
            handler.start()  # blocking
        except Exception as e:
            _socket_mode_running = False
            logger.error("Socket Mode failed (attempt %d): %s", attempt + 1, e)
            if attempt < max_retries - 1:
                time.sleep(5)  # 5초 후 재시도
            else:
                logger.error("Socket Mode gave up after %d attempts", max_retries)


def is_running() -> bool:
    """Socket Mode 연결 상태 반환."""
    return _socket_mode_running


def get_pending_messages() -> list[dict]:
    """처리되지 않은 메시지 목록 반환. Socket Mode + Web API 병합."""
    # Web API로 최근 메시지를 직접 가져옴 (Socket Mode 보완)
    _fetch_recent_messages()

    with _lock:
        pending = [
            msg for msg in _messages if msg["id"] not in _processed_ids
        ]
    return pending


def _fetch_recent_messages():
    """봇이 참여 중인 채널에서 최근 메시지를 Web API로 직접 가져옴."""
    bot_token = os.getenv("SLACK_BOT_TOKEN", "")
    client = WebClient(token=bot_token)

    with _settings_lock:
        my_user_id = _filter_settings["user_id"]
        keywords = _filter_settings["keywords"]

    try:
        # 봇이 참여 중인 채널 목록
        result = client.users_conversations(
            types="public_channel,private_channel,im",
            limit=50,
        )
        channels = result.get("channels", [])

        for ch in channels:
            ch_id = ch.get("id", "")
            is_im = ch.get("is_im", False)

            try:
                history = client.conversations_history(
                    channel=ch_id,
                    limit=20,
                )
                for msg in history.get("messages", []):
                    # bot 메시지 무시
                    if msg.get("bot_id") or msg.get("subtype"):
                        continue

                    text = msg.get("text", "")
                    ts = msg.get("ts", "")
                    msg_user = msg.get("user", "")

                    # 중복 방지 (ts 기반)
                    with _lock:
                        if any(m.get("ts") == ts and m.get("channel") == ch_id for m in _messages):
                            continue

                    # 필터링: 멘션/DM/키워드
                    if my_user_id:
                        is_my_mention = f"<@{my_user_id}>" in text
                        has_keyword = keywords and any(kw.lower() in text.lower() for kw in keywords)

                        # 본인이 보낸 일반 메시지는 제외 (키워드 매칭은 허용)
                        if msg_user == my_user_id and not has_keyword:
                            continue
                        if not (is_im or is_my_mention or has_keyword):
                            continue

                    new_msg = {
                        "id": str(uuid.uuid4()),
                        "channel": ch_id,
                        "channel_name": ch.get("name", ch_id),
                        "user": msg_user,
                        "text": text,
                        "ts": ts,
                        "thread_ts": msg.get("thread_ts", ""),
                        "is_mention": f"<@{my_user_id}>" in text if my_user_id else False,
                        "received_at": datetime.now(timezone.utc).isoformat(),
                    }

                    with _lock:
                        _messages.append(new_msg)

            except SlackApiError:
                continue

    except SlackApiError as e:
        logger.error("Failed to fetch recent messages: %s", e.response.get("error", str(e)))


def mark_processed(message_ids: list[str]):
    """지정된 메시지를 처리 완료로 표시."""
    with _lock:
        _processed_ids.update(message_ids)


def send_reply(channel: str, thread_ts: str, text: str) -> dict:
    """Slack 채널/스레드에 메시지 전송."""
    bot_token = os.getenv("SLACK_BOT_TOKEN", "")
    client = WebClient(token=bot_token)

    try:
        kwargs = {"channel": channel, "text": text}
        if thread_ts:
            kwargs["thread_ts"] = thread_ts
        result = client.chat_postMessage(**kwargs)
        return {"ok": True, "ts": result["ts"]}
    except SlackApiError as e:
        logger.error("Failed to send reply: %s", e.response["error"])
        return {"ok": False, "error": e.response["error"]}


def get_channels() -> list[dict]:
    """사용자가 참여 중인 채널 목록 반환."""
    bot_token = os.getenv("SLACK_BOT_TOKEN", "")
    client = WebClient(token=bot_token)

    try:
        result = client.conversations_list(
            types="public_channel,private_channel",
            exclude_archived=True,
            limit=200,
        )
        channels = []
        for ch in result.get("channels", []):
            channels.append({
                "id": ch["id"],
                "name": ch.get("name", ""),
                "is_member": ch.get("is_member", False),
                "is_private": ch.get("is_private", False),
            })
        return channels
    except SlackApiError as e:
        logger.error("Failed to list channels: %s", e.response["error"])
        return []


def get_user_info(user_id: str) -> dict:
    """Slack 사용자 프로필 정보 반환."""
    bot_token = os.getenv("SLACK_BOT_TOKEN", "")
    client = WebClient(token=bot_token)

    try:
        result = client.users_info(user=user_id)
        user = result.get("user", {})
        profile = user.get("profile", {})
        return {
            "id": user.get("id", ""),
            "name": user.get("name", ""),
            "real_name": user.get("real_name", ""),
            "display_name": profile.get("display_name", ""),
            "email": profile.get("email", ""),
            "avatar": profile.get("image_72", ""),
        }
    except SlackApiError as e:
        logger.error("Failed to get user info: %s", e.response["error"])
        return {}


def get_workspace_users() -> list[dict]:
    """워크스페이스의 활성 사용자 목록 반환 (봇 제외)."""
    bot_token = os.getenv("SLACK_BOT_TOKEN", "")
    client = WebClient(token=bot_token)

    try:
        result = client.users_list()
        users = []
        for member in result.get("members", []):
            if member.get("deleted") or member.get("is_bot") or member.get("id") == "USLACKBOT":
                continue
            profile = member.get("profile", {})
            users.append({
                "id": member["id"],
                "name": member.get("name", ""),
                "real_name": member.get("real_name", ""),
                "display_name": profile.get("display_name", "") or member.get("real_name", ""),
                "avatar": profile.get("image_72", ""),
            })
        return sorted(users, key=lambda u: u["display_name"])
    except SlackApiError as e:
        logger.error("Failed to list users: %s", e.response["error"])
        return []


def set_current_user(user_id: str) -> dict:
    """현재 사용자를 설정하고 프로필 정보 반환."""
    info = get_user_info(user_id)
    if info and info.get("id"):
        with _settings_lock:
            _filter_settings["user_id"] = info["id"]
            _filter_settings["user_name"] = info.get("display_name") or info.get("real_name", "")
        return info
    return {}


def get_current_user() -> dict:
    """현재 설정된 사용자 정보 반환."""
    with _settings_lock:
        uid = _filter_settings["user_id"]
        uname = _filter_settings["user_name"]
    if uid:
        return {"id": uid, "name": uname}
    return {}


def get_filter_settings() -> dict:
    """현재 필터 설정 반환."""
    with _settings_lock:
        return dict(_filter_settings)


def update_filter_settings(settings: dict) -> dict:
    """필터 설정 업데이트. channels, keywords 키 지원."""
    with _settings_lock:
        if "channels" in settings:
            _filter_settings["channels"] = settings["channels"]
        if "keywords" in settings:
            _filter_settings["keywords"] = settings["keywords"]
        return dict(_filter_settings)

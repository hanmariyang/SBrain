"""
Slack 메시지 AI 분석 서비스.

Anthropic Claude API를 사용하여 수신된 Slack 메시지를 분석하고,
긴급도·액션 유형·요약·초안 답장·캘린더 이벤트를 반환한다.
"""

import json
import logging
import os

import anthropic

logger = logging.getLogger(__name__)

SYSTEM_PROMPT = """당신은 사용자의 업무 비서 AI입니다.
Slack에서 수신된 메시지를 분석하여 각 메시지에 대해 다음 정보를 JSON 배열로 반환하세요.

각 메시지 항목:
- message_id: 메시지 고유 ID (입력에서 제공됨)
- urgency: "high" | "medium" | "low" — 긴급도 판단
- action_type: "reply" | "calendar" | "both" | "none" — 필요한 액션
- summary: 메시지 핵심 요약 (한국어, 1~2문장)
- draft_reply: 추천 답장 초안 (한국어, 전문적 톤). action_type이 "none"이면 빈 문자열.
- calendar_event: 일정 관련 메시지인 경우 이벤트 정보 객체, 아니면 null
  - title: 일정 제목
  - date: 날짜 (YYYY-MM-DD 또는 추정값)
  - time: 시간 (HH:MM 또는 추정값)
  - duration_minutes: 예상 소요 시간(분)

응답은 반드시 유효한 JSON 배열만 반환하세요. 다른 텍스트는 포함하지 마세요.
"""


def analyze_messages(messages: list[dict]) -> list[dict]:
    """
    Slack 메시지 목록을 Claude로 분석하여 구조화된 결과 반환.

    Args:
        messages: slack_service에서 받은 메시지 딕셔너리 리스트

    Returns:
        분석 결과 딕셔너리 리스트
    """
    api_key = os.getenv("ANTHROPIC_API_KEY", "")
    if not api_key:
        logger.error("ANTHROPIC_API_KEY is not set")
        return []

    if not messages:
        return []

    # 분석 요청용 메시지 포맷 구성
    formatted = []
    for msg in messages:
        formatted.append({
            "message_id": msg["id"],
            "channel": msg.get("channel", ""),
            "user": msg.get("user", ""),
            "text": msg.get("text", ""),
            "ts": msg.get("ts", ""),
            "is_mention": msg.get("is_mention", False),
        })

    user_content = json.dumps(formatted, ensure_ascii=False, indent=2)

    try:
        client = anthropic.Anthropic(api_key=api_key)
        response = client.messages.create(
            model="claude-sonnet-4-20250514",
            max_tokens=4096,
            system=SYSTEM_PROMPT,
            messages=[
                {"role": "user", "content": user_content},
            ],
        )

        # 응답 텍스트에서 JSON 추출
        result_text = response.content[0].text.strip()

        # 코드 블록으로 감싸진 경우 처리
        if result_text.startswith("```"):
            lines = result_text.split("\n")
            # 첫 줄(```json)과 마지막 줄(```) 제거
            lines = [l for l in lines if not l.strip().startswith("```")]
            result_text = "\n".join(lines)

        results = json.loads(result_text)
        return results

    except json.JSONDecodeError as e:
        logger.error("Failed to parse Claude response as JSON: %s (text: %s)", e, result_text[:200] if 'result_text' in dir() else 'N/A')
        return [{"error": f"JSON parse failed: {e}"}]
    except anthropic.APIError as e:
        logger.error("Anthropic API error: %s", e)
        return [{"error": f"Anthropic API: {e}"}]
    except Exception as e:
        logger.error("Unexpected error during message analysis: %s", e, exc_info=True)
        return [{"error": f"Unexpected: {e}"}]

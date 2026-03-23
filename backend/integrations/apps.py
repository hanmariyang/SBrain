import logging
import os
import threading

from django.apps import AppConfig

logger = logging.getLogger(__name__)

_socket_mode_started = False


class IntegrationsConfig(AppConfig):
    default_auto_field = "django.db.models.BigAutoField"
    name = "integrations"

    def ready(self):
        global _socket_mode_started

        # gunicorn worker 중복 실행 방지
        if _socket_mode_started:
            return
        _socket_mode_started = True

        slack_app_token = os.getenv("SLACK_APP_TOKEN", "")
        slack_bot_token = os.getenv("SLACK_BOT_TOKEN", "")

        if slack_app_token and slack_bot_token:
            from .slack_service import start_socket_mode

            thread = threading.Thread(
                target=start_socket_mode,
                daemon=True,
            )
            thread.start()
            logger.info("Slack Socket Mode listener started in daemon thread")
        else:
            logger.info(
                "Slack tokens not configured — Socket Mode listener skipped"
            )

from django.urls import path

from . import calendar_views, slack_views

urlpatterns = [
    # Slack
    path("slack/scan/", slack_views.slack_scan, name="slack-scan"),
    path("slack/messages/", slack_views.slack_messages, name="slack-messages"),
    path("slack/reply/", slack_views.slack_reply, name="slack-reply"),
    path("slack/channels/", slack_views.slack_channels, name="slack-channels"),
    path("slack/status/", slack_views.slack_status, name="slack-status"),
    path("slack/settings/", slack_views.slack_settings, name="slack-settings"),
    # Google Calendar
    path("calendar/auth/", calendar_views.calendar_auth, name="calendar-auth"),
    path(
        "calendar/auth/callback/",
        calendar_views.calendar_auth_callback,
        name="calendar-auth-callback",
    ),
    path("calendar/status/", calendar_views.calendar_status, name="calendar-status"),
    path("calendar/events/", calendar_views.calendar_events, name="calendar-events"),
    path(
        "calendar/events/<str:event_id>/",
        calendar_views.calendar_event_detail,
        name="calendar-event-detail",
    ),
]

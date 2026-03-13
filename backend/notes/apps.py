from django.apps import AppConfig


class NotesConfig(AppConfig):
    default_auto_field = "django.db.models.BigAutoField"
    name = "notes"

    def ready(self):
        from .db import init_vec_table

        try:
            init_vec_table()
        except Exception:
            pass

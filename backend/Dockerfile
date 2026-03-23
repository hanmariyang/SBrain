FROM python:3.11-slim

WORKDIR /app

# System deps for psycopg2 + pg_dump/pg_restore
RUN apt-get update && apt-get install -y --no-install-recommends \
    libpq-dev gcc postgresql-client \
    && rm -rf /var/lib/apt/lists/*

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY . .

RUN python manage.py collectstatic --noinput 2>/dev/null || true

EXPOSE ${PORT:-8765}

CMD ["sh", "-c", "python manage.py migrate --run-syncdb 2>/dev/null; gunicorn config.wsgi:application --bind 0.0.0.0:${PORT:-8765} --workers 1 --threads 4 --timeout 120 --preload"]

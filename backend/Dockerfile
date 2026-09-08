# syntax=docker/dockerfile:1
FROM python:3.12-slim

WORKDIR /app

# Create a non-root user
RUN addgroup --system app && adduser --system --ingroup app app

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY app.py entrypoint.sh ./
RUN chmod +x entrypoint.sh && chown -R app:app /app

USER app

EXPOSE 5000

ENTRYPOINT ["./entrypoint.sh"]

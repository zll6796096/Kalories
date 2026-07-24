# syntax=docker/dockerfile:1.7

FROM node:22-bookworm-slim AS frontend

WORKDIR /app

COPY package.json package-lock.json ./
RUN npm ci

COPY index.html metadata.json tsconfig.json vite.config.ts ./
COPY public ./public
COPY src ./src
RUN npm run build


FROM python:3.12-slim AS runtime

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PORT=8080

WORKDIR /app

COPY requirements.txt ./
RUN python -m pip install --no-cache-dir -r requirements.txt

RUN useradd --create-home --uid 10001 appuser

COPY api ./api
COPY lib ./lib
COPY --from=frontend --chown=appuser:appuser /app/dist ./dist

USER appuser

EXPOSE 8080

CMD ["sh", "-c", "exec uvicorn api.analyze:app --host 0.0.0.0 --port ${PORT:-8080}"]

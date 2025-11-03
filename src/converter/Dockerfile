FROM python:3.12-slim-bullseye

RUN apt-get update \
  && apt-get install -y --no-install-recommends --no-install-suggests \
  build-essential pkg-config ffmpeg \
  && pip install --no-cache-dir --upgrade pip

WORKDIR /app
COPY ./pyproject.toml /app
RUN pip install --no-cache-dir -e .
COPY . /app

CMD ["python3", "consumer.py"]
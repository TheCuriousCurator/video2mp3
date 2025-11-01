FROM python:3.12-slim-bullseye

RUN apt-get update \
  && apt-get install -y --no-install-recommends --no-install-suggests \
  build-essential default-libmysqlclient-dev pkg-config \
  && pip install --no-cache-dir --upgrade pip

WORKDIR /app
COPY ./pyproject.toml /app
RUN pip install --no-cache-dir -e .
COPY . /app

EXPOSE 5000

CMD ["python3", "server.py"]
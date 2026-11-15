# Clean rebuild: official Python base, locked PyPI packages and verified output trees.
ARG BASE_IMAGE=python:3.14.9-slim
FROM ${BASE_IMAGE}
RUN apt-get update && apt-get install -y --no-install-recommends git ca-certificates \
    && rm -rf /var/lib/apt/lists/*
COPY dependencies.lock /dependencies.lock
RUN python -m pip install --no-cache-dir --index-url https://pypi.org/simple -r /dependencies.lock
COPY backend /seed-source
RUN cd /seed-source && python scripts/seed_outputs.py build --lock outputs.lock.json --dest /opt/fiestaboard/seed/outputs \
    && rm -rf /seed-source
WORKDIR /app
ENTRYPOINT ["python"]

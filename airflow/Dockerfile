FROM apache/airflow:2.9.2-python3.11

USER root
# Build tools needed by some Python packages (e.g. psycopg2)
RUN apt-get update && apt-get install -y --no-install-recommends \
    gcc \
    libpq-dev \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# dlt writes its pipeline/incremental state here; the dlt_state volume mounts
# at this path, so it must exist and be airflow-owned BEFORE the mount.
RUN mkdir -p /opt/airflow/.dlt && chown -R airflow:0 /opt/airflow/.dlt

USER airflow

# Install everything our pipeline needs inside the Airflow image
COPY requirements.txt /requirements.txt
RUN pip install --no-cache-dir --upgrade pip \
    && pip install --no-cache-dir -r /requirements.txt
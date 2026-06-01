from datetime import datetime, timedelta

from airflow import DAG
from airflow.operators.python import PythonOperator
from airflow.operators.bash import BashOperator

from extractor.src.extractor import extract_all
from dlt_pipeline.lake_to_warehouse import run as run_dlt_load

DBT_DIR = "/opt/airflow/dbt_project"

default_args = {
    "owner": "data-eng",
    "retries": 2,                                   # >= 2 retries
    "retry_delay": timedelta(minutes=2),
    "retry_exponential_backoff": True,              # exponential backoff
    "max_retry_delay": timedelta(minutes=15),
}

with DAG(
    dag_id="retailco_pipeline",
    description="RetailCo ELT: extract -> load -> dbt (snapshot, staging, marts, test)",
    schedule="@daily",
    start_date=datetime(2024, 1, 1),
    catchup=False,                                  # backfill on demand, not auto
    default_args=default_args,
    tags=["retailco"],
) as dag:

    extract = PythonOperator(
        task_id="extract_erp_to_lake",
        python_callable=extract_all,
    )

    load = PythonOperator(
        task_id="load_lake_to_warehouse",
        python_callable=run_dlt_load,
        do_xcom_push=False,                         # dlt LoadInfo isn't JSON-serializable
    )

    dbt_snapshot = BashOperator(
        task_id="dbt_snapshot",
        bash_command=f"cd {DBT_DIR} && dbt deps && dbt snapshot",
    )

    dbt_staging = BashOperator(
        task_id="dbt_run_staging",
        bash_command=f"cd {DBT_DIR} && dbt run --select staging",
    )

    dbt_marts = BashOperator(
        task_id="dbt_run_marts",
        bash_command=f"cd {DBT_DIR} && dbt run --select marts",
    )

    dbt_test = BashOperator(
        task_id="dbt_test",
        bash_command=f"cd {DBT_DIR} && dbt test",
    )

    extract >> load >> dbt_snapshot >> dbt_staging >> dbt_marts >> dbt_test
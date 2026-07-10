# Parquet → MinIO → Apache Iceberg → Trino

> Store a Parquet file in MinIO, register it as an Apache Iceberg table via Hive Metastore, and query it through Trino — all running locally in Docker.

---

## Architecture

```
[titanic.parquet]
       │
       ▼
  MinIO (warehouse bucket)          ← S3-compatible local object store
       │
       ▼
  Apache Iceberg (table format)     ← metadata layer: schema, snapshots, manifests
       │
       ▼
  Hive Metastore (catalog)          ← stores table registry for Trino
       │
       ▼
  Trino (SQL engine)                ← pure compute, reads Iceberg via Metastore
```

---

## Stack

| Component | Role |
|-----------|------|
| **MinIO** | S3-compatible local object storage (bucket: `warehouse`) |
| **Apache Iceberg** | Open table format — wraps Parquet files with a metadata layer |
| **Hive Metastore** | Catalog service storing Iceberg table definitions |
| **Trino** | Distributed SQL query engine — no data stored here |
| **Docker** | All services run as local containers |

---

## Key Concept

A `.parquet` file in a bucket is just bytes — Trino has no way to query it directly. Apache Iceberg sits in between: it creates a `metadata/` layer (snapshot files, manifests) that tells Trino what the schema is, which files belong to the table, and what version is current. Hive Metastore is the address book that Trino checks to find where each table's Iceberg metadata lives.

The layers are independent. You can swap MinIO for S3, or Trino for Spark, without changing the others. That's the point of the format.

---

## Repo Structure

```
├── sql/
│   └── task1_setup.sql       # Full Trino SQL sequence for Task 1
├── docs/
│   └── task1_devlog.md       # Step-by-step dev log with errors and fixes
└── README.md
```

---

## Quick Start

```bash
# 1. Start services in order (Trino connects to Metastore at startup)
docker start minio
docker start metastore-standalone
docker start trino

# 2. Enter Trino CLI
docker exec -it trino trino

# 3. Run commands from sql/task1_setup.sql in the CLI
```

---

## Table Schema — `iceberg.titanic.passengers`

```sql
CREATE TABLE iceberg.titanic.passengers (
  PassengerId  BIGINT,
  Survived     INTEGER,
  Pclass       INTEGER,
  Name         VARCHAR,
  Sex          VARCHAR,
  Age          DOUBLE,
  SibSp        INTEGER,
  Parch        INTEGER,
  Ticket       VARCHAR,
  Fare         DOUBLE,
  Cabin        VARCHAR,
  Embarked     VARCHAR
);
```

**Type rationale:**
- `BIGINT` for `PassengerId` — 64-bit; ID columns should have room to grow
- `INTEGER` for flags and small counts — 32-bit is enough
- `DOUBLE` for `Age` and `Fare` — 64-bit float for decimal values
- `VARCHAR` for all text — variable-length, no fixed upper bound needed

---

## SQL Execution Sequence

Full annotated commands are in [`sql/task1_setup.sql`](sql/task1_setup.sql).  
Short version:

```sql
SHOW CATALOGS;
SHOW SCHEMAS FROM iceberg;

DROP SCHEMA IF EXISTS iceberg.titanic CASCADE;

CREATE SCHEMA iceberg.titanic
WITH (location = 's3://warehouse/warehouse/titanic');

CREATE TABLE iceberg.titanic.passengers ( ... );

INSERT INTO iceberg.titanic.passengers VALUES
(1, 0, 3, 'Braund, Mr. Owen Harris', 'male', 22, 1, 0, 'A/5 21171', 7.25, NULL, 'S');

SELECT * FROM iceberg.titanic.passengers;
SELECT COUNT(*) FROM iceberg.titanic.passengers;
```

---

## Errors Faced

See [`docs/task1_devlog.md`](docs/task1_devlog.md) for root causes and fixes. Summary:

| # | Error | Fix |
|---|-------|-----|
| 1 | `SHOW SCHEMAS` only returned `information_schema` | Schema doesn't auto-create — run `CREATE SCHEMA ... WITH (location = ...)` |
| 2 | Schema creation failed with `s3://titanic` | Correct URI: `s3://warehouse/warehouse/titanic` (bucket + prefix) |
| 3 | Docker containers not running | `docker start minio metastore-standalone trino` in order |
| 4 | `iceberg` not in `SHOW CATALOGS` | Verify `iceberg.properties` is mounted at `/etc/trino/catalog/`, restart Trino |
| 5 | `SELECT *` returned 0 rows after table creation | Iceberg tracks files, doesn't scan them — pre-existing Parquet isn't registered; used `INSERT INTO` to write first managed row |
| 6 | `BIGINT` vs `INTEGER` vs `DOUBLE` confusion | Size-based: 32-bit int / 64-bit int / 64-bit float — see devlog for reasoning |

---

## Task 2 — Next Steps

- Generate relational synthetic dataset with Python + Faker + PostgreSQL (with FK constraints)
- Export tables as Parquet files, upload to MinIO `warehouse` bucket
- Register as Iceberg tables
- Run multi-table analytical SQL through Trino

---

## Author

**Yash Ladlapure**  
B.Tech CSE @ MIT-WPU (2023–2027)  
[GitHub](https://github.com/YashLadlapure) · [Portfolio](https://yashladlapure.github.io/portfolio-website/)

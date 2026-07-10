# Parquet → MinIO → Apache Iceberg → Trino

> **Internship Task 1 @ Augmented Transformations, Pune**  
> End-to-end data lakehouse PoC: store a Parquet file in MinIO, register it as an Apache Iceberg table via Hive Metastore, and query it through Trino.

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
| **Apache Iceberg** | Open table format wrapping Parquet files with metadata |
| **Hive Metastore** | Catalog service storing Iceberg table definitions |
| **Trino** | Distributed SQL query engine — no data stored here |
| **Docker** | All services run as local containers |

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
# 1. Start services in order (order matters — Trino depends on Metastore at startup)
docker start minio
docker start metastore-standalone
docker start trino

# 2. Enter Trino CLI
docker exec -it trino trino

# 3. Run sql/task1_setup.sql commands in the CLI
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
- `BIGINT` for `PassengerId` — 64-bit; safe for IDs at scale  
- `INTEGER` for flags and small counts — 32-bit is sufficient  
- `DOUBLE` for `Age` and `Fare` — 64-bit IEEE 754 float for decimal values  
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

See [`docs/task1_devlog.md`](docs/task1_devlog.md) for the full error log with root causes and fixes. Summary:

| # | Error | Fix |
|---|-------|-----|
| 1 | `SHOW SCHEMAS` only showed `information_schema` | Create schema explicitly with `CREATE SCHEMA ... WITH (location = ...)` |
| 2 | Schema creation failed — wrong S3 URI `s3://titanic` | Correct URI: `s3://warehouse/warehouse/titanic` |
| 3 | Docker containers not running | `docker start minio metastore-standalone trino` in order |
| 4 | `iceberg` catalog missing in `SHOW CATALOGS` | Verify `iceberg.properties` is mounted at `/etc/trino/catalog/` |
| 5 | `SELECT *` returned 0 rows after table creation | Parquet file ≠ Iceberg table; used `INSERT INTO` to write first Iceberg-managed row |
| 6 | Type confusion: `BIGINT` vs `INTEGER` vs `DOUBLE` | Size-based choice: 32-bit int / 64-bit int / 64-bit float |

---

## Key Concept

Apache Iceberg is **not** storage and **not** a query engine — it is the contract between them. It gives Trino the schema, file locations, and snapshot version. Without it, Trino sees raw bytes. With it, Trino sees a fully managed, ACID-compliant table backed by open Parquet files in commodity object storage.

---

## Task 2 — Next Steps

- [ ] Generate relational synthetic dataset with Python + Faker + PostgreSQL (with FK constraints)
- [ ] Export tables as Parquet files, upload to MinIO `warehouse` bucket
- [ ] Register Parquet files as Iceberg tables
- [ ] Run multi-table analytical SQL through Trino

---

## Author

**Yash Ladlapure**  
B.Tech CSE @ MIT-WPU (2023–2027) | Software Engineer Intern @ Augmented Transformations  
[GitHub](https://github.com/YashLadlapure) · [Portfolio](https://yashladlapure.github.io/portfolio-website/)

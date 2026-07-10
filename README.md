# Parquet → MinIO → Apache Iceberg → Trino

Local data lakehouse PoC — Parquet file in MinIO, registered as an Iceberg table, queried through Trino. Everything runs in Docker.

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
  Hive Metastore (catalog)          ← table registry that Trino reads from
       │
       ▼
  Trino (SQL engine)                ← pure compute, reads Iceberg via Metastore
```

---

## Stack

| Component | Role |
|-----------|------|
| MinIO | S3-compatible local object storage (bucket: `warehouse`) |
| Apache Iceberg | Table format — adds metadata layer on top of Parquet files |
| Hive Metastore | Stores table definitions so Trino can find them |
| Trino | SQL query engine — no data stored here |
| Docker | All services run as containers |

---

## How Iceberg fits in

A `.parquet` file in a bucket is just bytes — Trino can't query it directly. Iceberg adds a `metadata/` layer that tells Trino the schema, which files belong to the table, and what version is current. Hive Metastore stores where that metadata lives so Trino knows where to look.

The layers are swappable. MinIO can be replaced with S3, Trino with Spark — Iceberg stays the same.

---

## Repo Structure

```
├── sql/
│   └── task1_setup.sql
├── docs/
│   └── task1_devlog.md
└── README.md
```

---

## Quick Start

```bash
docker start minio
docker start metastore-standalone
docker start trino
docker exec -it trino trino
```

Then run the commands from `sql/task1_setup.sql` inside the CLI.

---

## Table Schema

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

`BIGINT` for the ID, `INTEGER` for flags and counts, `DOUBLE` for decimals, `VARCHAR` for everything text.

---

## Errors

Full notes in [`docs/task1_devlog.md`](docs/task1_devlog.md). Short version:

| # | What happened | Fix |
|---|---------------|-----|
| 1 | `SHOW SCHEMAS` only showed `information_schema` | Had to create the schema manually with `CREATE SCHEMA ... WITH (location = ...)` |
| 2 | Schema creation failed — wrong S3 path | Correct path is `s3://warehouse/warehouse/titanic` |
| 3 | Containers weren't running | Started them in order: minio → metastore → trino |
| 4 | `iceberg` catalog not in `SHOW CATALOGS` | `iceberg.properties` wasn't mounted at `/etc/trino/catalog/` |
| 5 | `SELECT *` returned 0 rows | Iceberg doesn't auto-register existing files — used `INSERT INTO` to write a managed row |
| 6 | Wasn't sure on types | `INTEGER` for small ints, `BIGINT` for IDs, `DOUBLE` for decimals |

---

## Author

**Yash Ladlapure**  
B.Tech CSE @ MIT-WPU  
[GitHub](https://github.com/YashLadlapure) · [Portfolio](https://yashladlapure.github.io/portfolio-website/)

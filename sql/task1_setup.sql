-- Task 1: Parquet → MinIO → Apache Iceberg → Trino
-- Run all commands inside the Trino CLI
-- Entry: docker exec -it trino trino

-- Always check this first — if 'iceberg' isn't listed, the catalog config isn't mounted correctly
-- and everything below will fail
SHOW CATALOGS;

-- See what schemas exist under iceberg
SHOW SCHEMAS FROM iceberg;

-- Useful when re-running from scratch; CASCADE drops any tables in the schema too
DROP SCHEMA IF EXISTS iceberg.titanic CASCADE;

-- Location tells Iceberg (and Hive Metastore) where to write metadata for this schema
-- Format: s3://<bucket>/<prefix>  —  first 'warehouse' is the bucket name, second is a folder inside it
CREATE SCHEMA iceberg.titanic
WITH (location = 's3://warehouse/warehouse/titanic');

-- PassengerId is BIGINT even though this dataset is tiny — convention for ID columns is to give them room
-- Survived/Pclass/SibSp/Parch are INTEGER — small whole numbers, 32-bit is fine
-- Age/Fare are DOUBLE — decimal values need floating point
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

-- Iceberg doesn't auto-register a pre-existing Parquet file in the bucket
-- This INSERT validates the write path: Trino writes an Iceberg-managed Parquet file
-- and updates the snapshot metadata — confirming the full pipeline works
INSERT INTO iceberg.titanic.passengers VALUES
(1, 0, 3, 'Braund, Mr. Owen Harris', 'male', 22, 1, 0, 'A/5 21171', 7.25, NULL, 'S');

-- Should return the row inserted above
SELECT * FROM iceberg.titanic.passengers;

-- Should return 1
SELECT COUNT(*) FROM iceberg.titanic.passengers;

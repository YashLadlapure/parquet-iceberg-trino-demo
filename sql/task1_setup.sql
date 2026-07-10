-- Task 1: Parquet → MinIO → Iceberg → Trino
-- run inside trino CLI: docker exec -it trino trino

-- if 'iceberg' isn't here, the catalog config isn't mounted right — stop and fix that first
SHOW CATALOGS;

SHOW SCHEMAS FROM iceberg;

-- cleans up if re-running
DROP SCHEMA IF EXISTS iceberg.titanic CASCADE;

-- s3://<bucket>/<prefix> — bucket is 'warehouse', folder inside it is 'warehouse/titanic'
CREATE SCHEMA iceberg.titanic
WITH (location = 's3://warehouse/warehouse/titanic');

-- PassengerId as BIGINT even though dataset is small — ID columns should have room
-- Age and Fare are DOUBLE because they're decimals
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

-- existing titanic.parquet in the bucket isn't part of this table until explicitly registered
-- inserting one row to check the write path works
INSERT INTO iceberg.titanic.passengers VALUES
(1, 0, 3, 'Braund, Mr. Owen Harris', 'male', 22, 1, 0, 'A/5 21171', 7.25, NULL, 'S');

SELECT * FROM iceberg.titanic.passengers;

SELECT COUNT(*) FROM iceberg.titanic.passengers;

#!/usr/bin/python
"""BigQuery I/O PySpark example."""
from pyspark.sql import SparkSession
import os

spark = SparkSession \
  .builder \
  .appName('spark-bigquery-demo') \
  .getOrCreate()

catalog = os.get_env("lakehouse_catalog","lakehouse_catalog")
database = os.get_env("lakehouse_db","lakehouse_db")
bucket = os.get_env("temp_bucket","gcp-lakehouse-provisioner-8a68acad")

# Create BigLake Catalog and Database if they are not already created.
spark.sql(f"CREATE NAMESPACE IF NOT EXISTS {catalog};")
spark.sql(f"CREATE DATABASE IF NOT EXISTS {catalog}.{database};") # 20230309 Fix this starting here.
spark.sql(f"DROP TABLE IF EXISTS {catalog}.{database}.agg_events_iceberg;")

# Use the Cloud Storage bucket for temporary BigQuery export data used
# by the connector.

spark.conf.set('temporaryGcsBucket', bucket)

# Load data from BigQuery.
words = spark.read.format('bigquery') \
  .option('table', 'bigquery-public-data:samples.shakespeare') \
  .load()
words.createOrReplaceTempView('words')

# Perform word count.
word_count = spark.sql(
    'SELECT word, SUM(word_count) AS word_count FROM words GROUP BY word')
word_count.show()
word_count.printSchema()

# Saving the data to BigQuery
word_count.write.format('bigquery') \
  .option('table', 'gcp_lakehouse.wordcount_output') \
  .save()

#!/usr/bin/python
"""BigQuery I/O PySpark example."""
from pyspark.sql import SparkSession

spark = SparkSession \
  .builder \
  .appName('spark-bigquery-demo') \
  .getOrCreate()

spark.sql("CREATE NAMESPACE IF NOT EXISTS lakehouse;")
spark.sql("CREATE NAMESPACE IF NOT EXISTS lakehouse.lakehouse_db;")
spark.sql("DROP TABLE IF EXISTS lakehouse.lakehouse_db.agg_events_iceberg;")

# Use the Cloud Storage bucket for temporary BigQuery export data used
# by the connector.
bucket = "gcp-lakehouse-provisioner-8a68acad"
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
  .option('table', 'wordcount_dataset.wordcount_output') \
  .save()

#!/bin/bash
# LocalStack initialization script
# Runs automatically when LocalStack is ready

echo "Initializing LocalStack resources..."

# Create database credentials secret
awslocal secretsmanager create-secret \
  --name healthcare/db \
  --secret-string '{
    "host": "postgres",
    "port": 5432,
    "username": "postgres",
    "password": "postgres",
    "dbname": "healthcare"
  }' || true

# Create YouTube API key secret (placeholder for local dev)
awslocal secretsmanager create-secret \
  --name healthcare/youtube \
  --secret-string '{
    "api_key": "YOUTUBE_API_KEY"
  }' || true

echo "LocalStack initialization complete."

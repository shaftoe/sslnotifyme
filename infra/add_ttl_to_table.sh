#!/bin/bash
set -u
readonly table=$1

if aws dynamodb describe-time-to-live --table-name $table | grep -q DISABLED; then
    aws dynamodb update-time-to-live --table-name $table --time-to-live-specification Enabled=true,AttributeName=ttl
fi

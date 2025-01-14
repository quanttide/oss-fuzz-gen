#!/bin/bash
# Copyright 2024 Google LLC
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.


## Usage:
##   bash report/upload_report.sh results_dir [gcs_dir]
##
##   results_dir is the local directory with the experiment results.
##   gcs_dir is the name of the directory for the report in gs://oss-fuzz-gcb-experiment-run-logs/Result-reports/.
##     Defaults to '$(whoami)-%YY-%MM-%DD'.

RESULTS_DIR=$1
GCS_DIR=$2
BENCHMARK_SET=$3
WEB_PORT=8080
DATE=$(date '+%Y-%m-%d')

# Sleep 5 minutes for the experiment to start.
sleep 300

if [[ $RESULTS_DIR = '' ]]
then
  echo 'This script takes the results directory as the first argument'
  exit 1
fi

if [[ $GCS_DIR = '' ]]
then
  GCS_DIR="$(whoami)-${DATE:?}"
  echo "GCS directory was not specified as the second argument. Defaulting to ${GCS_DIR:?}."
fi

mkdir results-report

while true; do
  # Spin up the web server generating the report (and bg the process).
  $PYTHON -m report.web "${RESULTS_DIR:?}" "${WEB_PORT:?}" "${BENCHMARK_SET:?}" &
  pid_web=$!

  cd results-report || exit 1

  # Recursively get all the experiment results.
  echo "Download results from localhost."
  wget2 --quiet --inet4-only --no-host-directories --http2-request-window 10 --recursive localhost:${WEB_PORT:?}/ 2>&1

  # Also fetch the sorted line cov diff report.
  wget2 --quiet --inet4-only localhost:${WEB_PORT:?}/sort -O sort.html 2>&1

  # Stop the server.
  kill -9 "$pid_web"

  # Upload the report to GCS.
  echo "Uploading the report."
  gsutil -q -m -h "Content-Type:text/html" \
         -h "Cache-Control:public, max-age=3600" \
         cp -r . "gs://oss-fuzz-gcb-experiment-run-logs/Result-reports/${GCS_DIR:?}"

  cd ..

  # Upload the raw results into the same GCS directory
  echo "Uploading the raw results."
  gsutil -q -m cp -r "${RESULTS_DIR:?}" \
         "gs://oss-fuzz-gcb-experiment-run-logs/Result-reports/${GCS_DIR:?}"

  echo "See the published report at https://llm-exp.oss-fuzz.com/Result-reports/${GCS_DIR:?}/"

  if [[ -f /experiment_ended ]]; then
    echo "Experiment finished."
    exit
  fi

  echo "Experiment is running..."
  sleep 600
done

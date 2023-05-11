#!/usr/bin/env bash

# DIR where the current script resides
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"
source .env
skip=${1:-'0'}
# concurrency=${2:-'500'}   # 5,20 Maximum concurrency determined by the bottleneck - the submission server and storage space
concurrency=${2:-'2000'} # concurrency>=queue_size
pipeline=${3:-'illumina'}   # nanopore
root_dir=${4:-"/scratch/${PROJECT_ID}/nextflow"} 
batch_size=${5:-'15000'}
# batch_size=${5:-'3750'} # Storage capacity per job (Storage Max ~ 1500 samples in /project/) TODO: Submit array job if cannot handle large file download
profile=${6:-'hq'}
snapshot_date=${7:-'2023-04-18'}  #2022-09-26 2022-10-24 2022-11-21 2022-12-19
dataset_name=${8:-'sarscov2_metadata'}
project_id=${9:-'prj-int-dev-covid19-nf-gls'}
test_submission=true
# Row count and batches
table_name="${pipeline}_to_be_processed"
# sql="SELECT count(*) AS total FROM ${project_id}.${dataset_name}.${table_name}"
# row_count=$(bq --project_id="${project_id}" --format=csv query --use_legacy_sql=false "${sql}" | grep -v total)
row_count=75000
############################################
# as defined as queueSize in nextflow.config
############################################
queue_size=400     #20,40,100
batches=$(( row_count / batch_size + 1 ))
num_of_jobs=$(( concurrency / queue_size ))
echo "$batches $num_of_jobs"
#mem_limit=$(( batch_size / 2500 * 2048));mem_limit=$(( mem_limit > 2048 ? mem_limit : 2048 ))
export $(grep -v '^#' .env | xargs)

input_dir="${DIR}/data/${snapshot_date}"; mkdir -p "${input_dir}"

echo "$(( skip+num_of_jobs )) ${batches}"
for (( batch_index=skip;batch_index<skip+num_of_jobs&&batch_index<batches; batch_index++ )); do
  mkdir -p "${root_dir}/${pipeline}_${batch_index}"; cd "${root_dir}/${pipeline}_${batch_index}" || exit
  
  offset=$((batch_index * batch_size))
  echo ""
  echo "** Retrieving and reserving batch ${batch_index} with the size of ${batch_size} from the offset of ${offset}. **"
  sql="SELECT * FROM ${project_id}.${dataset_name}.${table_name} LIMIT ${batch_size} OFFSET ${offset}"
  # bq --project_id="${project_id}" --format=csv query --use_legacy_sql=false --max_rows="${batch_size}" "${sql}" \
  #   | awk 'BEGIN{ FS=","; OFS="\t" }{$1=$1; print $0 }' > "${input_dir}/${table_name}_${batch_index}.tsv"
  # gsutil -m cp "${input_dir}/${table_name}_${batch_index}.tsv" "gs://${dataset_name}/${table_name}_${batch_index}.tsv" && \
  # bq --project_id="${project_id}" load --source_format=CSV --replace=false --skip_leading_rows=1 --field_delimiter=tab \
  # --max_bad_records=0 "${dataset_name}.sra_processing" "gs://${dataset_name}/${table_name}_${batch_index}.tsv"
  sbatch --export=ALL --account=$PROJECT_ID -N 12 --cpus-per-task=128 --mem='32GB' -t 48:00:00 -p standard --wrap="${DIR}/hq.nextflow.sh ${input_dir}/${table_name}_${batch_index}.tsv \
    ${pipeline} ${profile} ${root_dir} ${batch_index} ${snapshot_date} ${test_submission}"
  # break
done

# sql="CREATE OR REPLACE TABLE ${dataset_name}.sra_processing AS SELECT DISTINCT * FROM ${dataset_name}.sra_processing"
# bq --project_id="${project_id}" --format=csv query --use_legacy_sql=false "${sql}"

#max_mem avg_mem swap stat exit_code exec_cwd exec_host
#bjobs -u all -d -o "jobid job_name user submit_time start_time finish_time run_time cpu_used slots min_req_proc max_req_proc nthreads delimiter='^'" > jobs.csv
num_of_snapshots=$(( batches / num_of_jobs + 1 ))
message="Row count: ${row_count}. Total number of batches: ${batches}, Number of jobs: ${num_of_jobs}, Number of snapshots: ${num_of_snapshots}."
echo $message
# if [[ $test_submission = true ]]
#   then
#     curl -X POST -H 'Content-type: application/json' --data '{"text": "Start running '"$profile"' \n'"$message"' ." }' $SLACK_WEBHOOK_URL
# fi

#!/bin/bash

set -e
set -u
set -x

export PGHOST=${PGHOST-192.168.99.100}
export PGPORT=${PGPORT-5432}
export PGDATABASE=${PGDATABASE-capstone}
export PGUSER=${PGUSER-cloud}
export PGPASSWORD=${PGPASSWORD-cloud}

function status_update {
	stat=$1 
	${SET_PSQL} <<-EOSQL
		UPDATE gene_analyses.analysis SET status = '${stat}', update_time = 'now()'
		WHERE analysis_id = '${analysis_id}';	
	EOSQL
	[ "$stat" != "ERROR" ] || exit 0;
}

analysis_id=${ANALYSIS_ID?"Please initialize analysis id"}
front="rows_"
out="_output"
output_table_name=${front}${analysis_id}${out}
SET_PSQL="psql -X --single-transaction -e -v ON_ERROR_STOP=1"	

tempDir=$(mktemp -d /tmp/variants_genes.XXX) || { status_update ERROR;}

status_update "RUNNING" 

echo "time for COPY INPUT:"
time ${SET_PSQL} -c  "\COPY gene_analyses.\"rows_${analysis_id}_genes\" TO '${tempDir}/rows_${analysis_id}_gene.csv' DELIMITER E'\t' CSV HEADER;" || { status_update ERROR; }

column_names=$( psql -t -c "SELECT string_agg(column_name, ',') FROM information_schema.columns WHERE table_name = 'rows_uuid_output' AND column_name IN ( SELECT column_name FROM information_schema.columns  WHERE table_name  = 'rows_uuid_output' ORDER BY ordinal_position) ; " )
input_file="${tempDir}/rows_${analysis_id}_gene.csv"
r_output_file="${tempDir}/${front}${analysis_id}${out}.csv" 

echo "time for R SCRIPT EXECUTION:"
no_lines=$( wc -l < ${input_file} )

time {  [ ${no_lines} -gt 1 ]   &&  R -e "source(file = '/scripts/script.r');count_genes( inputFile = '${input_file}', outputFile = '${r_output_file}', column_names ='${column_names[*]}')" ; }   ||   { status_update ERROR; }

echo "time for COPY OUTPUT:"
time if [ -f "$r_output_file" ]; then
	 ${SET_PSQL} <<-EOSQL 
		DROP TABLE IF EXISTS "gene_analyses"."${output_table_name}"; 
		CREATE TABLE "gene_analyses"."${output_table_name}" (LIKE 
			"gene_analyses"."rows_uuid_output"
			including defaults 
			including constraints 
			including indexes 
			); 
														 
		\COPY gene_analyses."${output_table_name}"(${column_names[*]})  FROM '${r_output_file}' WITH HEADER CSV DELIMITER E'\t';
	EOSQL
	status_update "COMPLETED"
else
	status_update "ERROR"
fi
echo time for TOTAL EXECUTION:
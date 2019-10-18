#!/usr/bin/env bash
#set -o xtrace
#Run from DE cluster with at least 2 worker nodes

export env_name='testenv-01'       ## needed for Ranger/atlas API
export datalake_name='testenv-01'  ## needed to create Ranger Admins role for group: cdp_<env_name>. This might be same as datalake_name
export user='myuserid'              ## Admin user. make sure IPA password is set for this user first
export password='BadPass#1'         ## replace with pasword
export lake_knox='10.10.0.5'       ## private IP address of DataLake master node
export s3bucket="s3a://mybucket/data"   ##replace with your data S3 bucket

#1. Confirm demo users/groups are in Ranger (e.g. joe_analyst, michelle_dpo, jeremy_contractor, diane_csr) else Ranger policy import will fail
#2. Confirm that group cdp_env_admin_<env name> is created and sync'd to Ranger. Confirm above user is part of this group or he won't have admin rights


git clone https://github.com/abajwa-hw/masterclass
cd masterclass/ranger-atlas/HortoniaMunichSetup


ranger_curl="curl -v -k -u ${user}:${password}"
ranger_url="https://${lake_knox}:8443/${datalake_name}/cdp-proxy-api/ranger/service"

#3. Create Admins role in Ranger with cdp_env_admin_<env name> e.g. cdp_env_admin_cdp-latest-public
${ranger_curl} -X GET -H "Content-Type: application/json" -H "Accept: application/json" ${ranger_url}/public/v2/api/roles

${ranger_curl} -X POST -H "Content-Type: application/json" -H "Accept: application/json" ${ranger_url}/public/v2/api/roles  -d @- <<EOF
{
   "name":"Admins",
   "description":"",
   "users":[

   ],
   "groups":[
      {
         "name":"cdp_${env_name}",
         "isAdmin":false
      }
   ],
   "roles":[

   ]
}
EOF


#4. Update Service def to include custom policy conditions

${ranger_curl} ${ranger_url}/public/v2/api/servicedef/name/hive \
  | jq '.options = {"enableDenyAndExceptionsInPolicies":"true"}' \
  | jq '.policyConditions = [
{
	  "itemId": 1,
	  "name": "resources-accessed-together",
	  "evaluator": "org.apache.ranger.plugin.conditionevaluator.RangerHiveResourcesAccessedTogetherCondition",
	  "evaluatorOptions": {},
	  "label": "Resources Accessed Together?",
	  "description": "Resources Accessed Together?"
},{
	"itemId": 2,
	"name": "not-accessed-together",
	"evaluator": "org.apache.ranger.plugin.conditionevaluator.RangerHiveResourcesNotAccessedTogetherCondition",
	"evaluatorOptions": {},
	"label": "Resources Not Accessed Together?",
	"description": "Resources Not Accessed Together?"
}
]' > hive.json


${ranger_curl} -i \
  -X PUT -H "Accept: application/json" -H "Content-Type: application/json" \
  -d @hive.json ${ranger_url}/public/v2/api/servicedef/name/hive
  


#5a. now import the Ranger resource based policies from UI (if error try incognito or diff browser/machine)
#5b. now import the Ranger tag based policies from UI (if error try incognito or diff browser/machine)
# TODO use CLI to automate import policies

#6. Add classifications
curl -v -k -X GET -u ${user}:${password}  https://${lake_knox}:8443/${datalake_name}/cdp-proxy-api/atlas/api/atlas/v2/types/typedefs
curl -v -k -X POST -u ${user}:${password} -H "Accept: application/json" -H "Content-Type: application/json" https://${lake_knox}:8443/${datalake_name}/cdp-proxy-api/atlas/api/atlas/v2/types/typedefs -d @data/classifications.json

#7. Import glossary
curl -v -k -X POST  -u ${user}:${password}  -H "Accept: application/json" -H "Content-Type: multipart/form-data" -H "Cache-Control: no-cache" -F data=@data/export-glossary.zip https://${lake_knox}:8443/${datalake_name}/cdp-proxy-api/atlas/api/atlas/admin/import

#8. Create dir structure in S3
hdfs dfs -mkdir ${s3bucket}/wwbankdata

s3base="${s3bucket}/wwbankdata/rawzone"


hdfs dfs -mkdir ${s3base}
hdfs dfs -mkdir ${s3base}/claim
hdfs dfs -mkdir ${s3base}/cost_savings
hdfs dfs -mkdir ${s3base}/finance
hdfs dfs -mkdir ${s3base}/finance/tax_2009
hdfs dfs -mkdir ${s3base}/finance/tax_2010
hdfs dfs -mkdir ${s3base}/finance/tax_2015
hdfs dfs -mkdir ${s3base}/worldwidebank
hdfs dfs -mkdir ${s3base}/worldwidebank/eu_countries
hdfs dfs -mkdir ${s3base}/worldwidebank/us_customers
hdfs dfs -mkdir ${s3base}/worldwidebank/ww_customers
hdfs dfs -mkdir ${s3base}/consent
hdfs dfs -mkdir ${s3base}/eu_countries
hdfs dfs -mkdir ${s3base}/hr
hdfs dfs -mkdir ${s3base}/hr/employees_raw
hdfs dfs -mkdir ${s3base}/hr/employees

hdfs dfs -mkdir ${s3base}/consent-trans
hdfs dfs -mkdir ${s3base}/ww_customers_trans
hdfs dfs -mkdir ${s3base}/us_customers_trans
hdfs dfs -mkdir ${s3base}/rtbf
hdfs dfs -mkdir ${s3base}/rtbf_trans

hdfs dfs -ls -R ${s3base}

hdfs dfs -put data/claims_provider_summary_data.csv ${s3base}/claim/
hdfs dfs -put data/claim-savings.csv                ${s3base}/cost_savings/
hdfs dfs -put data/tax_2009.csv                     ${s3base}/finance/tax_2009/
hdfs dfs -put data/tax_2010.csv                     ${s3base}/finance/tax_2010/
hdfs dfs -put data/tax_2015.csv                     ${s3base}/finance/tax_2015/
hdfs dfs -put data/eu_countries.csv                 ${s3base}/worldwidebank/eu_countries/
hdfs dfs -put data/us_customers_data.csv            ${s3base}/worldwidebank/us_customers/
hdfs dfs -put data/ww_customers_data.csv            ${s3base}/worldwidebank/ww_customers/
hdfs dfs -put data/consent_master_data_cleaned.csv	${s3base}/consent/
hdfs dfs -put data/eu_countries.csv	                ${s3base}/eu_countries/
hdfs dfs -put data/employees_raw.csv                ${s3base}/hr/employees_raw/
hdfs dfs -put data/employees.csv                    ${s3base}/hr/employees/

hdfs dfs -ls -h -R ${s3base}

#9. Create Hive tables
hdfs dfs -put /opt/cloudera/parcels/CDH-7*/lib/hive/lib/hive-exec.jar /user/${user}

sed -i.bak "s|__mybucket__|${s3bucket}|g" ./data/HiveSchema-cloud.hsql
sed -i.bak "s|__user__|${user}|g" ./data/HiveSchema-cloud.hsql

beeline -f ./data/HiveSchema-cloud.hsql

sed -i.bak "s|__mybucket__|${s3bucket}|g" ./data/TransSchema-cloud.hsql
beeline -f ./data/TransSchema-cloud.hsql

#optionally setup Airline demo dataset too
hdfs dfs -cp s3a://cldr-airline-demo/ ${s3bucket}
sed -i.bak "s|__mybucket__|${s3bucket}|g" ./data/AirlineSchema-cloud.hql
beeline -f ./data/AirlineSchema-cloud.hql

#10. associate tags with Hive entities
chmod +x ./09-associate-entities-with-tags-knox.sh
./09-associate-entities-with-tags-knox.sh

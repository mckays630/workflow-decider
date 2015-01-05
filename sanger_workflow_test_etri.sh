perl bin/sanger_workflow_decider.pl \
--seqware-clusters conf/cluster.json \
--bwa-workflow-version 2.6.0 \
--workflow-version 1.0.2 \
--working-dir etri \
--gnos-url  https://gtrepo-etri.annailabs.com \
--decider-config conf/decider.ini \
--use-cached-xml \
--local-status-cache local-status-cache.tsv  \
#--schedule-whitelist-donor donors_I_want.txt \
#--schedule-force-run \
#--schedule-whitelist-donor donors_I_want.txt \
#--seqware-clusters conf/cluster.json \

#https://gtrepo-etri.annailabs.com  \
#https://gtrepo-osdc-icgc.annailabs.com

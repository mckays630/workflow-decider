perl bin/sanger_workflow_decider.pl \
--schedule-force-run \
--seqware-clusters conf/empty.json \
--workflow-version 1.0.2 \
--bwa-workflow-version 2.6.0 \
--working-dir ebi \
--gnos-url  https://gtrepo-ebi.annailabs.com \
--decider-config conf/decider.ini \
--use-cached-xml \
#--schedule-whitelist-donor donors_I_want.txt \
#--seqware-clusters /home/ubuntu/state/instances.json \

#https://gtrepo-etri.annailabs.com  \
#https://gtrepo-osdc-icgc.annailabs.com

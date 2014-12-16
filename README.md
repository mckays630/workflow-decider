# BWA Decider

## About

This is the decider for the PanCancer Variant Calling workfow.


## Installing dependencies
A shell script named 'install' will install all of the dependencies.

$ sudo bash install

## Configuration
./conf/decider.ini contains the decoder parameters
./conf/ini contains templates for workflow setting and ini files

## White/Black lists
Place donor and sample-level white or black lists in the appropriate directory.
For example a white list of donor IDs is placed in the whitelist directory, then
specified as follows:

whitelist-donor=donors_I_want.txt

Other options:
blacklist-donor=
whitelist-sample=
blacklist-sample=

Each list is a text file with one donor or sample ID/line

## Testing
There is a shell script 'sanger_decider_test.sh' that will run the decider through its paces.

# To test on itri GNOS repo
bash sanger_workflow_test_itri.sh

# To test on osdc GNOS repo
bash sanger_workflow_test_osdc.sh

<pre>
Usage:
           sanger_workflow_decider.pl --decider-config<decider_path> [options]
           sanger_workflow_decider.pl --help
           sanger_workflow_decider.pl --version

Required:
    --decider-config[=][ ]<decider_path>
        The path to the file containing the default settings for the decider.
        If another option is chosen via command line option the command line
        setting will take precedence.

Options:
    --seqware-clusters[=][ ]<file>
        JSON file that describes the clusters available to schedule workflows
        to. As a reference there is a cluster.json file in the conf folder.

    --workflow-name[=][ ]<workflow_name>
        Specify the variant caller workflow name to be run (eq
        SangerPancancerCgpCnIndelSnvStr)

    --workflow-version[=][ ]<workflow_version>
        Specify the variant caller workflow version you would like to run (eg.
        1.0.1)

    --bwa-workflow-version[=][ ]<workflow_version>
        Specify the bwa workflow required to proceed to variant calling (eg
        2.6.0)

    --gnos-url[=][ ]<gnos_url>
        URL for a GNOS server, e.g. https://gtrepo-ebi.annailabs.com

    --gnos-upload-url[=][ ]<gnos_upload_url>
        URL for a GNOS server to upload (if different from --gnos-url)

    --working-dir[=][ ]<working_directory>
        A place for temporary ini and settings files

    --use-cached-analysis
        Use the previously downloaded list of files from GNOS that are marked
        in the live state (only useful for testing).

    --seqware-settings[=][ ]<seqware_settings>
        The template seqware settings file

    --report[=][ ]<report_file>
        The report file name that the results will be placed in by the decider

    --use-cached-xml
        A flag indicating that previously download xml files for each analysis
        file should not be downloaded again

    --tabix-url[=][ ]<tabix_url>
        The URL of the tabix server

    --pem-file[=][ ]<path_to_pem_file>
        Path to the Amazon EC2 key pair file

    --lwp-download-timeout[=][ ]<wait_time>
        This flag is used to specify the amount of time lwp download should
        wait for an xml file. If zero is specified it will skip lwp download
        and attempt other methods.

    --schedule-ignore-failed
        A flag indicating that previously failed runs for this specimen should
        be ignored and the specimen scheduled again

    --schedule-whitelist-sample[=][ ]<filename>
        This flag indicates the file that contains a list of sample ids to be
        analyzed. This file should be placed in the whitelist folder and
        should have one sample id per line.

    --schedule-whitelist-donor[=][ ]<filename>
        This flag indicates a file that contains a list of donor ids to be
        analyzed. This file should be placed in the whitelist folder and
        should have one donor id per line.

    --filter-downloads-by-whitelist
        This flag applies when a sample or donor whitelist is selected. If
        selected this option will block download of analysis results for
        non-whitelised donors or samples.

    --schedule-blacklist-sample[=][ ]<filename>
        This flag indicates samples that should not be run. The file should be
        placed in the blacklist folder and should have on sample id per line.

    --schedule-blacklist-donor[=][ ]<filename>
        This flag indicates donors that should not be run. The file should be
        placed in the blacklist folder and should have on donor id per line.

    --filter-downloads-by-blacklist
        This flag applies when a sample or donor blacklist is selected. If
        selected this option will block download of analysis results for
        blacklised donors or samples.

    --schedule-sample[=][ ]<aliquot_id>
        For only running one particular sample based on its uuid

    --schedule-donor[=][ ]<aliquot_id>
        For running one particular donor based on its uuid

    --schedule-ignore-lane-count
        Skip the check that the GNOS XML contains a count of lanes for this
        sample and the bams count matches

    --schedule-force-run
        Schedule workflows even if they were previously completed

    --cores-addressable[=][ ]<number of cores>
        The number of cores that can be used for the analysis

    --workflow-skip-scheduling
        Indicates no workflow should be scheduled, just summary of what would
        have been run.

    --workflow-upload-results
        A flag indicating the resulting VCF files and metadata should be
        uploaded to GNOS, default is to not upload!!!

    --workflow-skip-gtdownload
        A flag indicating that input files should be just the bam input paths
        and not from GNOS

    --workflow-skip-gtupload
        A flag indicating that upload should not take place but output files
        should be placed in output_prefix/output_dir

    --workflow-output-prefix[=][ ]<output_prefix>
        If --skip-gtupload is set, use this to specify the prefix of where
        output files are written

    --workflow-output-dir[=][ ]<output_directory>
        if --skip-gtupload is set, use this to specify the dir of where output
        files are written

    --workflow-input-prefix[=][ ]<prefix>
        if --skip-gtdownload is set, this is the input bam file prefix
</pre>


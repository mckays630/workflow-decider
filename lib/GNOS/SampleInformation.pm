package GNOS::SampleInformation;

use common::sense;

use IPC::System::Simple;
use autodie qw(:all);

use FindBin qw($Bin);

use Carp::Always;
use File::Slurp;

use XML::LibXML;
use XML::LibXML::Simple qw(XMLin);

use Data::Dumper;


sub new {
    my $class = shift;
    my $self = bless {}, $class;
    return $self;
}

sub filter_by_blacklist {
    my $self =  shift;
    my $filter = shift;
    $self->{_filter_by_blacklist} = 1 if $filter;
    return $self->{_filter_by_blacklist};
}

sub filter_by_whitelist{
    my $self =  shift;
    my $filter = shift;
    $self->{_filter_by_whitelist} = 1 if $filter;
    return $self->{_filter_by_whitelist};
}

sub get {
    my ($self, $working_dir, $gnos_url, $use_cached_xml, $whitelist, $blacklist) = @_;

    system "mkdir -p $working_dir";
    open my $parse_log, '>', "$Bin/../$working_dir/xml_parse.log";

    my $participants = {};

    my $cmd = "mkdir -p $working_dir/xml; cgquery -s $gnos_url -o $Bin/../$working_dir/xml/data.xml";
    $cmd .= ($gnos_url =~ /cghub.ucsc.edu/)? " 'study=PAWG&state=live'":" 'study=*&state=live'";

    say $parse_log "cgquery command: $cmd";

    system($cmd);

    my $xs = XML::LibXML::Simple->new(forcearray => 0, keyattr => 0 );
    my $data = $xs->XMLin("$Bin/../$working_dir/xml/data.xml");

    my $results = $data->{Result};

    say $parse_log '';

    my @donor_whitelist;
    if ($whitelist) {
	@donor_whitelist = @{$whitelist->{donor}};
	for (@donor_whitelist) {
	    s/^\S+\s+//;
	}
	say STDERR "Downloading only donor whitelist analysis results" if @donor_whitelist > 0;
    }
    my @donor_blacklist;
    if ($blacklist) {
	@donor_blacklist = @{$blacklist->{donor}};
	for (@donor_blacklist) {
	    s/^\S+\s+//;
	}
	say STDERR "Downloading only donor blacklist analysis results" if @donor_blacklist > 0;
    }
    my @sample_whitelist;
    if ($whitelist) {
        @sample_whitelist = grep {/^\S+$/} @{$whitelist->{sample}};
        say STDERR "Downloading only sample whitelist analysis results" if @sample_whitelist > 0;
    }
    my @sample_blacklist;
    if ($blacklist) {
        @sample_blacklist = grep{/^\S+$/} @{$blacklist->{sample}};
        say STDERR "Downloading only sample blacklist analysis results" if @sample_blacklist > 0;
    }

    # Save info about variant workflows external to the analysis list
    my $variant_workflow = {};

    my $i = 0;

    foreach my $result_id (keys %{$results}) {
        my $result = $results->{$result_id};
        my $analysis_full_url = $result->{analysis_full_uri};
	my $participant_id = $result->{participant_id};

        my $analysis_id = $i;
        if ( $analysis_full_url =~ /^(.*)\/([^\/]+)$/ ) {
            $analysis_full_url = $1."/".lc $2;
            $analysis_id = lc $2;
        }
        else {
            say $parse_log "SKIPPING: no analysis url";
            next;
        }

	# If requested, only download XML for whitelisted samples/donors
	# or block download of XML for blacklisted samples/donors
	if (@donor_whitelist && $self->filter_by_whitelist()) {
            next unless grep {$participant_id eq $_} @donor_whitelist;
	    say STDERR "Donor $participant_id is whitelisted";
        }
	if (@donor_blacklist && $self->filter_by_blacklist()) {
            say STDERR "Donor $participant_id is blacklisted"
                and next if grep {$participant_id eq $_} @sample_blacklist;
        }
        if (@sample_whitelist && $self->filter_by_whitelist()) {
            next unless grep {$analysis_id eq $_} @sample_whitelist;
	    say STDERR "Analysis $analysis_id is whitelisted";
        }
	if (@sample_blacklist && $self->filter_by_blacklist()) {
            say STDERR "Analysis $analysis_id is blacklisted" 
		and next if grep {$analysis_id eq $_} @sample_blacklist;
        }

        say $parse_log "\n\nANALYSIS\n";
        say $parse_log "\tANALYSIS FULL URL: $analysis_full_url $analysis_id";
        my $analysis_xml_path =  "$Bin/../$working_dir/xml/data_$analysis_id.xml";
        
        my $status = 0;
        my $attempts = 0;

        while ($status == 0 and $attempts < 10) {
            $status = $self->download_analysis($analysis_full_url, $analysis_xml_path, $use_cached_xml);
            $attempts++;
        }         

        if (not -e $analysis_xml_path or not eval {$xs->XMLin($analysis_xml_path); } ) {
           say $parse_log "skipping $analysis_id - no xml file available: $analysis_xml_path";
           die;
        } 

        my $analysis_data = $xs->XMLin($analysis_xml_path);

        if (ref($analysis_data) ne 'HASH'){
            say "XML can not be converted to a hash for $analysis_id";
            die;
        }

        my %analysis = %{$analysis_data};
        
        my $analysis_result = $analysis{Result};
        if (ref($analysis_result) ne 'HASH') {
             say $parse_log "XML does not contain Results - not including:$analysis_id";
             next;
        }

        my %analysis_result = %{$analysis_result};      
        my $upload_date = $analysis_result{upload_date};
        my $analysis_xml_path =  "$working_dir/xml/data_$analysis_id.xml";
        my $center_name = $analysis_result{center_name};
        my $analysis_data_uri = $analysis_result{analysis_data_uri};
        my $submitter_aliquot_id = $analysis_result{submitter_aliquot_id};
        my $aliquot_id = $analysis_result{aliquot_id};

        my $participant_id = $analysis_result{participant_id};
        if (ref($participant_id) eq 'HASH') {
            $participant_id = undef;
        }

	my $use_control = $analysis_result{use_cntl};

        my $alignment = $analysis_result{refassem_short_name};
        my $sample_id = $analysis_result{sample_id};

        if (ref($sample_id) eq 'HASH') {
           $sample_id = undef;
        }
        my ($analysis_attributes,$sample_uuid);
        if (ref($analysis_result{analysis_xml}{ANALYSIS_SET}) eq 'HASH'
           and ref($analysis_result{analysis_xml}{ANALYSIS_SET}{ANALYSIS}) eq 'HASH') {
            if (ref($analysis_result{analysis_xml}{ANALYSIS_SET}{ANALYSIS}{ANALYSIS_ATTRIBUTES}) eq 'HASH') {
                $analysis_attributes = $analysis_result{analysis_xml}{ANALYSIS_SET}{ANALYSIS}{ANALYSIS_ATTRIBUTES}{ANALYSIS_ATTRIBUTE};                
            }
            elsif ( ref($analysis_result{analysis_xml}{ANALYSIS_SET}{ANALYSIS}{TARGETS}{TARGETS_ATTRIBUTES}) eq 'HASH'
                 and ref($analysis_result{analysis_xml}{ANALYSIS_SET}{ANALYSIS}{TARGETS}{TARGET}) eq 'HASH') {
                 $sample_uuid = $analysis_result{analysis_xml}{ANALYSIS_SET}{ANALYSIS}{TARGETS}{TARGET}{refname};
            }
        }

        my (%attributes, $total_lanes, $aliquot_uuid, $submitter_participant_id, $submitter_donor_id, $workflow_version, 
            $submitter_sample_id, $bwa_workflow_version, $submitter_specimen_id, $bwa_workflow_name, $dcc_project_code,
	    $vc_workflow_version, $vc_workflow_name, $workflow_name);
        if (ref($analysis_attributes) eq 'ARRAY') {
            foreach my $attribute (@$analysis_attributes) {
                $attributes{$attribute->{TAG}} = $attribute->{VALUE};
            }

            $total_lanes = $attributes{total_lanes};
            $aliquot_uuid = $attributes{aliquot_id};

            $dcc_project_code = $attributes{dcc_project_code};
            $dcc_project_code = undef if (ref($dcc_project_code) eq 'HASH');

            $submitter_participant_id = $attributes{submitter_participant_id};
            $submitter_participant_id = undef if (ref($submitter_participant_id) eq 'HASH');

            $submitter_donor_id = $attributes{submitter_donor_id};
            $submitter_donor_id = undef if (ref($submitter_donor_id) eq 'HASH');

            $submitter_sample_id = $attributes{submitter_sample_id};
            $submitter_sample_id = undef if (ref($submitter_sample_id) eq 'HASH');

            $submitter_specimen_id = $attributes{submitter_specimen_id};
            $submitter_specimen_id = undef if (ref($submitter_specimen_id) eq 'HASH');
            $bwa_workflow_version = $attributes{workflow_version} || $attributes{alignmant_workflow_version};
            $bwa_workflow_name = $attributes{workflow_name} || $attributes{alignmant_workflow_name};

	    $vc_workflow_name    = $attributes{variant_workflow_name};
	    $vc_workflow_version = $attributes{variant_workflow_version};

	    # XML inconsistent across sites?
	    $use_control ||= $attributes{use_cntl};
        }

	$workflow_name = $vc_workflow_name || $bwa_workflow_name;
	$workflow_version = $vc_workflow_version || $bwa_workflow_version;


        my $donor_id =  $participant_id || $submitter_donor_id;

	# make sure the donor ID is unique for white/blacklist purposes;
	my $donor_id = join('-',$dcc_project_code,$donor_id);
        
        say $parse_log "\tDONOR:\t$donor_id";
        say $parse_log "\tANALYSIS:\t$analysis_data_uri";
        say $parse_log "\tANALYSIS ID:\t$analysis_id";
        say $parse_log "\tPARTICIPANT ID:\t$participant_id";
        say $parse_log "\tSAMPLE ID:\t$sample_id";
        say $parse_log "\tALIQUOT ID:\t$aliquot_id";
        say $parse_log "\tSUBMITTER PARTICIPANT ID:\t$submitter_participant_id";
        say $parse_log "\tSUBMITTER DONOR ID:\t$submitter_donor_id";
        say $parse_log "\tSUBMITTER SAMPLE ID:\t$submitter_sample_id";
        say $parse_log "\tSUBMITTER ALIQUOT ID:\t$submitter_aliquot_id";
        say $parse_log "\tWORKFLOW NAME:\t$workflow_name";
	say $parse_log "\tWORKFLOW VERSION:\t$workflow_version";
	
	# We don't need to save the analysis for variant calls, just
	# to record that it has been run.
	if ($vc_workflow_name && $vc_workflow_version) {
	    # just record the newer one if an earlier vertsion exists
	    if ( my $version = $variant_workflow->{$donor_id}->{$vc_workflow_name} ) {
		my @version1 = split '.', $version;
		my @version2 = split ',', $vc_workflow_version;
		next if $version1[0] >= $version2[0];
		next if $version1[1] >= $version2[1];
		next if $version1[2] >= $version2[2];
	    }

	    $variant_workflow->{$donor_id}->{$vc_workflow_name} = $vc_workflow_version;
	    next;
	}

        # We don't need to save the analysis if there is no workflow name or version
	unless ($workflow_name && $workflow_version) {
	    say $parse_log "\tNO WORKFLOW INFORMATION; analysis skipped";
	    next;
	}

	my ($library_name, $library_strategy, $library_source);
        my $library_descriptor;
        if (exists ($analysis_result{experiment_xml})) {

             if (ref($analysis_result{experiment_xml}{EXPERIMENT_SET}{EXPERIMENT}) eq 'HASH') {
                 $library_descriptor = $analysis_result{experiment_xml}{EXPERIMENT_SET}{EXPERIMENT}{DESIGN}{LIBRARY_DESCRIPTOR};
             }
             else {
                 $library_descriptor = $analysis_result{experiment_xml}{EXPERIMENT_SET}{EXPERIMENT}[0]{DESIGN}{LIBRARY_DESCRIPTOR};
             }
        }         
        my %library = (ref($library_descriptor) == 'HASH')? %{$library_descriptor} : ();
        my $library_name = $library{LIBRARY_NAME};
        my $library_strategy = $library{LIBRARY_STRATEGY};
        my $library_source = $library{LIBRARY_SOURCE};

        say $parse_log "\tLibrary\n\t\tName:\t$library_name\n\t\tLibrary Strategy:\t$library_strategy\n\t\tLibrary Source:\t$library_source";

        if (not $library_name or not $library_strategy or not $library_source or not $analysis_id or not $analysis_data_uri) {
            say $parse_log "\tERROR: one or more critical fields not defined, will skip $analysis_id\n";
            next;
        }

        say $parse_log "\tgtdownload -c gnostest.pem -v -d $analysis_data_uri\n";

        #This takes into consideration the files that were submitted with the old SOP
        if ((defined $submitter_donor_id) and (defined $submitter_donor_id ne '')) {
            $submitter_sample_id = $submitter_specimen_id;
        }
        $submitter_participant_id = (defined $submitter_donor_id) ? $submitter_donor_id : $submitter_participant_id;
        #$aliquot_id = (defined $submitter_sample_id) ? $submitter_sample_id : $aliquot_id;           
        #$submitter_aliquot_id = (defined $submitter_sample_id)? $submitter_sample_id: $submitter_aliquot_id;
	
        $sample_id = (defined $submitter_specimen_id) ? $submitter_specimen_id: $sample_id;
        $center_name //= 'unknown';

        my $library = {
	    analysis_ids             => $analysis_id,
	    analysis_url             => $analysis_data_uri,
	    library_name             => $library_name,
	    library_strategy         => $library_strategy,
	    library_source           => $library_source,
	    alignment_genome         => $alignment,
	    use_control              => $use_control,
	    total_lanes              => $total_lanes,
	    submitter_participant_id => $submitter_participant_id,
	    sample_id                => $sample_id,
	    submitter_sample_id      => $submitter_sample_id,
	    submitter_aliquot_id     => $submitter_aliquot_id,
	    sample_uuid              => $sample_uuid,
	    bwa_workflow_version     => $bwa_workflow_version
	};

        $center_name = 'seqware';
        if ($alignment ne 'unaligned') { 
            $alignment = "$alignment - $analysis_id - $bwa_workflow_name - $bwa_workflow_version - $upload_date";
        }


	foreach my $attribute (keys %{$library}) {
            my $library_value = $library->{$attribute};
            $participants->{$center_name}{$donor_id}{$sample_id}{$alignment}{$aliquot_id}{$library_name}{$attribute}{$library_value} = 1;
        }

        my $files = files($analysis_result, $parse_log, $analysis_id);
        foreach my $file_name (keys %$files) {
            my $file_info = $files->{$file_name};
            $participants->{$center_name}{$donor_id}{$sample_id}{$alignment}{$aliquot_id}{$library_name}{files}{$file_name} = $file_info;
        }

	# Save VC workflow data without mangling
	$participants->{$center_name}->{$donor_id}->{variant_workflow} = $variant_workflow;


    }
    close $parse_log;

    return $participants;
   
}

sub files {
    my ($results, $parse_log, $analysis_id) = @_;

    say $parse_log "FILES";

    my $files = $results->{files}{file};
    $files = [ $files ] if ref($files) ne 'ARRAY';

    my %files;
    foreach my $file (@{$files}) {
        my $file_name  = $file->{filename};
        
        next if (not $file_name =~ /\.bam$/);

        $files{$file_name}{size} =  $file->{filesize};
        $files{$file_name}{checksum} = $file->{checksum};
        $files{$file_name}{local_path} = $file_name;

        say $parse_log "\tFILE: $file_name SIZE: ".$files{$file_name}{size}." CHECKSUM: ".$files{$file_name}{checksum}{content};
        say $parse_log "\tLOCAL FILE PATH: $analysis_id/$file_name";

    }

    return \%files;
}

sub download_analysis {
    my ($self, $url, $out, $use_cached_xml) = @_;

    my $xs = XML::LibXML::Simple->new(forcearray => 0, keyattr => 0 );

    if (-e $out and eval {$xs->XMLin($out)} and $use_cached_xml) {
	return 1;
    }

    say STDERR "Downloading $out...";

    chomp(my $xml = `basename $out`);

    my $response = system("wget -q -O $out $url");
    if ($response != 0) {
	say STDERR "wget failed; falling back to lwp-download...";
	$response = system("lwp-download $url $out");
	return 0 if ($response != 0 );
    }

    if (-e $out and eval { $xs->XMLin($out) }) {
         return 1;
    }

    return 0;
}

1;

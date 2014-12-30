package SeqWare::Cluster;

use common::sense;

use FindBin qw($Bin);
use lib "$Bin/../lib";

use IPC::System::Simple;
use autodie qw(:all);
use Carp::Always;

use File::Slurp;

use XML::DOM;
use JSON;
use XML::LibXML;
use XML::Simple;
use Config::Simple;

use Data::Dumper;

sub combine_local_data {
  my ($self, $running_sample_ids, $failed_samples, $completed_samples, $local_cache_file) = @_;
  #print Dumper $running_sample_ids;
  # $samples_status->{$run_status}{$mergedSortedIds}{$created_timestamp}{$sample_id} = $run_status;
  # read it if it exists and add to structure
  if (-e $local_cache_file && -s $local_cache_file > 0) {
    open IN, "<$local_cache_file" or die "Can't open file $local_cache_file for reading";
    while(<IN>) {
      chomp;
      my @a = split /\t/;
      if ($a[3] eq 'running') {
        #$running_sample_ids->{$a[0]}{$a[1]}{$a[2]} = $a[3];
        # never cache the running, always rediscover in case a running box was terminated, want to restart
      } elsif ($a[3] eq 'completed') {
        $completed_samples->{$a[0]}{$a[1]}{$a[2]} = $a[3];
      } elsif ($a[3] eq 'failed') {
        $failed_samples->{$a[0]}{$a[1]}{$a[2]} = $a[3];
      } else {
        # just add to failed if don't know
        $failed_samples->{$a[0]}{$a[1]}{$a[2]} = $a[3];
      }
    }
    close IN;
  }
  # now save these back out, running is always a fresh list of what's really running
  open OUT, ">$local_cache_file" or die "Can't open file $local_cache_file for output";
  foreach my $hash ($running_sample_ids, $failed_samples, $completed_samples) {
    foreach my $mergedSortedIds (keys %{$hash}) {
      foreach my $created_timestamp (keys %{$hash->{$mergedSortedIds}}) {
        foreach my $sample_id (keys %{$hash->{$mergedSortedIds}{$created_timestamp}}) {
          print OUT "$mergedSortedIds\t$created_timestamp\t$sample_id\t".$hash->{$mergedSortedIds}{$created_timestamp}{$sample_id}."\n";
        }
      }
    }
  }
  close OUT;
  # return the structures
  return($running_sample_ids, $failed_samples, $completed_samples);
}

sub cluster_seqware_information {
    my ($class, $report_file, $clusters_json, $ignore_failed, $run_workflow_version, $failure_reports_dir) = @_;

    my ($clusters, $cluster_file_path);
    foreach my $cluster_json (@{$clusters_json}) {
        $cluster_file_path = "$Bin/../$cluster_json";
        die "file does not exist $cluster_file_path" unless (-f $cluster_file_path);
        my $cluster = decode_json( read_file($cluster_file_path));
         $clusters = {%$clusters, %$cluster};
    }

    my (%cluster_information,
       %running_samples,
       %failed_samples,
       %completed_samples,
       $cluster_info,
       $samples_status_ids);
    foreach my $cluster_name (keys %{$clusters}) {
        my $cluster_metadata = $clusters->{$cluster_name};
        #print Dumper($cluster_metadata);
        ($cluster_info, $samples_status_ids)
            = seqware_information( $report_file,
                                   $cluster_name,
                                   $cluster_metadata,
                                   $run_workflow_version,
                                   $failure_reports_dir);

        # LEFT OFF HERE: need to pass back the structure for failed workflows, parse it, and write out a report for it

        foreach my $cluster (keys %{$cluster_info}) {
           $cluster_information{$cluster} = $cluster_info->{$cluster};
        }

        foreach my $sample_id (keys %{$samples_status_ids->{running}}) {
          #$running_samples{$sample_id} = 1;
          $running_samples{$sample_id} = $samples_status_ids->{running}{$sample_id};
        }

        foreach my $sample_id (keys %{$samples_status_ids->{failed}}) {
             $failed_samples{$sample_id} = $samples_status_ids->{failed}{$sample_id};
        }

        foreach my $sample_id (keys %{$samples_status_ids->{completed}}) {
             $completed_samples{$sample_id} = $samples_status_ids->{completed}->{$sample_id};
        }

    }

    return (\%cluster_information, \%running_samples, \%failed_samples, \%completed_samples);
}

sub seqware_information {
    my ($report_file, $cluster_name, $cluster_metadata, $run_workflow_version, $failure_reports_dir) = @_;

    my $user = $cluster_metadata->{username};
    my $password = $cluster_metadata->{password};
    my $web = $cluster_metadata->{webservice};
    my $workflow_accession = $cluster_metadata->{workflow_accession};
    my $max_running = $cluster_metadata->{max_workflows};
    my $max_scheduled_workflows = $cluster_metadata->{max_scheduled_workflows};

    $max_running = 0 if ($max_running eq "");

    $max_scheduled_workflows = $max_running
          if ( $max_scheduled_workflows eq "" || $max_scheduled_workflows > $max_running);

    say $report_file "EXAMINING CLUSER: $cluster_name";

    my $workflow_information_xml = `wget --timeout=60 -t 2 -O - --http-user='$user' --http-password=$password -q $web/workflows/$workflow_accession`;

    if ($workflow_information_xml eq '' ) {
       say "could not connect to cluster: $web";
       return;
    }

    my $xs = XML::Simple->new(ForceArray => 1, KeyAttr => 1);
    my $workflow_information = $xs->XMLin($workflow_information_xml);

    my $samples_status;
    if ($workflow_information->{name}) {
        my $workflow_runs_xml = `wget -O - --http-user='$user' --http-password=$password -q $web/workflows/$workflow_accession/runs`;
        my $seqware_runs_list = $xs->XMLin($workflow_runs_xml);
        my $seqware_runs = $seqware_runs_list->{list};

        construct_failure_reports($seqware_runs, $failure_reports_dir);
        #print Dumper($seqware_runs);

        $samples_status = find_available_clusters($report_file, $seqware_runs,
                   $workflow_accession, $samples_status, $run_workflow_version);
    }
    my $running = scalar(keys %{$samples_status->{running}});
    my %cluster_info;
    if ($running < $max_running ) {
        say $report_file  "\tTHERE ARE $running RUNNING WORKFLOWS WHICH IS LESS THAN MAX OF $max_running, ADDING TO LIST OF AVAILABLE CLUSTERS";
        for (my $i=0; $i<$max_scheduled_workflows; $i++) {
            my %cluster_metadata = %{$cluster_metadata};
            $cluster_info{"$cluster_name-$i"} = \%cluster_metadata
                if ($run_workflow_version eq $cluster_metadata{workflow_version});
        }
    }
    else {
        say $report_file "\tCLUSTER HAS RUNNING WORKFLOWS, NOT ADDING TO AVAILABLE CLUSTERS";
    }

    return (\%cluster_info, $samples_status);
}

sub construct_failure_reports {
  my ($info, $failure_reports_dir) = @_;
  if ($failure_reports_dir ne "") {
    system("mkdir -p $failure_reports_dir");
    foreach my $entry (@{$info}) {
      if ($entry->{status}[0] eq 'failed') {
        my $cwd = $entry->{currentWorkingDir}[0];
        $cwd =~ /\/(oozie-[^\/]+)$/;
        my $uniq_name = $1;
        print "CWD: $uniq_name\n";
        system("mkdir -p $failure_reports_dir/$uniq_name");
        open OUT, ">$failure_reports_dir/$uniq_name/summary.tsv" or die;
        foreach my $key (keys %{$entry}) {
          next if ($key eq "iniFile" or $key eq "stdErr" or $key eq "stdOut");
          print OUT "$key\t".$entry->{$key}[0]."\n";
        }
        close OUT;
        open OUT, ">$failure_reports_dir/$uniq_name/stderr.txt" or die;
        print OUT $entry->{'stdErr'}[0];
        close OUT;
        open OUT, ">$failure_reports_dir/$uniq_name/stdout.txt" or die;
        print OUT $entry->{'stdOut'}[0];
        close OUT;
        open OUT, ">$failure_reports_dir/$uniq_name/workflow.ini" or die;
        print OUT $entry->{'iniFile'}[0];
        close OUT;
      }
    }
  }
}

sub find_available_clusters {
    my ($report_file, $seqware_runs, $workflow_accession, $samples_status) = @_;

    say $report_file "\tWORKFLOWS ON THIS CLUSTER";
    foreach my $seqware_run (@{$seqware_runs}) {
        my $run_status = $seqware_run->{status}->[0];

        say $report_file "\t\tWORKFLOW: ".$workflow_accession." STATUS: ".$run_status;

        my ($sample_id, $created_timestamp, $mergedSortedIds);

        if ( ($sample_id, $created_timestamp, $mergedSortedIds) = get_sample_info($report_file, $seqware_run))    {

            my $running_status = { 'pending' => 1,   'running' => 1,
                                   'scheduled' => 1, 'submitted' => 1 };
            $running_status = 'running' if ($running_status->{$run_status});
            $samples_status->{$run_status}{$mergedSortedIds}{$created_timestamp}{$sample_id} = $run_status;
            #$samples_status->{$run_status}{$mergedSortedIds}{$created_timestamp} = 1;
            #$samples_status->{$run_status}{$sample_id}{$created_timestamp} = 1;
        }
     }


     return $samples_status;
}

sub  get_sample_info {
    my ($report_file, $seqware_run) = @_;

    my @ini_file =  split "\n", $seqware_run->{iniFile}[0];

    my $created_timestamp = $seqware_run->{createTimestamp}[0];
    my %parameters;
    foreach my $line (@ini_file) {
         my ($parameter, $value) = split '=', $line, 2;
         $parameters{$parameter} = $value;
    }

    my $sample_id = $parameters{sample_id};


    my @urls = split /,/, $parameters{gnos_input_metadata_urls};
    say $report_file "\t\t\tSAMPLE: $sample_id";
    my $sorted_urls = join(',', sort @urls);
    say $report_file "\t\t\tINPUTS: $sorted_urls";

    say $report_file "\t\t\tCWD: ".$parameters{currentWorkingDir};
    say $report_file "\t\t\tWORKFLOW ACCESSION: ".$parameters{swAccession}."\n";

    $sample_id //= $sorted_urls;

    # for the variant calling workflow
    my @mergedIds = (split (/,/, $parameters{tumourAnalysisIds}), split (/,/, $parameters{controlAnalysisId}));
    my @sortedMergedIds = sort @mergedIds;
    say $report_file "\t\t\tMERGED_SORTED_IDS: ".join(",", @sortedMergedIds)."\n";

    return ($sample_id, $created_timestamp, join(",", @sortedMergedIds));
}


1;

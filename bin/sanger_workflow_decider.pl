#!/usr/bin/env perl

use common::sense;
use utf8;

use IPC::System::Simple;
use autodie qw(:all);

use FindBin qw($Bin);
use lib "$Bin/../lib";

use Getopt::Euclid;

use Config::Simple;

use SeqWare::Cluster;
use SeqWare::Schedule::Sanger;
use GNOS::SampleInformation;

use Decider::Database;
use Decider::Config;

use Data::Dumper;

# add information from config file into %ARGV parameters.
my %ARGV = %{Decider::Config->get(\%ARGV)};

open my $report_file, '>', "$Bin/../".$ARGV{'--report'};

say 'Removing cached ini and settings samples';
`rm $Bin/../$ARGV{'--working-dir'}/samples/ -rf`;

my $whitelist = {};
my $blacklist = {};
get_list($ARGV{'--schedule-whitelist-sample'}, 'white', 'sample', $whitelist);
get_list($ARGV{'--schedule-whitelist-donor'},  'white', 'donor',  $whitelist);
get_list($ARGV{'--schedule-blacklist-sample'}, 'black', 'sample', $blacklist);
get_list($ARGV{'--schedule-blacklist-donor'},  'black', 'donor',  $blacklist);

say 'Getting SeqWare Cluster Information';
my ($cluster_information, $running_sample_ids, $failed_samples, $completed_samples)
          = SeqWare::Cluster->cluster_seqware_information( $report_file,
                                                  $ARGV{'--seqware-clusters'},
                                                  $ARGV{'--schedule-ignore-failed'},
                                                  $ARGV{'--workflow-version'});

#my $failed_db = Decider::Database->failed_connect();

print Dumper($cluster_information);
print Dumper($running_sample_ids);
print Dumper($failed_samples);
print Dumper($completed_samples);

if (defined($ARGV{'--local-status-cache'})) {
  say 'Combining Previous Results with Local Cache File';
  ($running_sample_ids, $failed_samples, $completed_samples) = SeqWare::Cluster->combine_local_data($running_sample_ids, $failed_samples, $completed_samples, $ARGV{'--local-status-cache'});
}

die;

say 'Reading in GNOS Sample Information';
my $gnos_info = GNOS::SampleInformation->new();
if ($ARGV{'--filter-downloads-by-whitelist'}) {
    $gnos_info->filter_by_whitelist(1);
}
if ($ARGV{'--filter-downloads-by-blacklist'}) {
    $gnos_info->filter_by_blacklist(1);
}
my $sample_information = $gnos_info->get( $ARGV{'--working-dir'},
					  $ARGV{'--gnos-url'},
					  $ARGV{'--use-cached-xml'},
					  $whitelist,
					  $blacklist);


say 'Scheduling Samples';
my $scheduler = SeqWare::Schedule::Sanger->new();
my %args = %ARGV;
strip_keys(\%args);

$args{report_file}         = $report_file;
$args{sample_information}  = $sample_information;
$args{cluster_information} = $cluster_information;
$args{running_sample_ids}  = $running_sample_ids;
$args{failed_sample_ids}  = $failed_samples;
$args{completed_sample_ids}  = $completed_samples;
# TODO: need to pass in failed and other IDs too
$args{whitelist}           = $whitelist;
$args{blacklist}           = $blacklist;

$scheduler->schedule_samples(%args);

close $report_file;

say 'Finished!!';

# Grab contents of white/black list file

sub strip_keys {
    my $hash = shift;
    my @keys = keys %$hash;
    for my $key (@keys) {
	my $val = $hash->{$key};
	delete $hash->{$key};
	$key =~ s/^--//;
	$hash->{$key} = $val;
    }
}


sub get_list {
    my $path  = shift or return;
    my $color = shift;
    my $type  = shift;
    my $list  = shift;

    my $file = "$Bin/../${color}list/$path";
    die "${color}list does not exist: $file" if (not -e $file);

    open my $list_file, '<', $file;

    my @list_raw = <$list_file>;
    my @list = grep /\S+/, @list_raw;
    chomp @list;

    # If this is a donor whitelist, check the format
    my $format_OK = grep {/^\S+\s+\S+$/} @list;

    if ($color =~ /white|black/ && $type eq 'donor' && (!$format_OK || $format_OK != @list)) {
	warn "$type $color";
	die "Error: Donor ${color}list requires two columns (study_name,participant_id)\n";
    }

    close $list_file;

    $list->{$type} = \@list;
}

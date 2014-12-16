package GlobalGNOS::Search;

use strict;
use warnings;

use autodie;
use Carp::Always;

use feature qw(say);

use Search::Elasticsearch;
use JSON;

use Data::Dumper;

sub new {
    my ($class, $elastic_search_url) = @_;
    my $self = {
                 elastic_search_url => $elastic_search_url
               };
    return bless $self, $class
}


sub get_donors_completed_alignment {
    my ($self) = @_;

    my $e = Search::Elasticsearch->new( nodes =>  $self->{elastic_search_url} );
    my $results = $e->search({
        body => {
            query => {
                        "bool" => {
                           "must"=> [
                                 {                         
                                    "terms" => {
                                       "is_alignment_completed" => ["T"]
                                        }
                                 },
                            ]
                        }
            }
        },
        from => 0,
        size => 20
    });

    my @donor_sources = $results->{hits}{hits};

    my %donors;
    foreach my $donor_source (@donor_sources) {
        foreach my $donor (@{$donor_source}) {
            $donors{$donor->{_id}} = $donor->{_source} if ($donor->{_type} eq 'donor');
        }
    }
    
    my $donors = $self->group_donors_by_gnos_repo(\%donors);

    return $donors;
}

sub group_donors_by_gnos_repo {
    my ($self, $donors) = @_;

    my %grouped_donors;
    foreach my $donor_id (keys %{$donors}) {
          my $donor_info = $donors->{$donor_id};
          print Dumper $donor_info->{gnos_repos_with_complete_alignment_set}->[0];
          print Dumper keys %{$donor_info};
die;
        $grouped_donors{gnos_repo}{$donor_id} = $donor_info;
    }

    return \%grouped_donors;
}


sub find_aligned_bams {
    my ($self, $vcf_workflow_name, $vcf_workflow_version, 
               $bwa_workflow_name, $bwa_workflow_version) = @_;

    my $donors = get_donors_completed_alignment($self);

    $bwa_workflow_name //= 'Workflow_Bundle_BWA';
    $bwa_workflow_version //= '2.6.0';
  
    my (%aligned_bams, $donor_info);
    foreach my $donor_id (keys %{$donors}) {
        say "Donor: $donor_id";
        $donor_info = $donors->{$donor_id};

        # check to see if a VCF was already created with workflow
        my $vcf_files = $donor_info->{vcf_files};
        foreach my $vcf (@{$vcf_files}) {
            # this is not  complete: need to figure out how to actualy determine the 
            # workflow_name / version and actually determine where the vcfs are
            my $workflow_name = $vcf->{workflow_name};
            my $workflow_version = $vcf->{workflow_version};
            if (($workflow_name eq $vcf_workflow_name) 
                                  and ($workflow_version ge $vcf_workflow_version)) {
                     say 'Already Aligned';
                     last;
            }
        }

        # if not aligned check to see if there is something to align for donor
        my $bam_files = $donor_info->{bam_files};
        foreach my $bam (@{$bam_files}) {
            if ($bam->{bam_type} eq 'Specimen level aligned BAM')  {
                my $alignment = $bam->{alignment};
                my $workflow_name = $alignment->{workflow_name};
                my $workflow_version = $alignment->{workflow_version};
                if (($workflow_name eq $bwa_workflow_name) 
                                   and ($workflow_version ge $bwa_workflow_version)) {
                     $aligned_bams{$donor_id} = $bam;
                }
            }
        }

    }

    return \%aligned_bams;
}

1;

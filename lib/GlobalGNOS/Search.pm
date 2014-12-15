package GlobalGNOS::Search;

use strict;
use warnings;

use autodie;
use Carp::Always;

use feature qw(say);

use Search::Elasticsearch;
use JSON;

use Data::Dumper;

sub get_donor_aligned {
    my ($self, $elasticsearch_url) = @_;

    my $e = Search::Elasticsearch->new( nodes =>  $elasticsearch_url );
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
        size => 20000000
    });

    my @donor_sources = $results->{hits}{hits};

    my %donors;
    foreach my $donor_source (@donor_sources) {
        foreach my $donor (@{$donor_source}) {
            $donors{$donor->{_id}} = $donor->{_source} if ($donor->{_type} eq 'donor');
        }
    }
    
    return \%donors;
}

sub find_aligned_bams {
    my ($self, $elasticsearch_url) = @_;

    my $donor_data = get_donors_complted_alignment($elasticsearch_url);

    my $BWA_workflow_name = 'Workflow_Bundle_BWA';
    my $BWA_workflow_version = '2.6.0';
  
    my (@aligned_bams, $donor_info);
    foreach my $donor (%{$donor_data}) {
        $donor_info = $donor_data->{$donor};
        my $bam_files = $donor_info->{bam_files};
        foreach my $bam (@{$bam_files}) {
            if ($bam->{bam_type} eq 'Specimen level aligned BAM')  {
                my $alignment = $bam->{alignment};
                my $workflow_name = $alignment->{workflow_name};
                my $workflow_version = $alignment->{workflow_version};
                if (($workflow_name eq $BWA_workflow_name) and ($workflow_version ge $BWA_workflow_version)) {
                     push @aligned_bams, $bam;
                }
            }
        }
    }

    return \@aligned_bams;
}

1;

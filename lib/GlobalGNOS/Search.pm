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
    my ($class, $elasticsearch_url) = @_;
    my $self = {
                 elasticsearch_url => $elasticsearch_url,
                 query_size => 100,
                                 
               };
    return bless $self, $class;
}


sub get_donors_completed_alignment {
    my ($self, $filter_donors, $gnos_repo) = @_;



    my $query = (defined $gnos_repo)? 'gnos_repos_with_complete_alignment_set: "'.$gnos_repo."\"" : '*';

    ## To Do: need to add in filtering for ones that were already aligned. 
    my $es_query = { 
       body => {
           "query" => {
              "filtered" => {
                 "query" => {
                    "bool" => {
                       "must" => [
                          {
                             "query_string" => {
                                "query" => "$query"
                             }
                          }
                       ],
                    }
                 },
                 "filter" => {
                    "bool" => {
                       "must" => [
                          {
                             "terms" => {
                                "normal_specimen.is_aligned" => [
                                   "T"
                                ]
                             }
                          },
                          {
                             "terms" => {
                                "are_all_tumor_specimens_aligned" => [
                                   "T"
                                ]
                             }
                          }
                       ],
                       "must_not" => {
                           "terms" => { 
                                  "donor_unique_id" =>
                                  $filter_donors
                           }
                       }
                  
                    }
                 }
              }
           },
          "size" => $self->{query_size},
           "sort" => [
              {
                 "gnos_study" => {
                    "order" => "asc",
                    "ignore_unmapped" => "true"
                 }
              }
           ]
       }
    };

    my $e = Search::Elasticsearch->new( nodes =>  $self->{elasticsearch_url} );
    my $results = $e->search( $es_query);

    my @donor_sources = $results->{hits}{hits};
    
    my %donors;
    foreach my $donor_source (@donor_sources) {
        foreach my $donor (@{$donor_source}) {
            $donors{$donor->{_id}} = $donor->{_source} if ($donor->{_type} eq 'donor');
        }
    }
    
    return \%donors;
}

sub get_aligned_sets {
    my ($self, $filter_donors, $gnos_repo, $vcf_workflow_name ) = @_;

    my $donors = get_donors_completed_alignment($self, $filter_donors, $gnos_repo);

    my %aligned_sets;
    foreach my $donor_id (keys %{$donors}) {
        my $tumour_specimen = $donors->{$donor_id}{aligned_tumor_specimens};
        my $normal_specimen = $donors->{$donor_id}{normal_specimen};
        $aligned_sets{$donor_id} = { tumours => $tumour_specimen,
                                     normal => $normal_specimen
                                   };
 
    }

    return \%aligned_sets;
}

1;

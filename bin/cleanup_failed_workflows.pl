use strict;
use Data::Dumper;

# this is just a quick hack to cleanup the bam files for workflows that failed
# we're doing this so the hosts can be used for subsequent workflows without
# quickly running out of space. This way Youxia can be set to allow for long-lived hosts
# used for a large number of runs with debug information stored in working directories for later use.

my ($seqware, $workflow_accession) = @ARGV;

my $cmd = "$seqware workflow report --accession $workflow_accession";
print "THE COMMAND: $cmd\n";
my $txt = `$cmd`;

my @a = split /\n/, $txt;

my $failed = 0;

foreach my $line (@a) {
  chomp $line;
  if ($line =~ /Workflow Run Status/ && ($line =~ /failed/ || $line =~ /cancelled/)) {
    $failed = 1;
  }
  if ($line =~ /Workflow Run Working Dir/) {
    if ($failed) {
 print "$line \n";
      $line =~ /^\s*Workflow Run Working Dir\s*\|\s*(\S+)\s*$/;
      print "DELETING: rm -f `find $1 | grep '\.bam'`\n";
    }
    $failed = 0;
  }
}


#!/bin/bash

# a simple script for finding all the steps that failed

for i in $1/*/stdout.txt;
do echo "ERROR DIR: $i"; 
cat $i | perl -e 'my $job; while(<STDIN>) { chomp; if (/Job Name:(.*)/) { $job = $1; } if (/code: 1/) { print "$job\n"; } }';
done;


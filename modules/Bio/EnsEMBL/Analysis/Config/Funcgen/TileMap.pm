# Ensembl module for Bio::EnsEMBL::Analysis::Config::Funcgen::TileMap
#
# Copyright (c) 2007 Ensembl
#

=head1 NAME

  Bio::EnsEMBL::Analysis::Config::Funcgen::TileMap

=head1 SYNOPSIS

  use Bio::EnsEMBL::Analysis::Config::Funcgen::TileMap;
  
  use Bio::EnsEMBL::Analysis::Config::Funcgen::TileMap qw(CONFIG);

=head1 DESCRIPTION

This is a module needed to provide configuration for the
TileMap RunnableDBs.

CHIPOTLE_CONFIG is an hash of hashes which contains analysis specific
settings and is keyed on logic_name

=head1 AUTHOR

This module was created by Stefan Graf. It is part of the 
Ensembl project: http://www.ensembl.org/

=head1 CONTACT

Post questions to the Ensembl development list: ensembl-dev@ebi.ac.uk

=cut

package Bio::EnsEMBL::Analysis::Config::Funcgen::TileMap;

use strict;
use vars qw(%Config);

%Config = 
    (
     TILEMAP_CONFIG => {
         DEFAULT => {
             PROGRAM           => $ENV{TM_PROGRAM},
             PROGRAM_FILE      => $ENV{TM_PROGRAM_FILE},
             VERSION           => $ENV{TM_VERSION},
             PARAMETERS        => $ENV{TM_PARAMETERS},
             EXPERIMENT        => $ENV{EXPERIMENT},
             NORM_ANALYSIS     => $ENV{NORM_ANALYSIS},
             RESULT_SET_REGEXP => $ENV{RESULT_SET_REGEXP},
             DATASET_NAME      => $ENV{DATASET_NAME},
             ANALYSIS_WORK_DIR => $ENV{ANALYSIS_WORK_DIR},
         },
         TILEMAP => {
             PROGRAM           => $ENV{TM_PROGRAM},
             PROGRAM_FILE      => $ENV{TM_PROGRAM_FILE},
             VERSION           => $ENV{TM_VERSION},
             PARAMETERS        => $ENV{TM_PARAMETERS},
             EXPERIMENT        => $ENV{EXPERIMENT},
             NORM_ANALYSIS     => $ENV{NORM_ANALYSIS},
             RESULT_SET_REGEXP => $ENV{RESULT_SET_REGEXP},
             DATASET_NAME      => $ENV{DATASET_NAME},
             ANALYSIS_WORK_DIR => $ENV{ANALYSIS_WORK_DIR},
         }
     });

sub import {
    my ($callpack) = caller(0); # Name of the calling package
    my $pack = shift; # Need to move package off @_
    
    # Get list of variables supplied, or else all
    my @vars = @_ ? @_ : keys(%Config);
    return unless @vars;
    
    # Predeclare global variables in calling package
    eval "package $callpack; use vars qw("
        . join(' ', map { '$'.$_ } @vars) . ")";
    die $@ if $@;
    
    
    foreach (@vars) {
        if (defined $Config{ $_ }) {
            no strict 'refs';
            # Exporter does a similar job to the following
            # statement, but for function names, not
            # scalar variables:
            *{"${callpack}::$_"} = \$Config{ $_ };
        } else {
            die "Error: Config: $_ not known\n";
        }
    }
}

1;

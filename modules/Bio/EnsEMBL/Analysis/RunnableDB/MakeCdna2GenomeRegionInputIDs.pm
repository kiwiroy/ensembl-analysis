package Bio::EnsEMBL::Analysis::RunnableDB::MakeCdna2GenomeRegionInputIDs;
use strict;
use warnings;
use Bio::EnsEMBL::Analysis::RunnableDB;
use Bio::EnsEMBL::Analysis::RunnableDB::BaseGeneBuild;
use Bio::EnsEMBL::Analysis::Config::GeneBuild::MakeCdna2GenomeRegionInputIDs qw(CDNA2GENOME_REGION_CONFIG_BY_LOGIC);
use Bio::EnsEMBL::Utils::Exception qw(throw warning);
use Bio::EnsEMBL::Utils::Argument qw(rearrange);
use Bio::EnsEMBL::Analysis::Tools::Utilities qw (parse_config);
use Bio::EnsEMBL::Analysis::Tools::Logger qw(logger_info);
use Bio::EnsEMBL::Pipeline::DBSQL::DBAdaptor; 
use vars qw (@ISA);

@ISA = qw(Bio::EnsEMBL::Analysis::RunnableDB::BaseGeneBuild);

sub new {
  my ($class,@args) = @_;
  my $self = $class->SUPER::new(@args);

  my ( $submit_logic_name, $gene_db, $pipe_db, $expansion, $annotation ) =
    rearrange( [ 'SUBMIT_LOGIC_NAME', 'GENE_DB',
                 'PIPE_DB',           'EXPANSION',
                 'ANNOTATION'
               ], @args );

  # read default config entries
  # actually will read default twice by giving default as logic_name
  # but also does some nice checking and I want the config precedence
  # to be default, param hash, constructor and finally logic_name
  # config over-riding others
  parse_config($self, $CDNA2GENOME_REGION_CONFIG_BY_LOGIC, 'DEFAULT');

  # Defaults are over-ridden by parameters given in analysis table...
  my $ph = $self->parameters_hash;
  $self->SUBMIT_LOGIC_NAME($ph->{-submit_logic_name})   if $ph->{-submit_logic_name};
  $self->GENE_DB($ph->{-gene_db})                       if $ph->{-gene_db};
  $self->PIPE_DB($ph->{-pipe_db})                       if $ph->{-pipe_db};
  $self->EXPANSION($ph->{-expansion})                   if $ph->{-expansion};
  $self->ANNOTATION($ph->{-annotation})                 if $ph->{-annotation};

  #...which are over-ridden by constructor arguments. 
  $self->SUBMIT_LOGIC_NAME($submit_logic_name);
  $self->GENE_DB($gene_db);
  $self->PIPE_DB($pipe_db);
  $self->EXPANSION($expansion);
  $self->ANNOTATION($annotation);

  # Finally, analysis specific config
  # use uc as parse_config call above switches logic name to upper case
  $self->SUBMIT_LOGIC_NAME(${$CDNA2GENOME_REGION_CONFIG_BY_LOGIC}{uc($self->analysis->logic_name)}{SUBMIT_LOGIC_NAME});

  $self->GENE_DB(${$CDNA2GENOME_REGION_CONFIG_BY_LOGIC}{uc($self->analysis->logic_name)}{GENE_DB});

  $self->PIPE_DB(${$CDNA2GENOME_REGION_CONFIG_BY_LOGIC}{uc($self->analysis->logic_name)}{PIPE_DB});

  $self->EXPANSION(${$CDNA2GENOME_REGION_CONFIG_BY_LOGIC}{uc($self->analysis->logic_name)}{EXPANSION});

  $self->ANNOTATION(${$CDNA2GENOME_REGION_CONFIG_BY_LOGIC}{uc($self->analysis->logic_name)}{ANNOTATION});

  #throw if something vital is missing
  if ( (    !$self->SUBMIT_LOGIC_NAME
         || !$self->GENE_DB
         || !$self->PIPE_DB
         || !$self->EXPANSION ) )
  {
    throw(   "Need to specify SUBMIT_LOGIC_NAME, GENE_DB, "
           . "PIPE_DB and EXPANSION." );
  }

  print "Annotation file is:".$self->ANNOTATION."\n";

  if ( defined $self->ANNOTATION and not -e $self->ANNOTATION ) {
    throw( "Annotation file " . $self->ANNOTATION . " is not readable." );
  }

  return $self;
}

sub fetch_input {
  my ($self) = @_;

  # Check submit analysis exists in pipe db, where input ids of that
  # type will be written
  my $dba_pip = $self->get_pipe_dba;
  my $submit_analysis =
    $dba_pip->get_AnalysisAdaptor->fetch_by_logic_name( $self->SUBMIT_LOGIC_NAME );

  if ( !$submit_analysis ) {
    throw(   "Failed to find an analysis with the logic_name "
           . $self->SUBMIT_LOGIC_NAME
           . " in the pipeline db. Cannot continue." );
  }

  $self->submit_analysis($submit_analysis);

  # get genes
  my $gene_dba = $self->get_gene_dba;
  my @genes =
    @{ $gene_dba->get_SliceAdaptor->fetch_by_name( $self->input_id )->get_all_Genes() };

  print "There are " . scalar(@genes) . " genes.\n";
  $self->genes( \@genes );
}

sub run {
  my ($self) = @_;

  my $expansion = $self->EXPANSION;
  my @iids;

GENE: foreach my $gene ( @{ $self->genes } ) {
    # Check that there is only one piece of supporting evidence per gene
    my @transcripts = @{ $gene->get_all_Transcripts };
    throw "Multi-transcript gene." if ( scalar(@transcripts) > 1 );

    my $transcript = $transcripts[0];
    my @evidence   = @{ $transcript->get_all_supporting_features };
    throw "Multiple supporting features for transcript."
      if ( scalar(@evidence) > 1 );

    # query
    my $hit_name = $evidence[0]->hseqname();
    if ( $self->ANNOTATION ) {
      open(F, $self->ANNOTATION) or throw("Could not open supplied annotation file for reading");
      my $unmatched = 1;
    LINE: while (<F>) {
        my @fields = split;
        $unmatched = 0 if $hit_name eq $fields[0];
        last LINE if !$unmatched;
      }
      close(F);
      print "WARNING: " . $hit_name . " had no entry in annotation file.\n"
        if $unmatched;
      next GENE if $unmatched;
    }
    # genomic
    my $genomic_slice =
      $self->get_gene_dba->get_SliceAdaptor->fetch_by_transcript_id(
                                                            $transcript->dbID,
                                                            $expansion );

    my $id = $genomic_slice->name . '::' . $hit_name;
    push @iids, $id;
  } ## end foreach my $gene ( @{ $self...

  #Get rid of any duplicate ids that may have been generated
  my $num_ids = scalar(@iids);
  my %unique_ids;
  @unique_ids{@iids} = ();
  @iids = keys %unique_ids;
  print "WARNING: " . scalar(@iids)
    . " unique ids from " . $num_ids . " generated ids.\n"
    if scalar(@iids) < $num_ids;
  $self->output( \@iids );
} ## end sub run

sub write_output {
  my ($self) = @_;
  my $sic = $self->get_pipe_dba->get_StateInfoContainer;

  print "output submit analysis is : " . $self->SUBMIT_LOGIC_NAME . "\n";

  foreach my $iid ( @{ $self->output } ) {
    print "try to store input_id : $iid\n";
    eval {
      $sic->store_input_id_analysis( $iid, $self->submit_analysis, '' );
    };
    throw( "Failed to store " . $iid . " $@" ) if ($@);
    logger_info( "Stored " . $iid );
  }
}

sub get_gene_dba {
  my ($self) = @_;
  my $genedba;

  if ( $self->GENE_DB ) {
    if ( ref( $self->GENE_DB ) =~ m/HASH/ ) {
      $genedba = new Bio::EnsEMBL::DBSQL::DBAdaptor( %{ $self->GENE_DB },
                                                    -dnadb => $self->DNA_DB );
    } else {
      $genedba = $self->get_dbadaptor( $self->GENE_DB );
    }
  }
  return $genedba;
}

sub get_pipe_dba {
  my ($self) = @_;
  my $pipedba;

  if ( $self->PIPE_DB ) {
    if ( ref( $self->PIPE_DB ) =~ m/HASH/ ) {
      $pipedba =
        new Bio::EnsEMBL::Pipeline::DBSQL::DBAdaptor( %{ $self->PIPE_DB },
                                                    -dnadb => $self->DNA_DB );
    } else {
      $pipedba = $self->get_dbadaptor( $self->PIPE_DB, 'pipeline' );
    }
  }
  return $pipedba;
}

sub EXPANSION {
  my ( $self, $value ) = @_;
  if ($value) {
    $self->{'EXPANSION'} = $value;
  }
  return $self->{'EXPANSION'};
}

sub SUBMIT_LOGIC_NAME {
  my ( $self, $value ) = @_;
  if ($value) {
    $self->{'SUBMIT_LOGIC_NAME'} = $value;
  }
  return $self->{'SUBMIT_LOGIC_NAME'};
}

sub ANNOTATION {
  my ( $self, $value ) = @_;
  if ($value) {
    $self->{'ANNOTATION'} = $value;
  }
  return $self->{'ANNOTATION'};
}


sub GENE_DB {
  my ( $self, $value ) = @_;
  if ($value) {
    $self->{'GENE_DB'} = $value;
  }
  return $self->{'GENE_DB'};
}

sub PIPE_DB {
  my ( $self, $value ) = @_;
  if ($value) {
    $self->{'PIPE_DB'} = $value;
  }
  return $self->{'PIPE_DB'};
}

sub submit_analysis {
  my ( $self, $value ) = @_;
  if (    $value
       && $value->isa('Bio::EnsEMBL::Pipeline::Analysis') )
  {
    $self->{submit_analysis} = $value;
  }
  return $self->{'submit_analysis'};
}

sub genes {
  my ( $self, $value ) = @_;
  if ( $value && ( ref($value) eq "ARRAY" ) ) {
    $self->{genes} = $value;
  }
  return $self->{'genes'};
}

sub pipeline_adaptor {
  my ( $self, $value ) = @_;
  if (    $value
       && $value->isa('Bio::EnsEMBL::Pipeline::DBSQL::DBAdaptor') )
  {
    $self->{pipeline_adaptor} = $value;
  }
  return $self->{'pipeline_adaptor'};
}

sub protein_count {
  my ( $self, $value ) = @_;
  if ($value) {
    $self->{'protein_count'} = $value;
  }
  return $self->{'protein_count'};
}

sub output_logicname {
  my ( $self, $value ) = @_;
  if ($value) {
    $self->{'output_logicname'} = $value;
  }
  return $self->{'output_logicname'};
}

sub bmg_logicname {
  my ( $self, $value ) = @_;
  if ($value) {
    $self->{'bmg_logicname'} = $value;
  }
  return $self->{'bmg_logicname'};
}

sub paf_slice {
  my ( $self, $slice ) = @_;

  if ($slice) {
    $self->{paf_slice} = $slice;
  }
  if ( !$self->{paf_slice} ) {
    my $slice = $self->fetch_sequence( $self->input_id,
                                       $self->paf_source_db,
                                       $self->REPEATMASKING );
    $self->{paf_slice} = $slice;
  }
  return $self->{paf_slice};
}

sub gene_slice {
  my ( $self, $slice ) = @_;

  if ($slice) {
    $self->{gene_slice} = $slice;
  }
  if ( !$self->{gene_slice} ) {
    my $slice = $self->fetch_sequence( $self->input_id,
                                       $self->gene_source_db,
                                       $self->REPEATMASKING );
    $self->{gene_slice} = $slice;
  }
  return $self->{gene_slice};
}

sub paf_source_db {
  my ( $self, $db ) = @_;
  if ($db) {
    $self->{paf_source_db} = $db;
  }
  if ( !$self->{paf_source_db} ) {
    my $db = $self->get_dbadaptor( $self->PAF_SOURCE_DB );
    $self->{paf_source_db} = $db;
  }
  return $self->{paf_source_db};
}

sub gene_source_db {
  my ( $self, $db ) = @_;
  if ($db) {
    $self->{gene_source_db} = $db;
  }
  if ( !$self->{gene_source_db} ) {
    my $db = $self->get_dbadaptor( $self->GENE_SOURCE_DB );
    $self->{gene_source_db} = $db;
  }
  return $self->{gene_source_db};
}


=head2 CONFIG_ACCESSOR_METHODS

  Arg [1]   : Bio::EnsEMBL::Analysis::RunnableDB::BlastMiniGenewise
  Arg [2]   : Varies, tends to be boolean, a string, a arrayref or a hashref
  Function  : Getter/Setter for config variables
  Returntype: again varies
  Exceptions:
  Example   :

=cut

# Note the function of these variables is better described in the
# config file itself Bio::EnsEMBL::Analysis::Config::GeneBuild::BlastMiniGenewise

sub PAF_LOGICNAMES {
  my ( $self, $arg ) = @_;
  if ($arg) {
    $self->{PAF_LOGICNAMES} = $arg;
  }
  return $self->{PAF_LOGICNAMES};
}

sub PAF_MIN_SCORE_THRESHOLD {
  my ( $self, $arg ) = @_;
  if ($arg) {
    $self->{PAF_MIN_SCORE_THRESHOLD} = $arg;
  }
  return $self->{PAF_MIN_SCORE_THRESHOLD};
}

sub PAF_UPPER_SCORE_THRESHOLD {
  my ( $self, $arg ) = @_;
  if ($arg) {
    $self->{PAF_UPPER_SCORE_THRESHOLD} = $arg;
  }
  return $self->{PAF_UPPER_SCORE_THRESHOLD};
}

sub PAF_SOURCE_DB {
  my ( $self, $arg ) = @_;
  if ($arg) {
    $self->{PAF_SOURCE_DB} = $arg;
  }
  return $self->{PAF_SOURCE_DB};
}

sub GENE_SOURCE_DB {
  my ( $self, $arg ) = @_;
  if ($arg) {
    $self->{GENE_SOURCE_DB} = $arg;
  }
  return $self->{GENE_SOURCE_DB};
}

sub OUTPUT_DB {
  my ( $self, $arg ) = @_;
  if ($arg) {
    $self->{OUTPUT_DB} = $arg;
  }
  return $self->{OUTPUT_DB};
}

sub OUTPUT_BIOTYPE {
  my ( $self, $arg ) = @_;
  if ($arg) {
    $self->{OUTPUT_BIOTYPE} = $arg;
  }
  return $self->{OUTPUT_BIOTYPE};
}

sub GENEWISE_PARAMETERS {
  my ( $self, $arg ) = @_;
  if ($arg) {
    $self->{GENEWISE_PARAMETERS} = $arg;
  }
  return $self->{GENEWISE_PARAMETERS};
}

sub MINIGENEWISE_PARAMETERS {
  my ( $self, $arg ) = @_;
  if ($arg) {
    $self->{MINIGENEWISE_PARAMETERS} = $arg;
  }
  return $self->{MINIGENEWISE_PARAMETERS};
}

sub MULTIMINIGENEWISE_PARAMETERS {
  my ( $self, $arg ) = @_;
  if ($arg) {
    $self->{MULTIMINIGENEWISE_PARAMETERS} = $arg;
  }
  return $self->{MULTIMINIGENEWISE_PARAMETERS};
}

sub BLASTMINIGENEWISE_PARAMETERS {
  my ( $self, $arg ) = @_;
  if ($arg) {
    $self->{BLASTMINIGENEWISE_PARAMETERS} = $arg;
  }
  return $self->{BLASTMINIGENEWISE_PARAMETERS};
}

sub FILTER_PARAMS {
  my ( $self, $arg ) = @_;
  if ($arg) {
    $self->{FILTER_PARAMETERS} = $arg;
  }
  return $self->{FILTER_PARAMETERS};
}

sub FILTER_OBJECT {
  my ( $self, $arg ) = @_;
  if ($arg) {
    $self->{FILTER_OBJECT} = $arg;
  }
  return $self->{FILTER_OBJECT};
}

sub BIOTYPES_TO_MASK {
  my ( $self, $arg ) = @_;
  if ($arg) {
    $self->{BIOTYPES_TO_MASK} = $arg;
  }
  return $self->{BIOTYPES_TO_MASK};
}

sub EXON_BASED_MASKING {
  my ( $self, $arg ) = @_;
  if ($arg) {
    $self->{EXON_BASED_MASKING} = $arg;
  }
  return $self->{EXON_BASED_MASKING};
}

sub GENE_BASED_MASKING {
  my ( $self, $arg ) = @_;
  if ($arg) {
    $self->{GENE_BASED_MASKING} = $arg;
  }
  return $self->{GENE_BASED_MASKING};
}

sub POST_GENEWISE_MASK {
  my ( $self, $arg ) = @_;
  if ($arg) {
    $self->{POST_GENEWISE_MASK} = $arg;
  }
  return $self->{POST_GENEWISE_MASK};
}

sub PRE_GENEWISE_MASK {
  my ( $self, $arg ) = @_;
  if ($arg) {
    $self->{PRE_GENEWISE_MASK} = $arg;
  }
  return $self->{PRE_GENEWISE_MASK};
}

sub REPEATMASKING {
  my ( $self, $arg ) = @_;
  if ($arg) {
    $self->{REPEATMASKING} = $arg;
  }
  return $self->{REPEATMASKING};
}

sub USE_KILL_LIST {
  my ( $self, $arg ) = @_;
  if ($arg) {
    $self->{USE_KILL_LIST} = $arg;
  }
  return $self->{USE_KILL_LIST};
}

sub LIMIT_TO_FEATURE_RANGE {
  my ( $self, $arg ) = @_;
  if ($arg) {
    $self->{LIMIT_TO_FEATURE_RANGE} = $arg;
  }
  return $self->{LIMIT_TO_FEATURE_RANGE};
}

sub FEATURE_RANGE_PADDING {
  my ( $self, $arg ) = @_;
  if ($arg) {
    $self->{FEATURE_RANGE_PADDING} = $arg;
  }
  return $self->{FEATURE_RANGE_PADDING};
}

sub WRITE_REJECTED {
  my ( $self, $arg ) = @_;
  if ( defined($arg) ) {
    $self->{WRITE_REJECTED} = $arg;
  }
  return $self->{WRITE_REJECTED};
}

sub REJECTED_BIOTYPE {
  my ( $self, $arg ) = @_;
  if ($arg) {
    $self->{REJECTED_BIOTYPE} = $arg;
  }
  return $self->{REJECTED_BIOTYPE};
}

sub SOFTMASKING {
  my ( $self, $arg ) = @_;
  if ($arg) {
    $self->{SOFTMASKING} = $arg;
  }
  return $self->{SOFTMASKING};
}

sub EXONERATE_PARAMETERS {
  my ( $self, $arg ) = @_;
  if ($arg) {
    $self->{EXONERATE_PARAMETERS} = $arg;
  }
  return $self->{EXONERATE_PARAMETERS};
}

sub MAKE_SIMGW_INPUT_ID_PARMAMS {
  my ( $self, $arg ) = @_;
  if ($arg) {
    $self->{MAKE_SIMGW_INPUT_ID_PARMAMS} = $arg;
  }
  return $self->{MAKE_SIMGW_INPUT_ID_PARMAMS};
}
1;

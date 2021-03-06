#!/usr/bin/perl
# Copyright (C) 2011 Ion Torrent Systems, Inc. All Rights Reserved

#--------- Begin command arg parsing ---------

(my $CMD = $0) =~ s{^(.*/)+}{};
my $DESCR = "Create numbers of fwd/rev target base read depth over specified chromosome region for a given BBC file. (Output to STDOUT.)
If start and end of chromosome defined these are 1-based coordinates. Forward and reverse coverage is summed and output for a number of
bins (200 by default). The totals for on-taret base reads are also output if present in the BBC/CBC files, unless the -n option is supplied.";
my $USAGE = "Usage:\n\t$CMD [options] <BBC file> <chrom> [<start>] [<end>]";
my $OPTIONS = "Options:
  -h ? --help Display Help information
  -b <int> Number of bins to output. Default: 200. (Actual number may be less if smaller than contig size.)
  -s <int> Start bins to skip for output. Default: 0.
  -e <int> End bin to output. Default: 0. (Output to the last bin.)
  -r Output Regions-only BED file. (0-base region start.)
  -l Write detail log messages to STDERR.
  -n Do Not output on-target read coverage counts (when present in the input BBC/CBC files).
  -c <int> Binning size used in coarse coverage file (if -C option used). Default: 1000.
  -C <file> Coarse coverage (CBC) file to use for performance over large regions. Default: '' (Just use BBC file.)";

my $numOutBins = 200;
my $cbcfile = "";
my $cbcBinSize = 1000;
my $logopt = 0;
my $haveTargets = 1;
my $srtBin = 0;
my $endBin = 0;
my $regionBed = 0;

my $help = (scalar(@ARGV) == 0);
while( scalar(@ARGV) > 0 )
{
  last if($ARGV[0] !~ /^-/);
  my $opt = shift;
  if($opt eq '-C') {$cbcfile = shift;}
  elsif($opt eq '-b') {$numOutBins = int(shift);}
  elsif($opt eq '-s') {$srtBin = int(shift);}
  elsif($opt eq '-e') {$endBin = int(shift);}
  elsif($opt eq '-r') {$regionBed = 1;}
  elsif($opt eq '-l') {$logopt = 1;}
  elsif($opt eq '-c') {$cbcBinSize = int(shift);}
  elsif($opt eq '-n') {$haveTargets = 0;}
  elsif($opt eq '-h' || $opt eq "?" || $opt eq '--help') {$help = 1;}
  else
  {
    print STDERR "$CMD: Invalid option argument: $opt\n";
    print STDERR "$OPTIONS\n";
    exit 1;
  }
}
my $nargs = scalar @ARGV;
if( $help )
{
  print STDERR "$DESCR\n";
  print STDERR "$USAGE\n";
  print STDERR "$OPTIONS\n";
  exit 1;
}
elsif( $nargs < 2 || $nargs > 4 )
{
  print STDERR "$CMD: Invalid number of arguments.\n";
  print STDERR "$USAGE\n";
  exit 1;
}

my $bbcfile = shift(@ARGV);
my $targChrom = shift(@ARGV);
my $targStart = int(shift(@ARGV));
my $targEnd = int(shift(@ARGV));

$numOutBins = 200 if( $numOutBins < 1 );
$cbcBinSize = 1000 if( $cbcBinSize < 1 );

if( $targEnd < $targStart )
{
  print STDERR "$CMD: Invalid arguments: <end> value must be >= <start>.\n";
  exit 1;
}

my $haveCbc = ($cbcfile ne "" && $cbcfile ne "-" );
$srtBin = 0 if( $srtBin < 0 );
$endBin = 0 if( $endBin < 0 );

#--------- End command arg parsing ---------

use constant BIGWORD => 2**32;

# table file fields line
my $header = "chrom\tstart\tend\tfwd_basereads\trev_basereads";
$header .= "\tfwd_trg_basereads\trev_trg_basereads" if( $haveTargets );

my $intsize = 4;

die "Cannot find depth file $bbcfile" unless( -e $bbcfile );

# read expected chromosomes from the BBCFILE
open( BBCFILE, "<:raw", $bbcfile ) || die "Failed to open BBC file $bbcfile\n";
chomp( my $contigList = <BBCFILE> );
my @chromName = split('\t',$contigList );
my $numChroms = scalar(@chromName);
my @chromSize;
my $genomeSize = 0;
for( my $i = 0; $i < $numChroms; ++$i )
{
  my @fields = split('\$',$chromName[$i]);
  $chromName[$i] = $fields[0];
  $chromSize[$i] = int($fields[1]);
  $genomeSize += $chromSize[$i];
}
print STDERR "Read $numChroms contig names and lengths. Total contig size: $genomeSize\n" if( $logopt );

# check the speicifed target against contig sizes and determine coverage bin file offset
my $targChromLen = 0;
my $targChromNum = 0;
my $targCBlength = 0;
my $targCBoffset = 0;
my $cbcSize = 0;
for( my $cn = 0; $cn < $numChroms; ++$cn )
{
  my $chrid = $chromName[$cn];
  my $chrlen = $chromSize[$cn];
  my $cbnum = $chrlen / $cbcBinSize;
  $cbnum = ($cbnum == int($cbnum)) ? $cbnum : int($cbnum + 1);
  if( $chrid eq $targChrom )
  {
    $targChromNum = $cn;
    $targChromLen = $chrlen;
    $targCBlength = $cbnum;
    $targCBoffset = $cbcSize;
  }
  $cbcSize += $cbnum;
}
if( $targChromLen <= 0 )
{
  print STDERR "$CMD: Specified contig ($targChrom) is not in the genome.\n";
  exit 1;
}
if( $targEnd > $targChromLen )
{
  print STDERR "Corrected specified target end ($targEnd) to contig length ($targChromLen).\n" if( $logopt );
  $targEnd = $targChromLen;
}
$targStart = 1 if( $targStart <= 0 );
$targEnd = $targChromLen if( $targEnd < $targStart );

my $regionFilter = "$targChrom";
$regionFilter .= ":$targStart" if( $targStart > 0 );
$regionFilter .= "-$targEnd" if( $targEnd > 0 );
my $regionLength = $targEnd - $targStart + 1;
my $binsize = $regionLength / $numOutBins;
if( $regionLength < $numOutBins )
{
  $numOutBins = $regionLength;
  $binsize = 1;
}
# adjust optional window range vs. actual number of bins output
$endBin = $numOutBins if( $endBin < 1 || $endBin > $numOutBins );
$srtBin = $endBin if( $srtBin > $endBin );

# if pre-binned file not disabled, check if it should be used
my $useCbc = ($haveCbc && $binsize >= 10 * $cbcBinSize);
if( $useCbc )
{
  # disable output of targets if none appear in CBC file
  if( -e $cbcfile )
  {
    my $nvalues = (stat $cbcfile)[7] / ($cbcSize * $intsize);
    if( $nvalues == 2 )
    {
      print STDERR "$CMD: Warning: No target information in CBC file. Disabling output of on-target read counts.\n" if( $haveTargets );
      $haveTargets = 0;
    }
    elsif( $nvalues != 4 )
    {
      print STDERR "$CMD: WARNING: Unexpected record size in CBC file $nvalues (for expected $cbcSize records).\n";
      print STDERR " - Using BBC base reads, which may take longer.\n";
      $useCbc = 0;
    }
    elsif( $logopt )
    {
      print STDERR "CBC record size = $nvalues (for expected $cbcSize records)\n" if( $logopt );
    }
  }
  else
  {
    print STDERR "$CMD: Warning: Expected pre-binned reads file $cbcfile does not exist.\n - Using BBC base reads, which may take longer.\n";
    $useCbc = 0;
  }
}

if( $useCbc )
{
  # round region boundaries to accurately use sample bins
  # - this means each output bin is an integer number of sample bins
  close( BBCFILE );
  if( $logopt )
  {
    print STDERR "Modifying selected region to closest coarse-sampled region.\n";
    print STDERR "- Original region: $targStart - $targEnd ($regionLength), output binsize = $binsize\n";
  }
  $numcbcs = $binsize / $cbcBinSize;
  $numcbcs = int($numcbcs+1) if( $numcbcs > int($numcbcs) );
  $binsize = int($numcbcs) * $cbcBinSize;
  $targStart = 1 + $cbcBinSize * int(0.5 * ($targStart + $targEnd - 1 - $binsize * $numOutBins) / $cbcBinSize);
  $targStart = 1 if( $targStart <= $cbcBinSize );
  $targEnd = $targStart - 1 + $binsize * $numOutBins;
  $targEnd = $targChromLen if( $targEnd > $targChromLen );
  if( $logopt )
  {
    printf STDERR "- Sampled region:  $targStart - $targEnd (%d), output binsize = $binsize\n", $targEnd-$targStart+1;
    printf STDERR "- Effective range: %d = ($numcbcs * $numOutBins) * $cbcBinSize\n", $binsize*$numOutBins;
  }
  # by-pass all the work if only the boundaries wanted as a BED file
  if( $regionBed ) {
    for( my $i = $srtBin; $i < $endBin && $lastRec < 1; ++$i )
    {
      my $srt = $targStart+$i*$binsize;
      my $end = $srt + $binsize - 1;
      if( $end > $targChromLen )
      {
        $end = $targChromLen;
        $i = $endBin;
      }
      printf "$targChrom\t%.0f\t%.0f\n", $srt-1, $end if( $i >= $srtBin )
    }
    exit 0;
  }
  # read course bins and add to make new coverage bins - one big read is much faster
  my $intsPerSample = $haveTargets ? 4 : 2;
  my $bytesPerInt = 4;
  my $binSkip = int(($targStart-1)/$cbcBinSize);
  print STDERR "Skipping to data bin $binSkip + $targCBoffset\n" if( $logopt );
  my $skipto = $intsPerSample * $bytesPerInt * ($binSkip + $targCBoffset);
  my $numSamples = $binsize * $numOutBins / $cbcBinSize;
  if( $binSkip+$numSamples > $targCBlength )
  {
    $numSamples = $targCBlength - $binSkip;
    printf STDERR "- Corrected range: %d = (%d * $numOutBins + %d) * $cbcBinSize\n",
      $cbcBinSize*$numSamples, ($numcbcs-1), ($numSamples % $numOutBins) if( $logopt );
  }
  my $numints = $intsPerSample * $numSamples;
  my $numbytes = $bytesPerInt * $numints;
  print STDERR "Unpacking $numSamples bins (x$intsPerSample ints) at CBC offset $skipto\n" if( $logopt );
  open( CBCFILE, "<:raw", $cbcfile ) or die "Cannot read binary coverage from $cbcfile.\n";
  seek( CBCFILE, $skipto, 0 );
  read( CBCFILE , my $buffer, $numbytes) == $numbytes or die "Did not read $numbytes bytes at $skipto for $regionFilter from $cbcfile\n";
  my @ary = unpack "L[$numints]", $buffer;
  close( CBCFILE );
  # output bins as tsv - note for small genomes the round-off may require extra empty bins - correct here
  my $a = 0, $lastRec = 0;
  print "$header\n";
  for( my $i = 0; $i < $endBin && $lastRec < 1; ++$i )
  {
    my ($sumFwd,$sumRev,$sumFOT,$sumROT) = (0,0,0,0);
    for( my $j = 0; $j < $numcbcs; ++$j )
    {
      last if( $a >= $numints );
      $sumFwd += $ary[$a++];
      $sumRev += $ary[$a++];
      if( $haveTargets )
      {
        $sumFOT += $ary[$a++];
        $sumROT += $ary[$a++];
      }
    }
    my $srt = $targStart+$i*$binsize;
    my $end = $srt + $binsize - 1;
    if( $end > $targChromLen )
    {
      $end = $targChromLen;
      $lastRec = $i+1; # do not output any more bins - should only happen with small/awkward length references
    }
    if( $i >= $srtBin )
    {
      printf "$targChrom\t%.0f\t%.0f\t%.0f\t%.0f", $srt, $end, $sumFwd, $sumRev;
      print "\t$sumFOT\t$sumROT" if( $haveTargets );
      print "\n";
    }
  }
  print STDERR "Warning: Output $lastRec instead of $numOutBins due to bin resolution.\n" if( $lastRec >= 0 && $logopt );
  exit 0;
}

# first pass for counting reads per bin
my @binFwdOff = ((0) x $numOutBins);
my @binRevOff = ((0) x $numOutBins);
my @binFwdOnt = ((0) x $numOutBins);
my @binRevOnt = ((0) x $numOutBins);

print STDERR "Specified CBC file ignorred based on region size.\n" if( $haveCbc && $logopt );

# by-pass all the work if only the boundaries wanted as a BED file
my $bin0 = int(($targStart-1)/$binsize);
if( $regionBed ) {
  close( BBCFILE );
  my ($srt,$bin,$lbn) = ($targStart-1,0,0);
  for( my $pos = $targStart; $pos < $targEnd; ++$pos )
  {
    $bin = int($pos/$binsize)-$bin0;
    if( $bin != $lbn )
    {
      printf "$targChrom\t%.0f\t%.0f\n", $srt, $pos if( $bin > $srtBin );
      $lbn = $bin;
      $srt = $pos;
      last if( $bin >= $endBin );
    }
  }
  printf "$targChrom\t%.0f\t%.0f\n", $srt, $targEnd if( $bin < $endBin );
  exit 0;
}

# load read depth file (for off-target if target depth file unspecified
my $upcstr = "";
my $headbytes = 2 * $intsize;
my $seekStart = bciSeekStart( $bbcfile, $targChromNum, $targStart, $targEnd );
print STDERR "Seek start for $targChrom:$targStart = $seekStart\n" if( $logopt );
if( $seekStart > 0 )
{
  seek( BBCFILE, $seekStart, 0 ) || die "Failed to seek to BBC offset $seekStart\n";
  my ($cd,$rdlen,$wdsiz,$fcov,$rcov,$bin);
  my $pos = 0;
  while( $pos <= $targEnd )
  {
    last if( read( BBCFILE, my $buffer, $headbytes) != $headbytes );
    ($pos,$cd) = unpack "L2", $buffer;
    last if( $pos == 0 ); # start of next contig
    last if( $pos > $targEnd );
    $wdsiz = ($cd & 6) >> 1;
    next if( $wdsiz == 0 );  # ignore 0 read regions (for now)
    $rdlen = $cd >> 3;
    if( $pos+$rdlen < $targStart )
    {
      # ignore regions ending before target start
      last unless( seek( BBCFILE, $rdlen << $wdsiz, 1 ) );
      next;
    }
    # skips read to align for regions overlapping target start
    if( $pos < $targStart )
    {
      my $skip = $targStart - $pos;
      last unless( seek( BBCFILE, $skip << $wdsiz, 1 ) );
      $rdlen -= $skip;
      $pos = $targStart;
    }
    #printf STDERR "Reading region: $pos+$rdlen ($wdsiz.%d)\n", ($cd & 1) if( $logopt );
    # debatable if reading whole block into memory would be useful here - reading is buffered anyway
    if( $wdsiz == 3 ) {$upcstr = "L2";}
    elsif( $wdsiz == 2 ) {$upcstr = "S2";}
    else {$upcstr = "C2";}
    $wdsiz = 1 << $wdsiz;
    # duplicated code to avoid having repeated if test
    if( $cd & 1 & $haveTargets )
    {
      while( $rdlen )
      {
        read( BBCFILE, my $buffer, $wdsiz );
        ($fcov,$rcov) = unpack $upcstr, $buffer;
        $bin = int(($pos-1)/$binsize)-$bin0;
        $binFwdOnt[$bin] += $fcov;
        $binRevOnt[$bin] += $rcov;
        --$rdlen;
        last if( ++$pos > $targEnd );
      }
    }
    else
    {
      while( $rdlen )
      {
        read( BBCFILE, my $buffer, $wdsiz );
        ($fcov,$rcov) = unpack $upcstr, $buffer;
        $bin = int(($pos-1)/$binsize)-$bin0;
        $binFwdOff[$bin] += $fcov;
        $binRevOff[$bin] += $rcov;
        --$rdlen;
        last if( ++$pos > $targEnd );
      }
    }
    last if( $pos > $targEnd );
  }
}
close( BBCFILE );

# output bins as tsv - region looked at using same math to avoid round-off errors
print "$header\n";
my ($srt,$bin,$lbn) = ($targStart,0,0);
for( my $pos = $targStart; $pos < $targEnd; ++$pos )
{
  $bin = int($pos/$binsize)-$bin0; # pos here is 0-based
  if( $bin != $lbn )
  {
    if( $bin > $srtBin )
    {
      printf "$targChrom\t%.0f\t%.0f\t%.0f\t%.0f", $srt, $pos, $binFwdOff[$lbn]+$binFwdOnt[$lbn], $binRevOff[$lbn]+$binRevOnt[$lbn];
      printf "\t%.0f\t%.0f", $binFwdOnt[$lbn], $binRevOnt[$lbn] if( $haveTargets );
      print "\n";
    }
    $lbn = $bin;
    $srt = $pos+1;
    last if( $bin >= $endBin );
  }
}
if( $bin < $endBin )
{
  printf "$targChrom\t%.0f\t%.0f\t%.0f\t%.0f", $srt, $targEnd, $binFwdOff[$lbn]+$binFwdOnt[$lbn], $binRevOff[$lbn]+$binRevOnt[$lbn];
  printf "\t%.0f\t%.0f", $binFwdOnt[$lbn], $binRevOnt[$lbn] if( $haveTargets );
  print "\n";
}

# ----------------END-------------------

# Return the seek position into the depth file closet >= read coordinate for given chromosome and starting position
# The chromosome is the 1-base index of the contig as it appears in the fai file, e.g. 2->chr2, 23->chrX, etc.
# A return value of 0 means there was no coverage for the given chromosome or the chrom/start was out of range.
# The end location of the region is only necessary to ensure that if there is nothing in the starting bin
# then subsequent bins will be checked that overlap the region. This is only a safety precaution since indexing
# should already denote where to move to for te start of the next covered region (i.e. no zero references.)
sub bciSeekStart
{
  my ($bbcfile,$chrom,$srt_pos,$end_pos) = @_;
  ++$chrom;
  print STDERR "bciSeekStart for chr#$chrom:$srt_pos\n" if( $logopt );
  return 0 if( $chrom <= 0 || $srt_pos <= 0 );
  my $bcifile = $bbcfile . '.bci';
  unless( -e $bcifile )
  {
    $bcifile = $bbcfile;
    $bcifile =~ s/\.bbc$//;
    $bcifile .= ".bci";
  }
  open BCIFILE, "<:raw", $bcifile or die "Could not open $bcifile or $bbcfile.bci: $!\n";
  my $fsize = (stat $bcifile)[7];
  my $intsize = 4;
  my $numbytes = $intsize * 2;
  read(BCIFILE, my $buffer, $numbytes) == $numbytes or die "Did not read $numbytes bytes from $bcifile\n";
  my ($bciBlockSize,$numchroms) = unpack "L2", $buffer;
  print STDERR "Read blocksize ($bciBlockSize) and number of contigs ($numchroms) from $bcifile\n" if( $logopt );
  if( $bciBlockSize <= 0 || $chrom > $numchroms )
  {
    close( BCIFILE );
    return 0;
  }
  $numbytes = $numchroms * $intsize;
  read(BCIFILE, $buffer, $numbytes) == $numbytes or die "Did not read $numbytes bytes from $bcifile\n";
  my @bciBlockOffsets = unpack "L[$numchroms]", $buffer;
  # to support large BBC the file offsets need to be converted to long ints, which requires reading the whole block
  $numbytes = $fsize - (2 + $numchroms) * $intsize;
  read(BCIFILE, $buffer, $numbytes) == $numbytes or die "Did not read $numbytes bytes from $bcifile\n";
  my $bciIndexSize = $numbytes >> 2;
  my @bciIndex = unpack "L[$bciIndexSize]", $buffer;
  close(BCIFILE);
  # convert bciIndex to double integers
  my $highWord = 0;
  my @bigints = (($highBit) x $bciIndexSize);
  $bigints[0] = $bciIndex[0];
  for( my $i = 1; $i < $bciIndexSize; ++$i ) {
    $highWord += BIGWORD if( $bciIndex[$i] > 0 && $bciIndex[$i] < $bciIndex[$i-1] );
    $bigints[$i] = $bciIndex[$i] + $highWord;
  }
  @bciIndex = @bigints;
  # find the place to start reading the requested coverage
  my $chrBlockSrt = $bciBlockOffsets[$chrom-1];
  my $blockSrt = $chrBlockSrt + int(($srt_pos-1)/$bciBlockSize);
  my $blockEnd = $chrBlockSrt + int(($end_pos-1)/$bciBlockSize);
  # get the bin range for the end position to find first no 0 coverage region
  while( $blockSrt <= $blockEnd )
  {
    return $bciIndex[$blockSrt] if( $bciIndex[$blockSrt] );
    ++$blockSrt;
  }
  return 0;
}


#!/usr/bin/env perl
if (@ARGV && ($ARGV[0] eq '-h' || $ARGV[0] eq '--help')) {
  print "Usage: vids-rename.pl\n";
  print "Read video filenames from stdin; print mv commands to normalize names (strip resolution, tidy years).\n";
  exit 0;
}
my $VERBOSE = $ENV{VERBOSE} || 0;

sub print_it {
  my ($orig, $pig) = @_;
  
  $pig =~ s/\s*$//;
  $pig =~ s/^\s*//;
  $pig =~ s/\s+(\d{4}-?({\d{4})?)/ ($1)/;
  print("mv '$orig' '$pig'\n") if "$orig" ne "$pig";
}

while(<>) {
  chomp;
  my $orig = $_;
  my $pig = "$orig";
  
  $pig =~ s/1080//g;
  $pig =~ s/720//g;
  $pig =~ s/480//g;
  $pig =~ s/1280(x\d})?//g;
  $pig =~ s/1920(x\d})?//g;
  $pig =~ s/^\s*www(\.\w+)*\W+//;

  next if "$pig" =~ /\.nfo$/i;
  next if "$pig" =~ /\.txt$/i;

  print("# 1 $orig => $pig\n") if $VERBOSE;

  if($pig =~ s/(\(\d{4}\)).*$/$1/) {
    print("# 2 $orig => $pig\n") if $VERBOSE;
    
    print_it($orig, $pig);
    next;
  }

  if($pig =~ /^(.*)\.(\d{4})/) {
    $prefix = $1;
    $year = $2;

    print("# 3 $orig => PREFIX $prefix YEAR $year\n") if $VERBOSE;

	  $prefix =~ s/^(\d+\.)//;
    $prefix =~ s/\b\.\b/ /g;

    print_it($orig, "$prefix ($year)");
    next;
  }

  if($pig =~ s/(\d{4}(\s*\-(\s*\d{4})?)?\s*\)?).*$/$1/) {
    print("# 4 $orig => $pig\n") if $VERBOSE;
    print_it($orig, $pig);
    next;
  }

}


# Tests
# Millennium S01-S03 (1996-)
# www.UIndex.org    -    Hamnet 2025 1080p TS EN-RGB
# Dark Skies 1996-1997 (Complete TV series in MP4 format): => Dark Skies 1996-1997 (Complete TV series in MP4 format)
# Jane.Eyre.1996.1080p.BluRay.H264.AAC-RARBG:
# [TorrentCounter.to].Tumbbad.2018.Hindi.1080p.WEB-DL.x264.[1.5GB].[MP4]
#!/usr/bin/env perl
use strict;
use warnings;

my $VERBOSE = $ENV{VERBOSE} || 0;
my $execute = 1;   # default: perform the renames (mv) in the current directory
my @inputs;

for my $a (@ARGV) {
  if ($a eq '-h' || $a eq '--help') {
    print <<'USAGE';
Usage: vids-rename.pl [-n|--dry-run] [name ...]

Normalize video/folder names (strip resolution, tidy years). Names come from
positional arguments, or from stdin (one per line) when no names are given.

By default the renames are executed (mv) in the current directory. Use
-n/--dry-run to only print the `mv` commands instead of running them. A rename
is skipped when the source is missing or the target already exists.
USAGE
    exit 0;
  } elsif ($a eq '-n' || $a eq '--dry-run') {
    $execute = 0;
  } elsif ($a =~ /^-/) {
    die "vids-rename.pl: unknown option: $a\n";
  } else {
    push @inputs, $a;
  }
}

sub emit {
  my ($orig, $pig) = @_;

  $pig =~ s/\s*$//;
  $pig =~ s/^\s*//;
  $pig =~ s/\s+(\d{4}-?({\d{4})?)/ ($1)/;

  return if "$orig" eq "$pig";

  if (!$execute) {
    print "mv '$orig' '$pig'\n";
    return;
  }
  if (!-e $orig) {
    warn "skip (source missing): $orig\n";
    return;
  }
  if (-e $pig) {
    warn "skip (target exists): $pig\n";
    return;
  }
  if (rename($orig, $pig)) {
    print "renamed: '$orig' -> '$pig'\n";
  } else {
    warn "ERROR renaming '$orig' -> '$pig': $!\n";
  }
}

sub process {
  my ($orig) = @_;
  my $pig = "$orig";

  $pig =~ s/1080//g;
  $pig =~ s/720//g;
  $pig =~ s/480//g;
  $pig =~ s/1280(x\d})?//g;
  $pig =~ s/1920(x\d})?//g;
  $pig =~ s/^\s*www(\.\w+)*\W+//;

  return if "$pig" =~ /\.nfo$/i;
  return if "$pig" =~ /\.txt$/i;

  print("# 1 $orig => $pig\n") if $VERBOSE;

  if ($pig =~ s/(\(\d{4}\)).*$/$1/) {
    print("# 2 $orig => $pig\n") if $VERBOSE;
    emit($orig, $pig);
    return;
  }

  if ($pig =~ /^(.*)\.(\d{4})/) {
    my $prefix = $1;
    my $year   = $2;

    print("# 3 $orig => PREFIX $prefix YEAR $year\n") if $VERBOSE;

    $prefix =~ s/^(\d+\.)//;
    $prefix =~ s/\b\.\b/ /g;

    emit($orig, "$prefix ($year)");
    return;
  }

  if ($pig =~ s/(\d{4}(\s*\-(\s*\d{4})?)?\s*\)?).*$/$1/) {
    print("# 4 $orig => $pig\n") if $VERBOSE;
    emit($orig, $pig);
    return;
  }
}

if (@inputs) {
  for my $line (@inputs) {
    chomp $line;
    process($line);
  }
} else {
  while (<STDIN>) {
    chomp;
    process($_);
  }
}

# Tests
# Millennium S01-S03 (1996-)
# www.UIndex.org    -    Hamnet 2025 1080p TS EN-RGB
# Dark Skies 1996-1997 (Complete TV series in MP4 format): => Dark Skies 1996-1997 (Complete TV series in MP4 format)
# Jane.Eyre.1996.1080p.BluRay.H264.AAC-RARBG:
# [TorrentCounter.to].Tumbbad.2018.Hindi.1080p.WEB-DL.x264.[1.5GB].[MP4]

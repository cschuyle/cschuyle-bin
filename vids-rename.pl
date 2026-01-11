#!/usr/bin/env perl
while(<>) {
  chomp;
  my $orig = $_;
  
  my $pig = $orig;
  
  if($pig =~ s/(\(\d{4}\)).*$/$1/) {
    print("mv '$orig' '$pig'\n");
  }

  if($pig = s/^(.*)\.(\d{4})(\.)?.*$//) {
    $prefix = $1;
    $year = $2;
    
	$prefix =~ s/^(\d+\.)//;
    $prefix =~ s/\b\.\b/ /g;
    print("mv '$orig' '$prefix ($year)'\n");
  }

  if($pig =~ s/(\d{4}).*$/$1/) {
    print("mv '$orig' '$pig'\n");
  }


}

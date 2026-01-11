#!/usr/bin/env perl
while(<>) {
  chomp;
  $orig = $_;
  $pig = $orig;

	if($pig =~ s/(.*?\b)(\d{4})\b.*?(\.(mp4|m4v|avi|mkv|mov))$//i) {
		$new_dir = "$1($2)";
		print("mkdir '$new_dir' && mv '$orig' '$new_dir'\n");
	}

	if($pig = s/(.*)\.(\d{4}).*?(\\.(mp4|m4v|avi|mkv|mov))$//i) {
		$prefix = $1;
		$year = $2;
		$prefix =~ s/\b\.\b/ /g;
		print("mkdir '$prefix ($year)'\n");
	}
}

#!/usr/bin/env perl
use strict;
use warnings;

use Test::More;

my $module = 'StratiphyParallel';
my @subs = qw( 
  run
  init_logging
  get_parameters_from_cmd
  _capture_output
  _exec_cmd
  _dbi_connect
  stratiphy_parallel
  collect_maps
  multi_maps
 
);

use_ok( $module, @subs);

foreach my $sub (@subs) {
    can_ok( $module, $sub);
}

done_testing();

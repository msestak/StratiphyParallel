#!/usr/bin/env perl
package StratiphyParallel;
use 5.010001;
use strict;
use warnings;
use Exporter 'import';
use File::Spec::Functions qw(:ALL);
use Path::Tiny;
use Carp;
use Getopt::Long;
use Pod::Usage;
use Capture::Tiny qw/capture/;
use Data::Dumper;
use Data::Printer;
#use Regexp::Debugger;
use Log::Log4perl;
use File::Find::Rule;
use Config::Std { def_sep => '=' };   #MySQL uses =
use Parallel::ForkManager;
use Excel::Writer::XLSX;
use DBI;
use DBD::mysql;
use Statistics::R;
use List::Util qw/sum/;

our $VERSION = "0.01";

our @EXPORT_OK = qw{
  run
  init_logging
  get_parameters_from_cmd
  _capture_output
  _exec_cmd
  _dbi_connect
  stratiphy_parallel
  collect_maps
  multi_maps

};

#MODULINO - works with debugger too
run() if !caller() or (caller)[0] eq 'DB';

### INTERFACE SUB starting all others ###
# Usage      : main();
# Purpose    : it starts all other subs and entire modulino
# Returns    : nothing
# Parameters : none (argument handling by Getopt::Long)
# Throws     : lots of exceptions from logging
# Comments   : start of entire module
# See Also   : n/a
sub run {
    croak 'main() does not need parameters' unless @_ == 0;

    #first capture parameters to enable verbose flag for logging
    my ($param_href) = get_parameters_from_cmd();

    #preparation of parameters
    my $verbose  = $param_href->{verbose};
    my $quiet    = $param_href->{quiet};
    my @mode     = @{ $param_href->{mode} };

    #start logging for the rest of program (without capturing of parameters)
    init_logging( $verbose, $param_href->{argv} );
    ##########################
    # ... in some function ...
    ##########################
    my $log = Log::Log4perl::get_logger("main");

    # Logs both to Screen and File appender
	#$log->info("This is start of logging for $0");
	#$log->trace("This is example of trace logging for $0");

    #get dump of param_href if -v (verbose) flag is on (for debugging)
    my $param_print = sprintf( p($param_href) ) if $verbose;
    $log->debug( '$param_href = ', "$param_print" ) if $verbose;

    #call write modes (different subs that print different jobs)
    my %dispatch = (
        stratiphy_parallel           => \&stratiphy_parallel,              # run Phylostrat in parallel
		collect_maps                 => \&collect_maps,                    # collect maps in Excel file
		multi_maps                   => \&multi_maps,                      # load and create maps and association maps

    );

    foreach my $mode (@mode) {
        if ( exists $dispatch{$mode} ) {
            $log->info("RUNNING ACTION for mode: ", $mode);

            $dispatch{$mode}->( $param_href );

            $log->info("TIME when finished for: $mode");
        }
        else {
            #complain if mode misspelled or just plain wrong
            $log->logcroak( "Unrecognized mode --mode={$mode} on command line thus aborting");
        }
    }

    return;
}

### INTERNAL UTILITY ###
# Usage      : my ($param_href) = get_parameters_from_cmd();
# Purpose    : processes parameters from command line
# Returns    : $param_href --> hash ref of all command line arguments and files
# Parameters : none -> works by argument handling by Getopt::Long
# Throws     : lots of exceptions from die
# Comments   : works without logger
# See Also   : run()
sub get_parameters_from_cmd {

    #no logger here
	# setup config file location
	my ($volume, $dir_out, $perl_script) = splitpath( $0 );
	$dir_out = rel2abs($dir_out);
    my ($app_name) = $perl_script =~ m{\A(.+)\.(?:.+)\z};
	$app_name = lc $app_name;
    my $config_file = catfile($volume, $dir_out, $app_name . '.cnf' );
	$config_file = canonpath($config_file);

	#read config to setup defaults
	read_config($config_file => my %config);
	#p(%config);
	my $config_ps_href = $config{PS};
	#p($config_ps_href);
	my $config_ti_href = $config{TI};
	#p($config_ti_href);
	my $config_psname_href = $config{PSNAME};

	#push all options into one hash no matter the section
	my %opts;
	foreach my $key (keys %config) {
		# don't expand PS, TI or PSNAME
		next if ( ($key eq 'PS') or ($key eq 'TI') or ($key eq 'PSNAME') );
		# expand all other options
		%opts = (%opts, %{ $config{$key} });
	}

	# put config location to %opts
	$opts{config} = $config_file;

	# put PS and TI section to %opts
	$opts{ps} = $config_ps_href;
	$opts{ti} = $config_ti_href;
	$opts{psname} = $config_psname_href;

	#cli part
	my @arg_copy = @ARGV;
	my (%cli, @mode);
	$cli{quiet} = 0;
	$cli{verbose} = 0;
	$cli{argv} = \@arg_copy;

	#mode, quiet and verbose can only be set on command line
    GetOptions(
        'help|h'        => \$cli{help},
        'man|m'         => \$cli{man},
        'config|cnf=s'  => \$cli{config},
        'in|i=s'        => \$cli{in},
        'infile|if=s'   => \$cli{infile},
        'out|o=s'       => \$cli{out},
        'outfile|of=s'  => \$cli{outfile},

        'term_sub_name|ts=s' => \$cli{term_sub_name},
        'map_sub_name|ms=s'  => \$cli{map_sub_name},
        'expr_file=s'        => \$cli{expr_file},
        'column_list|cl=s'   => \$cli{column_list},

        'relation|r=s'  => \$cli{relation},
        'nodes|no=s'    => \$cli{nodes},
        'names|na=s'    => \$cli{names},
        'max_process|max=i'=> \$cli{max_process},
        'e_value|e=s'   => \$cli{e_value},
        'tax_id|ti=i'   => \$cli{tax_id},

        'host|ho=s'      => \$cli{host},
        'database|d=s'  => \$cli{database},
        'user|u=s'      => \$cli{user},
        'password|p=s'  => \$cli{password},
        'port|po=i'     => \$cli{port},
        'socket|s=s'    => \$cli{socket},

        'mode|mo=s{1,}' => \$cli{mode},       #accepts 1 or more arguments
        'quiet|q'       => \$cli{quiet},      #flag
        'verbose+'      => \$cli{verbose},    #flag
    ) or pod2usage( -verbose => 1 );

	# help and man
	pod2usage( -verbose => 1 ) if $cli{help};
	pod2usage( -verbose => 2 ) if $cli{man};

	#you can specify multiple modes at the same time
	@mode = split( /,/, $cli{mode} );
	$cli{mode} = \@mode;
	die 'No mode specified on command line' unless $cli{mode};   #DIES here if without mode
	
	#if not -q or --quiet print all this (else be quiet)
	if ($cli{quiet} == 0) {
		#print STDERR 'My @ARGV: {', join( "} {", @arg_copy ), '}', "\n";
		#no warnings 'uninitialized';
		#print STDERR "Extra options from config:", Dumper(\%opts);
	
		if ($cli{in}) {
			say 'My input path: ', canonpath($cli{in});
			$cli{in} = rel2abs($cli{in});
			$cli{in} = canonpath($cli{in});
			say "My absolute input path: $cli{in}";
		}
		if ($cli{infile}) {
			say 'My input file: ', canonpath($cli{infile});
			$cli{infile} = rel2abs($cli{infile});
			$cli{infile} = canonpath($cli{infile});
			say "My absolute input file: $cli{infile}";
		}
		if ($cli{out}) {
			say 'My output path: ', canonpath($cli{out});
			$cli{out} = rel2abs($cli{out});
			$cli{out} = canonpath($cli{out});
			say "My absolute output path: $cli{out}";
		}
		if ($cli{outfile}) {
			say 'My outfile: ', canonpath($cli{outfile});
			$cli{outfile} = rel2abs($cli{outfile});
			$cli{outfile} = canonpath($cli{outfile});
			say "My absolute outfile: $cli{outfile}";
		}
	}
	else {
		$cli{verbose} = -1;   #and logging is OFF

		if ($cli{in}) {
			$cli{in} = rel2abs($cli{in});
			$cli{in} = canonpath($cli{in});
		}
		if ($cli{infile}) {
			$cli{infile} = rel2abs($cli{infile});
			$cli{infile} = canonpath($cli{infile});
		}
		if ($cli{out}) {
			$cli{out} = rel2abs($cli{out});
			$cli{out} = canonpath($cli{out});
		}
		if ($cli{outfile}) {
			$cli{outfile} = rel2abs($cli{outfile});
			$cli{outfile} = canonpath($cli{outfile});
		}
	}

    #copy all config opts
	my %all_opts = %opts;
	#update with cli options
	foreach my $key (keys %cli) {
		if ( defined $cli{$key} ) {
			$all_opts{$key} = $cli{$key};
		}
	}

    return ( \%all_opts );
}


### INTERNAL UTILITY ###
# Usage      : init_logging();
# Purpose    : enables Log::Log4perl log() to Screen and File
# Returns    : nothing
# Parameters : verbose flag + copy of parameters from command line
# Throws     : croaks if it receives parameters
# Comments   : used to setup a logging framework
#            : logfile is in same directory and same name as script -pl +log
# See Also   : Log::Log4perl at https://metacpan.org/pod/Log::Log4perl
sub init_logging {
    croak 'init_logging() needs verbose parameter' unless @_ == 2;
    my ( $verbose, $argv_copy ) = @_;

    #create log file in same dir where script is running
	#removes perl script and takes absolute path from rest of path
	my ($volume,$dir_out,$perl_script) = splitpath( $0 );
	#say '$dir_out:', $dir_out;
	$dir_out = rel2abs($dir_out);
	#say '$dir_out:', $dir_out;

    my ($app_name) = $perl_script =~ m{\A(.+)\.(?:.+)\z};   #takes name of the script and removes .pl or .pm or .t
    #say '$app_name:', $app_name;
    my $logfile = catfile( $volume, $dir_out, $app_name . '.log' );    #combines all of above with .log
	#say '$logfile:', $logfile;
	$logfile = canonpath($logfile);
	#say '$logfile:', $logfile;

    #colored output on windows
    my $osname = $^O;
    if ( $osname eq 'MSWin32' ) {
        require Win32::Console::ANSI;                                 #require needs import
        Win32::Console::ANSI->import();
    }

    #enable different levels based on verbose flag
    my $log_level;
    if    ($verbose == 0)  { $log_level = 'INFO';  }
    elsif ($verbose == 1)  { $log_level = 'DEBUG'; }
    elsif ($verbose == 2)  { $log_level = 'TRACE'; }
    elsif ($verbose == -1) { $log_level = 'OFF';   }
	else                   { $log_level = 'INFO';  }

    #levels:
    #TRACE, DEBUG, INFO, WARN, ERROR, FATAL
    ###############################################################################
    #                              Log::Log4perl Conf                             #
    ###############################################################################
    # Configuration in a string ...
    my $conf = qq(
      log4perl.category.main                   = TRACE, Logfile, Screen

	  # Filter range from TRACE up
	  log4perl.filter.MatchTraceUp               = Log::Log4perl::Filter::LevelRange
      log4perl.filter.MatchTraceUp.LevelMin      = TRACE
      log4perl.filter.MatchTraceUp.LevelMax      = FATAL
      log4perl.filter.MatchTraceUp.AcceptOnMatch = true

      # Filter range from $log_level up
      log4perl.filter.MatchLevelUp               = Log::Log4perl::Filter::LevelRange
      log4perl.filter.MatchLevelUp.LevelMin      = $log_level
      log4perl.filter.MatchLevelUp.LevelMax      = FATAL
      log4perl.filter.MatchLevelUp.AcceptOnMatch = true
      
	  # setup of file log
      log4perl.appender.Logfile           = Log::Log4perl::Appender::File
      log4perl.appender.Logfile.filename  = $logfile
      log4perl.appender.Logfile.mode      = append
      log4perl.appender.Logfile.autoflush = 1
      log4perl.appender.Logfile.umask     = 0022
      log4perl.appender.Logfile.header_text = INVOCATION:$0 @$argv_copy
      log4perl.appender.Logfile.layout    = Log::Log4perl::Layout::PatternLayout
      log4perl.appender.Logfile.layout.ConversionPattern = [%d{yyyy/MM/dd HH:mm:ss,SSS}]%5p> %M line:%L==>%m%n
	  log4perl.appender.Logfile.Filter    = MatchTraceUp
      
	  # setup of screen log
      log4perl.appender.Screen            = Log::Log4perl::Appender::ScreenColoredLevels
      log4perl.appender.Screen.stderr     = 1
      log4perl.appender.Screen.layout     = Log::Log4perl::Layout::PatternLayout
      log4perl.appender.Screen.layout.ConversionPattern  = [%d{yyyy/MM/dd HH:mm:ss,SSS}]%5p> %M line:%L==>%m%n
	  log4perl.appender.Screen.Filter     = MatchLevelUp
    );

    # ... passed as a reference to init()
    Log::Log4perl::init( \$conf );

    return;
}

### INTERNAL UTILITY ###
# Usage      : my ($stdout, $stderr, $exit) = _capture_output( $cmd, $param_href );
# Purpose    : accepts command, executes it, captures output and returns it in vars
# Returns    : STDOUT, STDERR and EXIT as vars
# Parameters : ($cmd_to_execute,  $param_href)
# Throws     : nothing
# Comments   : second param is verbose flag (default off)
# See Also   :
sub _capture_output {
    my $log = Log::Log4perl::get_logger("main");
    $log->logdie( '_capture_output() needs a $cmd' ) unless (@_ ==  2 or 1);
    my ($cmd, $param_href) = @_;

    my $verbose = $param_href->{verbose};
    $log->debug(qq|Report: COMMAND is: $cmd|);

    my ( $stdout, $stderr, $exit ) = capture {
        system($cmd );
    };

    if ($verbose == 2) {
        $log->trace( 'STDOUT is: ', "$stdout", "\n", 'STDERR  is: ', "$stderr", "\n", 'EXIT   is: ', "$exit" );
    }

    return  $stdout, $stderr, $exit;
}

### INTERNAL UTILITY ###
# Usage      : _exec_cmd($cmd_git, $param_href, $cmd_info);
# Purpose    : accepts command, executes it and checks for success
# Returns    : prints info
# Parameters : ($cmd_to_execute, $param_href)
# Throws     : 
# Comments   : second param is verbose flag (default off)
# See Also   :
sub _exec_cmd {
    my $log = Log::Log4perl::get_logger("main");
    $log->logdie( '_exec_cmd() needs a $cmd, $param_href and info' ) unless (@_ ==  2 or 3);
	croak( '_exec_cmd() needs a $cmd' ) unless (@_ == 2 or 3);
    my ($cmd, $param_href, $cmd_info) = @_;
	if (!defined $cmd_info) {
		($cmd_info)  = $cmd =~ m/\A(\w+)/;
	}
    my $verbose = $param_href->{verbose};

    my ($stdout, $stderr, $exit) = _capture_output( $cmd, $param_href );
    if ($exit == 0 and $verbose > 1) {
        $log->trace( "$cmd_info success!" );
    }
	else {
        $log->trace( "$cmd_info failed!" );
	}
	return $exit;
}


## INTERNAL UTILITY ###
# Usage      : my $dbh = _dbi_connect( $param_href );
# Purpose    : creates a connection to database
# Returns    : database handle
# Parameters : ( $param_href )
# Throws     : DBI errors and warnings
# Comments   : first part of database chain
# See Also   : DBI and DBD::mysql modules
sub _dbi_connect {
    my $log = Log::Log4perl::get_logger("main");
    $log->logcroak( '_dbi_connect() needs a hash_ref' ) unless @_ == 1;
    my ($param_href) = @_;
	
	#split logic for operating system
	my $osname = $^O;
	my $data_source;
    my $user     = defined $param_href->{user}     ? $param_href->{user}     : 'msandbox';
    my $password = defined $param_href->{password} ? $param_href->{password} : 'msandbox';
	
	if( $osname eq 'MSWin32' ) {	  
		my $host     = defined $param_href->{host}     ? $param_href->{host}     : 'localhost';
    	my $database = defined $param_href->{database} ? $param_href->{database} : 'blastdb';
    	my $port     = defined $param_href->{port}     ? $param_href->{port}     : 3306;
    	my $prepare  = 1;   #server side prepare is ON
		my $use_res  = 0;   #1 doesn't work with selectall_aref (O means it catches in application)

    	$data_source = "DBI:mysql:database=$database;host=$host;port=$port;mysql_server_prepare=$prepare;mysql_use_result=$use_res";
	}
	elsif ( $osname eq 'linux' ) {
		my $host     = defined $param_href->{host}     ? $param_href->{host}     : 'localhost';
    	my $database = defined $param_href->{database} ? $param_href->{database} : 'blastdb';
    	my $port     = defined $param_href->{port}     ? $param_href->{port}     : 3306;
    	my $socket   = defined $param_href->{socket}   ? $param_href->{socket}   : '/var/lib/mysql/mysql.sock';
    	my $prepare  = 1;   #server side prepare is ON
		my $use_res  = 0;   #1 doesn't work with selectall_aref (O means it catches in application)

    	$data_source = "DBI:mysql:database=$database;host=$host;port=$port;mysql_socket=$socket;mysql_server_prepare=$prepare;mysql_use_result=$use_res";
	}
	else {
		$log->error( "Running on unsupported system" );
	}

	my %conn_attrs  = (
        RaiseError         => 1,
        PrintError         => 0,
        AutoCommit         => 1,
        ShowErrorStatement => 1,
    );
    my $dbh = DBI->connect( $data_source, $user, $password, \%conn_attrs );

    $log->trace( 'Report: connected to ', $data_source, ' by dbh ', $dbh );

    return $dbh;
}

### INTERFACE SUB ###
# Usage      : --mode=stratiphy_parallel
# Purpose    : runs PhyloStrat in parallel using fork()
# Returns    : nothing
# Parameters : ( $param_href )
# Throws     : croaks if wrong number of parameters
# Comments   : runs only on tiktaalik (Phylostrat installed)
# See Also   : 
sub stratiphy_parallel {
    my $log = Log::Log4perl::get_logger("main");
    $log->logcroak('stratiphy_parallel() needs a $param_href') unless @_ == 1;
    my ($param_href) = @_;

    my $infile      = $param_href->{infile}      or $log->logcroak('no $infile specified on command line!');
    my $max_process = $param_href->{max_process} or $log->logcroak('no $max_process specified on command line!');
    my $e_value     = $param_href->{e_value}     or $log->logcroak('no $e_value specified on command line!');
	my $tax_id      = $param_href->{tax_id}      or $log->logcroak('no $tax_id specified on command line!');
    my $nodes       = $param_href->{nodes}       or $log->logcroak('no $nodes specified on command line!');
    my $names       = $param_href->{names}       or $log->logcroak('no $names specified on command line!');

	# get infile and outdir
	my $out_dir = path($infile)->parent;
	$log->trace("Report: OUT_DIR:$out_dir");
	my $species = path($infile)->basename;
	$species = substr($species, 0, 2);
	$log->trace("Report: species:$species");

	# split e_values to array to fork on each later
	my ($e_value_start, $e_value_end) = split('-', $e_value);
	my @e_values = $e_value_start .. $e_value_end;
	$log->trace("e_values:@e_values");

	#make hot current filehandle (disable buffering)
	$| = 1;

	# start
	$log->trace("Report: parent PID $$ forking $max_process processes");
	my $pm = Parallel::ForkManager->new($max_process);

	E_VALUE_LOOP:
	foreach my $e_value (@e_values){
		#modify the e-value
		my $real_e_value = '1e-' . $e_value;
	
		#make the fork
		my $pid = $pm->start and next E_VALUE_LOOP;
	
		# run the stratiphy step
		my $map = path($out_dir, $species . $e_value . '.phmap');
		$log->debug("Action: started child for {$map}");
		my $cmd = qq{PhyloStrat -b $infile -n $nodes -t $tax_id -e $real_e_value > $map};
		$log->trace("CMD:$cmd");
		system($cmd) and die "Error: can't stratiphy $infile to $map:$!";
		$log->debug("Report: stratiphy finish:$map");

		# run the AddNames step
		my $map_with_names = path($map . '_names');
		#say "second step: map with names {$map_with_names}";
		my $cmd2 = qq{AddNames.pl -m $map -n $names > $map_with_names};
		$log->trace("CMD:$cmd2");
		system($cmd2) and die "Error: can't add names $names to $map:$!";
		$log->debug("Report: addnames finish:$map_with_names");

		# run the summary step
		my $map_summary = path($map . '_sum');
		#say "second step: map summary {$map_summary}";
		my $cmd3 = qq{MapSummary.pl -m $map_with_names > $map_summary};
		$log->trace("CMD:$cmd3");
		system($cmd3) and die "Error: can't summarize $map_with_names to $map_summary:$!";
		$log->debug("Report: summary finish:$map_summary");
	
		$pm->finish; # Terminates the child process
	}
	$pm->wait_all_children;


    return;
}


### INTERFACE SUB ###
# Usage      : --mode=collect_maps
# Purpose    : creates excel file with multiple maps on one sheet and compares them
# Returns    : nothing
# Parameters : ( $param_href )
# Throws     : croaks for parameters
# Comments   : it works on map summary files created by MapSummary.pl by Robert Bakarić
# See Also   : --mode=stratiphy_parallel which creates maps
sub collect_maps {
	my $log = Log::Log4perl::get_logger("main");
    $log->logcroak ('collect_maps() needs a hash_ref' ) unless @_ == 1;
    my ($param_href ) = @_;
    
	my $in      = $param_href->{in}      or $log->logcroak( 'no $in specified on command line!' );
	my $outfile = $param_href->{outfile} or $log->logcroak( 'no $outfile specified on command line!' );

	# collect map summary files from IN
	my $sorted_maps_aref = _sorted_files_in( $in, 'phmap_sum' );

	# count number of lines in map and extract phylostrata
	my $test_map = $sorted_maps_aref->[0];
	my ($test_phylostrata, $test_tax_id, $test_phylostrata_name) = _test_map($test_map);
	my @test_phylostrata = @$test_phylostrata;
	my $lines = @test_phylostrata;
	my @test_tax_id = @$test_tax_id;
	my @test_phylostrata_name = @$test_phylostrata_name;

	# calculate offsets in comparison to first map (1e-3)
	my $diff_start = 3;                      #third line from top
	my $diff_end   = $lines + $diff_start;   #num of lines in file + 3

    # Create a new Excel workbook
	my $excel_href = _create_excel_for_collect_maps($outfile);

	# create hash to hold all coordinates of start - end lines holding data
	my %plot_hash;

    #add a counter for different files and lines
    state $line_counter = 0;

	# run for each map
	foreach my $map (@$sorted_maps_aref) {

		#skip non-uniform maps
		next if $map =~ /2014|2015|2016|2017/;

		# Add a caption to each worksheet (with name of map)
		my $map_sum = path($map)->basename;
		my ($map_name) = $map_sum =~ m/\A([^\.]+)\./;
		$map_name .= '_map';

    	$excel_href->{sheet}->write( $line_counter, 0, $map_name, $excel_href->{red_bold} );
    	$line_counter++;

		# here comes header
		$excel_href->{sheet}->write( $line_counter, 0,  'phylostrata',      $excel_href->{black_bold} );
    	$excel_href->{sheet}->write( $line_counter, 1,  'tax_id',           $excel_href->{black_bold} );
    	$excel_href->{sheet}->write( $line_counter, 2,  'phylostrata_name', $excel_href->{black_bold} );
    	$excel_href->{sheet}->write( $line_counter, 3,  'genes',            $excel_href->{black_bold} );
    	$excel_href->{sheet}->write( $line_counter, 4,  '% of genes',       $excel_href->{black_bold} );
    	$excel_href->{sheet}->write( $line_counter, 5,  'diff in num',      $excel_href->{black_bold} );
    	$excel_href->{sheet}->write( $line_counter, 6,  'diff in %',        $excel_href->{black_bold} );

    	#using absolute notation (0,0 == A1)
    	$line_counter++;
		my $sum_start = $line_counter + 1;   # for SUM genes

		# read a map summary file and print it to Excel
		{ 
			local $. = 0;
			my $local_cnt = 0;
			my %HoA_columns_as_arrays;
			my @col_names = ('phylostrata', 'tax_id', 'phylostrata_name', 'genes', '% of genes');
			open (my $map_fh, "<", $map) or $log->logdie("Error: can't open $map for reading:$!");
			while (<$map_fh>) {
				# split rows on tab
				chomp;
				my @columns = split "\t", $_;
				foreach my $i (0 .. $#columns) {
					push @{ $HoA_columns_as_arrays{ $col_names[$i] } }, $columns[$i];
				}
		
				$local_cnt++;
				#say "local_cnt:$local_cnt";
				my $tmp_cnt_here = $line_counter + $local_cnt;
				#say $tmp_cnt_here;
				my $tmp_cnt_diff = $diff_start + $local_cnt -1 ;
				#say $tmp_cnt_diff;
				#$excel_href->{sheet}->write_formula( $tmp_cnt_here - 1, 5, "{=D$tmp_cnt_here - D$tmp_cnt_diff}" );
				$excel_href->{sheet}->write_formula( $tmp_cnt_here - 1, 6, "{=E$tmp_cnt_here - E$tmp_cnt_diff}", $excel_href->{perc} );
			}   #end while reading file

			my @phylostrata = @{ $HoA_columns_as_arrays{ $col_names[0] } };
			my @tax_id = @{ $HoA_columns_as_arrays{ $col_names[1] } };
			my @phylostrata_name = @{ $HoA_columns_as_arrays{ $col_names[2] } };
			my @genes = @{ $HoA_columns_as_arrays{ $col_names[3] } };
			my @perc_of_genes = @{ $HoA_columns_as_arrays{ $col_names[4] } };

			#check if phylostrata match
			my $r = _comp_arrays(\(@test_phylostrata, @phylostrata));
			if ($r) {
				$log->trace("Report: phylostrata match for $map");

				$line_counter++;   #relative notation
				$excel_href->{sheet}->write_col( "A$line_counter", \@phylostrata );
				$excel_href->{sheet}->write_col( "B$line_counter", \@tax_id );
				$excel_href->{sheet}->write_col( "C$line_counter", \@phylostrata_name );
				$excel_href->{sheet}->write_col( "D$line_counter", \@genes );
				$excel_href->{sheet}->write_col( "E$line_counter", \@perc_of_genes );
				my $end = $line_counter + @phylostrata;
				$excel_href->{sheet}->write_array_formula( "F$line_counter:F$end",    "{=(D$line_counter:D$end - D$diff_start:D$diff_end)}" );
				#$excel_href->{sheet}->write_array_formula( "G$line_counter:G$end",    "{=(E$line_counter:E$end - E$diff_start:E$diff_end)}", $format_perc );
				#print Dumper(\%HoA_columns_as_arrays);
			}
			else {
				$log->debug("Report: phylostrata DO NOT match for $map");

				#get modified phylostrata and missing indices
				my ($new_phylostrata_aref, $empty_index_aref) = _add_missing_phylostrata(\(@test_phylostrata, @phylostrata));
				#say Dumper($new_phylostrata_aref);
				#say Dumper($empty_index_aref);

				#increase all other arrays/columns
				foreach my $index (@$empty_index_aref) {
					splice(@tax_id, $index, 0, $test_tax_id[$index]);
					splice(@phylostrata_name, $index, 0, $test_phylostrata_name[$index]);
					splice(@genes, $index, 0, 0);
					splice(@perc_of_genes, $index, 0, '0.00%');
				}

				#print to Excel
				$line_counter++;   #relative notation
				$excel_href->{sheet}->write_col( "A$line_counter", $new_phylostrata_aref );
				$excel_href->{sheet}->write_col( "B$line_counter", \@tax_id );
				$excel_href->{sheet}->write_col( "C$line_counter", \@phylostrata_name );
				$excel_href->{sheet}->write_col( "D$line_counter", \@genes );
				#$excel_href->{sheet}->write_col( "E$line_counter", \@perc_of_genes );
				my $end = $line_counter + @$new_phylostrata_aref;
				$excel_href->{sheet}->write_array_formula( "F$line_counter:F$end",    "{=(D$line_counter:D$end - D$diff_start:D$diff_end)}" );

				#increase line_counter for number of indexes
				$line_counter += scalar @$empty_index_aref;
			}
	
			# calculate sum of genes
			$line_counter += $. - 1;  # for length of file
			my $sum_end = $line_counter;
			$excel_href->{sheet}->write_formula( $line_counter, 3, "{=SUM(D$sum_start:D$sum_end)}" );   #curly braces to write result to Excel

			# write percentage (needed for chart)
			my $end = $sum_end + 1;
			foreach my $i ($sum_start .. $sum_end) {
				$excel_href->{sheet}->write_formula( "E$i", "{=D$i/D$end}", $excel_href->{perc} );
			}

			# fill %plot_hash with coordinates of percentages for summary chart
			$plot_hash{$map_name} = [$sum_start, $sum_end];

			# write positive genes in green and negative in red
			# Write a conditional format over a range.
			$excel_href->{sheet}->conditional_formatting( "F$sum_start:F$sum_end",
			    {
			        type     => 'cell',
			        criteria => '>',
			        value    => 0,
			        format   => $excel_href->{green},
			    }
			);
 
			# Write another conditional format over the same range.
			$excel_href->{sheet}->conditional_formatting( "F$sum_start:F$sum_end",
			    {
			        type     => 'cell',
			        criteria => '<',
			        value    => 0,
			        format   => $excel_href->{red},
			    }
			);
	
			# write conditional format for percentage
			$excel_href->{sheet}->conditional_formatting( "G$sum_start:G$sum_end",
			    {
			        type     => 'cell',
			        criteria => '>',
			        value    => 0,
			        format   => $excel_href->{green},
			    }
			);

			# insert chart for each map near maps
			_add_bare_map_chart( { map => $map_name, workbook => $excel_href->{workbook}, sheet => $excel_href->{sheet}, sheet_name => "MAPS", start => $sum_start, end => $sum_end } );
	


			# make space for next map
			$line_counter += 2;      # +2 for next map name
	
		}   #end local $.
	}   # end foreach map

	# create chart with all maps on it
	_chart_all_for_collect_maps( { plot =>\%plot_hash, workbook => $excel_href->{workbook}, sheet_name => "MAPS" } );

	$excel_href->{workbook}->close() or $log->logdie( "Error closing Excel file: $!" );

	return;
}


### INTERNAL UTILITY ###
# Usage      : my ($test_phylostrata, $test_tax_id, $test_phylostrata_name) = _test_map($test_map);
# Purpose    : analyzes test map for length
# Returns    : @phylostrata
# Parameters : $test_map
# Throws     : croaks if wrong number of parameters
# Comments   : helper
# See Also   : collect_maps()
sub _test_map {
    my $log = Log::Log4perl::get_logger("main");
    $log->logcroak('_test_map() needs a $test_map') unless @_ == 1;
    my ($test_map) = @_;

	# count number of lines in map and extract phylostrata
	my @col_names = ('phylostrata', 'tax_id', 'phylostrata_name', 'genes', '% of genes');
	my %HoA_columns_as_arrays;   #hash of arrays to hold columns
	open (my $test_fh, "<", $test_map) or $log->logdie("Error: can't open $test_map for reading:$!");
	while (<$test_fh>) {
		# split rows on tab
		chomp;
		my @columns = split "\t", $_;
		foreach my $i (0 .. $#columns) {
			push @{ $HoA_columns_as_arrays{ $col_names[$i] } }, $columns[$i];
		}
	}
	my @test_phylostrata = @{ $HoA_columns_as_arrays{ $col_names[0] } };
	my @test_tax_id = @{ $HoA_columns_as_arrays{ $col_names[1] } };
	my @test_phylostrata_name = @{ $HoA_columns_as_arrays{ $col_names[2] } };
	my $lines = @test_phylostrata;	
	$log->info("Report: found $lines lines in $test_map for offsets");
	#print Dumper(\%HoA_columns_as_arrays);
	#say "@phylostrata";
	#
    return \@test_phylostrata, \@test_tax_id, \@test_phylostrata_name;
}


### INTERNAL UTILITY ###
# Usage      : my $r = _comp_arrays(\(@x, @y));
# Purpose    : compare 2 arrays if equal in length and content
# Returns    : nothing
# Parameters : 2 array refs
# Throws     : croaks if wrong number of parameters
# Comments   : helper for
#            : by Hynek -Pichi- Vychodil http://stackoverflow.com/questions/1609467/in-perl-is-there-a-built-in-way-to-compare-two-arrays-for-equality
# See Also   : collect_maps()
sub _comp_arrays {
    my ($xref, $yref) = @_;
    return unless  @$xref == @$yref;

    my $i;
    for my $e (@$xref) {
        return unless $e eq $yref->[$i++];
    }
    return 1;
}


### INTERNAL UTILITY ###
# Usage      : my (\@new_phylostrata, \@empty_index) = _add_missing_phylostrata(\(@x, @y));
# Purpose    : compare 2 arrays if equal in length and content
# Returns    : nothing
# Parameters : 2 array refs
# Throws     : croaks if wrong number of parameters
# Comments   : helper for
#            : by Hynek -Pichi- Vychodil http://stackoverflow.com/questions/1609467/in-perl-is-there-a-built-in-way-to-compare-two-arrays-for-equality
# See Also   : collect_maps()
sub _add_missing_phylostrata {
    my ($test_ref, $yref) = @_;

	my @new_phylostrata;           #returning phylostrata
	my @empty_index;               #returning indices

	my $i = 0;                 #iterator (and index)
	for my $e (@$test_ref) {
		if ($e eq $yref->[$i]) {
			push @new_phylostrata, $yref->[$i];
			#say "NEW_ph:@new_phylostrata";
		}
		else {
			push @new_phylostrata, $e;
			#say "NEW_ph_add:@new_phylostrata";
			push @empty_index, $i;
			#say "INDEX:@empty_index";
			$i--;             #because of mismatch between indices
		}
		$i++;
	}

    return \@new_phylostrata, \@empty_index;
}


### INTERFACE SUB ###
# Usage      : --mode=multi_maps NOT WORKING
# Purpose    : load and create maps and association maps for multiple e_values and one term
# Returns    : nothing
# Parameters : $param_href
# Throws     : croaks if wrong number of parameters
# Comments   : writes to Excel file
# See Also   : 
sub multi_maps2 {
    my $log = Log::Log4perl::get_logger("main");
    $log->logcroak('multi_maps() needs a $param_href') unless @_ == 1;
    my ($param_href) = @_;

	my $out      = $param_href->{out}      or $log->logcroak('no $out specified on command line!');
	my $in       = $param_href->{in}       or $log->logcroak( 'no $in specified on command line!' );
	my $outfile  = $param_href->{outfile}  or $log->logcroak( 'no $outfile specified on command line!' );
	my $infile   = $param_href->{infile}   or $log->logcroak( 'no $infile specified on command line!' );
	my $relation = $param_href->{relation} or $log->logcroak( 'no $relation specified on command line!' );
	$relation = path($relation)->absolute;

	# collect maps from IN
	my $sorted_maps_aref = _sorted_files_in( $in, 'phmap_names' );

	# get new handle
    my $dbh = _dbi_connect($param_href);

	# create new Excel workbook that will hold calculations
	my ($workbook, $log_odds_sheet, $entropy_sheet, $black_bold, $red_bold) = _create_excel($outfile, $infile);

	# create hash to hold all coordinates of start - end lines holding data
	my %plot_hash;

	# create hash to hold all real_log_odds and fdr_p_values for entropy analysis (information)
	my %entropy_hash;
	my $calc_info_href;

	my $term_tbl;   # name needed outside loop
	# foreach map create and load into database (general reusable)
	foreach my $map (@$sorted_maps_aref) {

		# import map
		my $map_tbl = _import_map($in, $map, $dbh);
	
		# import one term (specific part)
		$term_tbl = _import_term($infile, $dbh, $relation);
	
		# connect term
		_update_term_with_map($term_tbl, $map_tbl, $dbh);
	
		# calculate hypergeometric test and print to Excel
		my ($start_line, $end_line, $phylo_log_cnt_href, $real_log_odd_aref, $fdr_p_value_aref) = _hypergeometric_test( { term => $term_tbl, map => $map_tbl, sheet => $log_odds_sheet, black_bold => $black_bold, red_bold => $red_bold, %{$param_href} } );
		say "$start_line-$end_line";

		# collect all coordinates of start and end lines to hash
		# series name is key, coordinates are value (aref)
		$plot_hash{"${map_tbl}_x_$term_tbl"} = [$start_line, $end_line];

		# collect real_log_odds and FDR_P_value for information calculation
		$entropy_hash{"${map_tbl}_x_$term_tbl"} = [$real_log_odd_aref, $fdr_p_value_aref];

		# hash ref for _calculate_information() need to persist after loop
		$calc_info_href = $phylo_log_cnt_href;

		# insert chart for each map-term combination near maps
		_add_chart( { term => $term_tbl, map => $map_tbl, workbook => $workbook, sheet => $log_odds_sheet, sheet_name => "hyper_$term_tbl", start => $start_line, end => $end_line } );
	
	}   # end foreach map

	# create chart with all maps on it
	_chart_all( { plot =>\%plot_hash, workbook => $workbook, sheet_name => "hyper_$term_tbl", term => $term_tbl } );

	# calculate entropy here using %entropy_hash
	_calculate_information(  { entropy =>\%entropy_hash, phylo_cnt => $calc_info_href, workbook => $workbook, sheet => $entropy_sheet, black_bold => $black_bold, red_bold => $red_bold } );

	# close the Excel file
	$workbook->close() or $log->logdie( "Error closing Excel file: $!" );

	$dbh->disconnect;

    return;
}


### INTERNAL UTILITY ###
# Usage      : my $map_tbl = _import_map( { map_file => $map, dbh => $dbh, %{$param_href} } );
# Purpose    : imports map with header
# Returns    : name of map table
# Parameters : input dir, full path to map file and database handle
# Throws     : croaks if wrong number of parameters
# Comments   : creates temp files without header for LOAD data infile
# See Also   : --mode=multi_maps
sub _import_map {
    my $log = Log::Log4perl::get_logger("main");
    $log->logcroak('_import_map() needs {$map_href}') unless @_ == 1;
    my ($map_href) = @_;

	# get name of map table
	my $map_tbl = path($map_href->{map_file})->basename;
	($map_tbl) = $map_tbl =~ m/\A([^\.]+)\.phmap_names\z/;
	$map_tbl   .= '_map';

    # create map table
    my $create_query = sprintf( qq{
	CREATE TABLE IF NOT EXISTS %s (
	prot_id VARCHAR(40) NOT NULL,
	phylostrata TINYINT UNSIGNED NOT NULL,
	ti INT UNSIGNED NOT NULL,
	species_name VARCHAR(200) NULL,
	PRIMARY KEY(prot_id),
	KEY(phylostrata),
	KEY(ti),
	KEY(species_name)
    ) }, $map_href->{dbh}->quote_identifier($map_tbl) );
	_create_table( { table_name => $map_tbl, dbh => $map_href->{dbh}, query => $create_query } );
	$log->trace("Report: $create_query");

	# create tmp filename
	#my $temp_map = Path::Tiny->tempfile( TEMPLATE => "XXXXXXXX", SUFFIX => '.map' );
	my $temp_map = path($map_href->{in}, $map_tbl);
	open (my $tmp_fh, ">", $temp_map) or $log->logdie("Error: can't open map $temp_map for writing:$!");

	# need to skip header
	open (my $map_fh, "<", $map_href->{map_file}) or $log->logdie("Error: can't open map $map_href->{map_file} for reading:$!");
	while (<$map_fh>) {
		chomp;
	
		# check if record (ignore header)
		next if !/\A(?:[^\t]+)\t(?:[^\t]+)\t(?:[^\t]+)\t(?:[^\t]+)\z/;
	
		my ($prot_id, $ps, $ti, $ps_name) = split "\t", $_;

		# this is needed because psname can be short without {cellular_organisms : Eukaryota}
		my $psname_short;
		if ($ps_name =~ /:/) {
			(undef, $psname_short) = split ' : ', $ps_name;
		}
		else {
			$psname_short = $ps_name;
		}

		# update map with new phylostrata (shorter phylogeny)
		my $ps_new;
		if ( exists $map_href->{ps}->{$ps} ) {
			$ps_new = $map_href->{ps}->{$ps};
			#say "LINE:$.\tPS_INFILE:$ps\tPS_NEW:$ps_new";
			$ps = $ps_new;
		}

		# update map with new tax_id (shorter phylogeny)
		my $ti_new;
		if ( exists $map_href->{ti}->{$ti} ) {
			$ti_new = $map_href->{ti}->{$ti};
			#say "LINE:$.\tTI_INFILE:$ti\tTI_NEW:$ti_new";
			$ti = $ti_new;
		}

		# update map with new phylostrata name (shorter phylogeny)
		my $psname_new;
		if ( exists $map_href->{psname}->{$psname_short} ) {
			$psname_new = $map_href->{psname}->{$psname_short};
			#say "LINE:$.\tPS_REAL_NAME:$psname_short\tPSNAME_NEW:$psname_new";
			$psname_short = $psname_new;
		}

		# print to tmp map file
		say {$tmp_fh} "$prot_id\t$ps\t$ti\t$psname_short";

	}   # end while

	# explicit close needed else it can break
	close $tmp_fh;

	# load tmp map file without header
    my $load_query = qq{
    LOAD DATA INFILE '$temp_map'
    INTO TABLE $map_tbl } . q{ FIELDS TERMINATED BY '\t'
    LINES TERMINATED BY '\n'
    };
	$log->trace("Report: $load_query");
	my $rows;
    eval { $rows = $map_href->{dbh}->do( $load_query ) };
	$log->error( "Action: loading into table $map_tbl failed: $@" ) if $@;
	$log->debug( "Action: table $map_tbl inserted $rows rows!" ) unless $@;

	# unlink tmp map file
	unlink $temp_map and $log->trace("Action: $temp_map unlinked");

    return $map_tbl;
}


### INTERNAL UTILITY ###
# Usage      : my $term_tbl = _import_term($infile, $dbh, $relation);
# Purpose    : imports association term into MySQL
# Returns    : name of term table
# Parameters : input file and database handle
# Throws     : croaks if wrong number of parameters
# Comments   : 
# See Also   : --mode=multi_maps
sub _import_term {
    my $log = Log::Log4perl::get_logger("main");
    $log->logcroak('_import_term() needs {$infile, $dbh, $relation}') unless @_ == 3;
    my ($infile, $dbh, $relation) = @_;

	# get name of term table
	my $term_tbl = path($infile)->basename;
	($term_tbl) = $term_tbl =~ m/\A([^\.]+)\.(.+)\z/;
	$term_tbl   .= '_term';

    # create term table
    my $create_query = sprintf( qq{
	CREATE TABLE %s (
	gene_name VARCHAR(20) NOT NULL,
	gene_id VARCHAR(20) NOT NULL,
	prot_id VARCHAR(20) NULL,
	phylostrata TINYINT UNSIGNED NULL,
	ti INT UNSIGNED NULL,
	species_name VARCHAR(200) NULL,
	extra MEDIUMTEXT NULL,
	PRIMARY KEY(gene_id),
	KEY(prot_id)
    ) }, $dbh->quote_identifier($term_tbl) );
	_create_table( { table_name => $term_tbl, dbh => $dbh, query => $create_query } );
	$log->trace("Report: $create_query");

	# load data infile (needs column list or empty)
	my $column_list = '(gene_name, gene_id)';
	_load_table_into($term_tbl, $infile, $dbh, $column_list);

	# load and connect to ensembl_relation_table
	_connect_to_relation($term_tbl, $dbh, $relation);

    return $term_tbl;
}


### INTERNAL UTILITY ###
# Usage      : my $sorted_maps_aref = _sorted_files_in( $in, $file_ext );
# Purpose    : it sorts file names (absolute paths) based on number before dot
# Returns    : array of sorted files
# Parameters : input directory and file extension
# Throws     : croaks if wrong number of parameters
# Comments   : it ignore numbers in path only before dot is important one
# See Also   : --mode=multi_maps
sub _sorted_files_in {
    my $log = Log::Log4perl::get_logger("main");
    $log->logcroak('_sorted_files_in() needs $in, $file_ext') unless @_ == 2;
    my ($in, $file_ext) = @_;

	# set glob and regex for later
	my $glob = '*.' . "$file_ext";
	my $regex = qr/\A(?:.+?)(\d+)\.$file_ext\z/;

	# collect files
	my @files = File::Find::Rule->file()
                                ->name( $glob )
                                ->in( $in );

	# sort maps and print them out
	my @sorted_files =
	map { $_->[0] }                 # returns back to file path format
    sort { $a->[1] <=> $b->[1] }    # compares numbers at second place in aref
    map { [ $_, /$regex/ ] }        # puts number at second place of aref (// around regex is needed becase this is matching on $_)
    @files;
    $log->trace( 'Report: files in input directory sorted: ', "\n", join("\n", @sorted_files) );

    return \@sorted_files;
}


### INTERNAL UTILITY ###
# Usage      : _create_table( { table_name => $table_info, dbh => $dbh, query => $create_query } );
# Purpose    : it drops and recreates table
# Returns    : nothing
# Parameters : hash_ref of table_name, dbh and query
# Throws     : errors if it fails
# Comments   : 
# See Also   : 
sub _create_table {
    my $log = Log::Log4perl::get_logger("main");
    $log->logcroak('_create_table() needs a $param_href') unless @_ == 1;
    my ($param_href) = @_;

    my $table_name   = $param_href->{table_name} or $log->logcroak('no $table_name sent to _create_table()!');
    my $dbh          = $param_href->{dbh}        or $log->logcroak('no $dbh sent to _create_table()!');
    my $create_query = $param_href->{query}      or $log->logcroak('no $query sent to _create_table()!');

	#create table in database specified in connection
    my $drop_query = sprintf( qq{
    DROP TABLE IF EXISTS %s
    }, $dbh->quote_identifier($table_name) );
    eval { $dbh->do($drop_query) };
    $log->error("Action: dropping $table_name failed: $@") if $@;
    $log->trace("Action: $table_name dropped successfully!") unless $@;

    eval { $dbh->do($create_query) };
    $log->error( "Action: creating $table_name failed: $@" ) if $@;
    $log->trace( "Action: $table_name created successfully!" ) unless $@;

    return;
}


### INTERNAL UTILITY ###
# Usage      : _load_table_into($tbl_name, $infile, $dbh, $column_list);
# Purpose    : LOAD DATA INFILE of $infile into $tbl_name
# Returns    : nothing
# Parameters : ($tbl_name, $infile, $dbh)
# Throws     : croaks if wrong number of parameters
# Comments   : $column_list can be empty
# See Also   : 
sub _load_table_into {
    my $log = Log::Log4perl::get_logger("main");
    $log->logcroak('_load_table_into() needs {$tbl_name, $infile, $dbh + opt. $column_list}') unless @_ == 3 or 4;
    my ($tbl_name, $infile, $dbh, $column_list) = @_;
	$column_list //= '';

	# load query
    my $load_query = qq{
    LOAD DATA INFILE '$infile'
    INTO TABLE $tbl_name } . q{ FIELDS TERMINATED BY '\t'
    LINES TERMINATED BY '\n' }
	. '(' . $column_list . ')';
	$log->trace("Report: $load_query");

	# report number of rows inserted
	my $rows;
    eval { $rows = $dbh->do( $load_query ) };
	$log->error( "Action: loading into table $tbl_name failed: $@" ) if $@;
	$log->debug( "Action: table $tbl_name inserted $rows rows!" ) unless $@;

    return;
}


### INTERNAL UTILITY ###
# Usage      : _connect_to_relation($term_tbl, $dbh, $relation);
# Purpose    : connects term table to relation table (to get prot ids)
# Returns    : nothing
# Parameters : $term_tbl, database handle and relation file path
# Throws     : croaks if wrong number of parameters
# Comments   : relation file location is used here
# See Also   : _import_term() which calls it
sub _connect_to_relation {
    my $log = Log::Log4perl::get_logger("main");
    $log->logcroak('_connect_to_relation() needs {$term_tbl, $dbh, $relation}') unless @_ == 3;
    my ($term_tbl, $dbh, $relation) = @_;

	# set name of relation table
	my $rel_tbl = path($relation)->basename;
	($rel_tbl) = $rel_tbl =~ m/\A([^\.]+)\.(.+)\z/;
	$rel_tbl   .= '_rel';

	# check for existence of relation table
	if ( _table_exists( $dbh, $rel_tbl) ) {
		#print "it's there!\n";
	}
	else {
		# create relation table
	    my $create_query = sprintf( qq{
		CREATE TABLE %s (
		prot_id VARCHAR(20) NULL,
		gene_id VARCHAR(20) NOT NULL,
		transcript_id VARCHAR(20) NOT NULL,
		aaseq MEDIUMTEXT NOT NULL,
		PRIMARY KEY(prot_id),
		KEY(gene_id)
	    ) }, $dbh->quote_identifier($rel_tbl) );
		_create_table( { table_name => $rel_tbl, dbh => $dbh, query => $create_query } );
		$log->trace("Report: $create_query");
	
		# load data infile (needs column list or empty)
		#my $column_list = '(gene_name, gene_id)';
		_load_table_into($rel_tbl, $relation, $dbh);
	}

	# update term table with gene_id
	my $update_q = sprintf( qq{
	UPDATE %s AS term
	INNER JOIN %s AS rel ON term.gene_id = rel.gene_id
	SET term.prot_id = rel.prot_id
	}, $dbh->quote_identifier($term_tbl), $dbh->quote_identifier($rel_tbl) );

	# report number of rows updated
	my $rows;
    eval { $rows = $dbh->do( $update_q ) };
	$log->error( "Action: updating table $term_tbl failed: $@" ) if $@;
	$log->debug( "Action: table $term_tbl updated $rows rows!" ) unless $@;

    return;
}


### INTERNAL UTILITY ###
# Usage      : _update_term_with_map($term_tbl, $map_tbl, $dbh);
# Purpose    : updates term table with phylostrata, ti and ps_name
# Returns    : nothing
# Parameters : names of tables and database handle
# Throws     : croaks if wrong number of parameters
# Comments   : 
# See Also   : --mode=multi_maps
sub _update_term_with_map {
    my $log = Log::Log4perl::get_logger("main");
    $log->logcroak('_update_term_with_map() needs {$term_tbl, $map_tbl, $dbh}') unless @_ == 3;
    my ($term_tbl, $map_tbl, $dbh) = @_;

	# update term table with map
	my $update_q = sprintf( qq{
	UPDATE %s AS term
	INNER JOIN %s AS map ON map.prot_id = term.prot_id
	SET term.phylostrata = map.phylostrata, term.ti= map.ti, term.species_name = map.species_name
	}, $dbh->quote_identifier($term_tbl), $dbh->quote_identifier($map_tbl) );
	$log->trace("Report: $update_q");

	# report number of rows updated
	my $rows;
    eval { $rows = $dbh->do( $update_q ) };
	$log->error( "Action: updating table $term_tbl failed: $@" ) if $@;
	$log->debug( "Action: table $term_tbl updated $rows rows!" ) unless $@;

	# delete term table where empty phylostrata
	my $del_q = sprintf( qq{
	DELETE term FROM %s AS term
	WHERE phylostrata IS NULL
	}, $dbh->quote_identifier($term_tbl) );

	# report number of rows updated
	my $rows_del;
    eval { $rows_del = $dbh->do( $del_q ) };
	$log->error( "Action: deleting table $term_tbl failed: $@" ) if $@;
	$log->debug( "Action: deleted $rows_del rows from table $term_tbl!" ) unless $@;

    return;
}


### CLASS METHOD/INSTANCE METHOD/INTERFACE SUB/INTERNAL UTILITY ###
# Usage      : _table_exists( $dbh, $tbl_name)
# Purpose    : checks for existence of table
# Returns    : 1 if true 0 if false
# Parameters : database handle and table name
# Throws     : croaks if wrong number of parameters
# Comments   : modified from DBI recipies
# See Also   : 
sub _table_exists {
    my $log = Log::Log4perl::get_logger("main");
    $log->logcroak('_table_exists() needs {$dbh, $tbl_name}') unless @_ == 2;
    my ($dbh, $table) = @_;

    my @tables = $dbh->tables('','','','TABLE');
    if (@tables) {
        for (@tables) {
            next unless $_;
            return 1 if $_ =~ /$table/;
        }
    }
    else {
        eval {
            local $dbh->{PrintError} = 0;
            local $dbh->{RaiseError} = 1;
            $dbh->do(qq{SELECT * FROM $table WHERE 1 = 0 });
        };
        return 1 unless $@;
    }
    return 0;
}


## INTERNAL UTILITY ###
# Usage      : _calculate_in_R( $r_href );
# Purpose    : calculates hypergeometric test in R
# Returns    : href with calculated values
# Parameters : input values for quant, hit, sample and total
# Throws     : 
# Comments   : 
# See Also   :
sub _calculate_in_R {
    my $log = Log::Log4perl::get_logger("main");
    $log->logcroak( '_calculate_in_R() needs a hash_ref' ) unless @_ == 1;
    my ($param_href) = @_;

    #preparation of parameters (extract arefs from href where values are arefs)
    my $phylostrata_aref = $param_href->{phylo};
    my $func_term_aref   = $param_href->{term};
    my $quant_aref       = $param_href->{quant};
    my $sample_aref      = $param_href->{sample};
    my $hit_aref         = $param_href->{hit};
    my $total_aref       = $param_href->{total};
    my $out              = $param_href->{out};   #dereferences only outer hashref

    #start with R block
    # Create a communication bridge with R and start R
    my $R = Statistics::R->new() and $log->trace("Report: connection to R opened");

    #run a command in R
    #first set working directory and check it
    my $cwd_before = $R->get('getwd()');
    $log->trace( 'Report: this is directory before:  ', "$cwd_before" );
	my $set_wd = <<"SETWD";
	setwd("$out")
SETWD
    $R->run($set_wd);
    my $cwd_set = $R->get('getwd()');
    $log->trace( 'Report: working directory: ', "$cwd_set" );

    #set a list in R (accepts array_ref and returns array_ref)
    $R->set( 'phylostrata', $phylostrata_aref );
    $R->set( 'func_term',   $func_term_aref );
    $R->set( 'quant',       $quant_aref );
    $R->set( 'sample',      $sample_aref );
    $R->set( 'hit',         $hit_aref );
    $R->set( 'total',       $total_aref );

    my $printed_phylostrata_ref = $R->get('phylostrata');
    $log->trace( 'Returned phylostrata from R:', "@{$printed_phylostrata_ref}" );

    # Here-doc with multiple R commands:
    # first combine arrays into data.frame
    # log by default means ln in R
    my $cmds_combine_dataframe = <<'COMBINE';
    dataset <- cbind.data.frame(phylostrata, func_term, quant, sample, hit, total)
    odds_sample <-quant / (sample - quant)
    odds_rest <- (hit - quant) / (total - hit - sample + quant)
    real_log_odds <- log(odds_sample/odds_rest)
    dataset <- cbind.data.frame(dataset, odds_sample, odds_rest, real_log_odds)
COMBINE
    my $combine_exec = $R->run($cmds_combine_dataframe);
	$log->trace('Dataframe combined in R');

    #hypergeometric calculation
    my $cmds_hyper_exec = <<'HYPER';
    CDFHyper = phyper(dataset$quant, dataset$hit, dataset$total - dataset$hit, dataset$sample)
    PDFHyper = dhyper(dataset$quant, dataset$hit, dataset$total - dataset$hit, dataset$sample)
    CDFHyperOver = (1 - CDFHyper) + PDFHyper
    raw_p_value = pmin(CDFHyper, CDFHyperOver)*2
    dataset = cbind.data.frame(dataset, CDFHyper, CDFHyperOver, raw_p_value)
HYPER
    my $hyper_exec = $R->run($cmds_hyper_exec);
	$log->trace('Hypergeometric test calculated in R');

    #calculate values for mapping
    #sort by raw_p_value to calculate the FDR
    my $cmds_fdr = <<'FDR';
    dataset$raw_p_value_map = ifelse (dataset$raw_p_value < 0.001, "<0.001", ifelse(dataset$raw_p_value < 0.01, "<0.01", ifelse(dataset$raw_p_value < 0.05, "<0.05", "ns")))
    dataset_sorted = dataset[order(dataset$raw_p_value),]
    niz = phylostrata
    dataset_sorted = cbind.data.frame(dataset_sorted, niz)
    dataset_sorted = dataset_sorted[order(dataset_sorted$phylostrata),]
    FDR_p_value = dataset_sorted$raw_p_value* max(dataset$phylostrata)/dataset_sorted$niz
    dataset_sorted = cbind.data.frame(dataset_sorted, FDR_p_value)
    dataset_sorted$for_map_p_value = ifelse (dataset_sorted$FDR_p_value < 0.001, "<0.001", ifelse(dataset_sorted$FDR_p_value < 0.01, "<0.01", ifelse(dataset_sorted$FDR_p_value < 0.05, "<0.05", "ns")))
FDR
    my $fdr_exec = $R->run($cmds_fdr);
	$log->trace('FDR calculated in R');

    #return values from R
    return (
        {   odds_sample     => $R->get('dataset_sorted$odds_sample'),
            odds_rest       => $R->get('dataset_sorted$odds_rest'),
            real_log_odds   => $R->get('dataset_sorted$real_log_odds'),
            cdfhyper        => $R->get('dataset_sorted$CDFHyper'),
            cdfhyperover    => $R->get('dataset_sorted$CDFHyperOver'),
            raw_p_value     => $R->get('dataset_sorted$raw_p_value'),
            raw_p_value_map => $R->get('dataset_sorted$raw_p_value_map'),
            niz             => $R->get('dataset_sorted$niz'),
            fdr_p_value     => $R->get('dataset_sorted$FDR_p_value'),
            for_map_p_value => $R->get('dataset_sorted$for_map_p_value'),
        });
}

### INTERFACE SUB ###
# Usage      : my ($start_line, $end_line, $phylo_log_cnt_href, $real_log_odd_aref, $fdr_p_value_aref) = _hypergeometric_test( $param_href );
# Purpose    : creates excel file with log-odds info
# Returns    : ($start_line, $end_line) of values and (real_log_odds, fdr_p_value) for entropy analysis
# Parameters : ( $param_href )
# Throws     : croaks for parameters
# Comments   : it works on maps (not map_phylo) and requires prot_id in map table
# See Also   : 
sub _hypergeometric_test {
	my $log = Log::Log4perl::get_logger("main");
    $log->logcroak ('_hypergeometric_test() needs {$param_href}') unless @_ == 1;
    my ($param_href ) = @_;

	my $log_odds_sheet = $param_href->{sheet};
    
	# get new database handle
    my $dbh      = _dbi_connect($param_href);

    #add a counter for different files and lines
    state $line_counter = 0;

    # Add a caption to each worksheet
    $log_odds_sheet->write( $line_counter, 0, $param_href->{map} . '_x_' . $param_href->{term}, $param_href->{red_bold} );
    $line_counter++;

	$log_odds_sheet->write( $line_counter, 0,  'phylostrata',                                    $param_href->{black_bold} );
	$log_odds_sheet->write( $line_counter, 1,  'phylostrata_name',                               $param_href->{black_bold} );
    $log_odds_sheet->write( $line_counter, 2,  'Functional term',                                $param_href->{black_bold} );
    $log_odds_sheet->write( $line_counter, 3,  'quant',                                          $param_href->{black_bold} );
    $log_odds_sheet->write( $line_counter, 4,  'sample',                                         $param_href->{black_bold} );
    $log_odds_sheet->write( $line_counter, 5,  'hit',                                            $param_href->{black_bold} );
    $log_odds_sheet->write( $line_counter, 6,  'total',                                          $param_href->{black_bold} );
    $log_odds_sheet->write( $line_counter, 7,  'Odds sample (quant/(sample-quant))',             $param_href->{black_bold} );
    $log_odds_sheet->write( $line_counter, 8,  'Odds rest (hit-quant)/(total-hit-sample+quant)', $param_href->{black_bold} );
    $log_odds_sheet->write( $line_counter, 9,  'Real log-odds',                                  $param_href->{black_bold} );
    $log_odds_sheet->write( $line_counter, 10, 'CDFHyper',                                       $param_href->{black_bold} );
    $log_odds_sheet->write( $line_counter, 11, 'CDFHyperOver',                                   $param_href->{black_bold} );
    $log_odds_sheet->write( $line_counter, 12, 'Raw P_value',                                    $param_href->{black_bold} );
    $log_odds_sheet->write( $line_counter, 13, 'Raw P_value for map',                            $param_href->{black_bold} );
    $log_odds_sheet->write( $line_counter, 14, 'Order',                                          $param_href->{black_bold} );
    $log_odds_sheet->write( $line_counter, 15, 'FDR P_value',                                    $param_href->{black_bold} );
    $log_odds_sheet->write( $line_counter, 16, 'for map P_value',                                $param_href->{black_bold} );

    #double increment needed because of difference between absolute notation starting at 0
    #and relative notation starting at 1 (0,0 == A1)
    $line_counter++;
    $line_counter++;
	#save this line number as start of values
	my $start_line = $line_counter;

	# retrieve columns from map table
	my ($phylo_aref, $ps_name_aref, $sample_aref, $total_aref) = _retrieve_map_cols($param_href->{map}, $dbh);

	#get functional term column
	my $phylostrata = scalar @$phylo_aref;
    my @term = ($param_href->{term}) x $phylostrata;

    #writa a table in one go (oxhos missing values so this doesn't work)
    $log_odds_sheet->write_col( "A$line_counter", $phylo_aref );
    $log_odds_sheet->write_col( "B$line_counter", $ps_name_aref );
    $log_odds_sheet->write_col( "C$line_counter", \@term );
    $log_odds_sheet->write_col( "E$line_counter", $sample_aref );
    $log_odds_sheet->write_col( "G$line_counter", $total_aref );

	# retrieve columns from term table
	my ($quant_aref, $hit_aref) = _retrieve_term_cols($param_href->{term}, $phylo_aref, $dbh);

    #write oxphos values
    $log_odds_sheet->write_col( "D$line_counter", $quant_aref );
    $log_odds_sheet->write_col( "F$line_counter", $hit_aref);

    #get rest of values from R using Statistics::R
    my ($exit_href) = _calculate_in_R(
        {   phylo  => $phylo_aref,
            term   => \@term,
            quant  => $quant_aref,
            sample => $sample_aref,
            hit    => $hit_aref,
            total  => $total_aref,
			out    => $param_href->{out},
        }
      );

    #write calculated values from R to excel
    $log_odds_sheet->write_col( "H$line_counter", $exit_href->{odds_sample} );
    $log_odds_sheet->write_col( "I$line_counter", $exit_href->{odds_rest} );
    $log_odds_sheet->write_col( "J$line_counter", $exit_href->{real_log_odds} );
    $log_odds_sheet->write_col( "K$line_counter", $exit_href->{cdfhyper} );
    $log_odds_sheet->write_col( "L$line_counter", $exit_href->{cdfhyperover} );
    $log_odds_sheet->write_col( "M$line_counter", $exit_href->{raw_p_value} );
    $log_odds_sheet->write_col( "N$line_counter", $exit_href->{raw_p_value_map} );
    $log_odds_sheet->write_col( "O$line_counter", $exit_href->{niz} );
    $log_odds_sheet->write_col( "P$line_counter", $exit_href->{fdr_p_value} );
    $log_odds_sheet->write_col( "Q$line_counter", $exit_href->{for_map_p_value} );

    #increment for number of phylostrata to make space for next map (file)
    $line_counter += $phylostrata + 2;
	#save this value for end of values
	my $end_line = $line_counter - 3;

	# report writing to Excel to log
	$log->debug("Report: wrote $param_href->{map}_x_$param_href->{term} to $param_href->{outfile}");

	# produce phylo => log_odd temp hash
	my %phylo_log_odds;
	@phylo_log_odds{@$phylo_aref} = @{ $exit_href->{real_log_odds} };

	# produce phylo => [up, zero, down] permanent hash
	state %phylo_log_cnt;
	foreach my $ps ( keys %phylo_log_odds ) {
		no warnings 'uninitialized';
		my ($up, $zero, $down) = (0, 0, 0);
		if ( ($phylo_log_odds{$ps} eq '-Inf') or ($phylo_log_odds{$ps} == 0) or ($phylo_log_odds{$ps} =~ m/#/) ) {
			$zero++;
		}
		elsif ($phylo_log_odds{$ps} > 0) {
			$up++;
		}
		elsif ($phylo_log_odds{$ps} < 0) {
			$down++;
		}
		$phylo_log_cnt{$ps} = [$phylo_log_cnt{$ps}->[0] + $up, $phylo_log_cnt{$ps}->[1] + $zero, $phylo_log_cnt{$ps}->[2] + $down];
	}

    $dbh->disconnect;

	return ($start_line, $end_line, \%phylo_log_cnt, $exit_href->{real_log_odds}, $exit_href->{fdr_p_value} );
}


### INTERNAL UTILITY ###
# Usage      : my ($workbook, $log_odds_sheet, $entropy_sheet, $black_bold, $red_bold) = _create_excel($outfile, $infile);
# Purpose    : creates Excel workbook and sheet needed
# Returns    : $workbook, $log_odds_sheet, $black_bold, $red_bold
# Parameters : $outfile and $infile
# Throws     : croaks if wrong number of parameters
# Comments   : 
# See Also   : 
sub _create_excel {
    my $log = Log::Log4perl::get_logger("main");
    $log->logcroak('_create_excel() needs {$outfile}') unless @_ == 2;
    my ($outfile, $infile) = @_;

	# get name of term table
	my $term_tbl = path($infile)->basename;
	($term_tbl) = $term_tbl =~ m/\A([^\.]+)\.(.+)\z/;
	$term_tbl   .= '_term';

    # Create a new Excel workbook
	if (-f $outfile) {
		unlink $outfile and $log->warn( "Action: unlinked Excel $outfile" );
	}
    my $workbook = Excel::Writer::XLSX->new("$outfile") or $log->logcroak( "Problems creating new Excel file: $!" );

    # Add a worksheet (log-odds for calculation);
    my $log_odds_sheet = $workbook->add_worksheet("hyper_$term_tbl");
    my $entropy_sheet = $workbook->add_worksheet("info_$term_tbl");

    $log->trace( 'Report: Excel file: ',          $outfile );
    $log->trace( 'Report: Excel workbook: ',      $workbook );
    $log->trace( 'Report: Excel hyper_sheet: ',   $log_odds_sheet );
    $log->trace( 'Report: Excel entropy_sheet: ', $entropy_sheet );

    # Add a Format (bold black)
    my $black_bold = $workbook->add_format(); $black_bold->set_bold(); $black_bold->set_color('black');
    # Add a Format (bold red)
    my $red_bold = $workbook->add_format(); $red_bold->set_bold(); $red_bold->set_color('red'); 

    return ($workbook, $log_odds_sheet, $entropy_sheet, $black_bold, $red_bold);
}


### INTERNAL UTILITY ###
# Usage      : my ($phylo_aref, $ps_name_aref, $sample_aref, $total_aref) = _retrieve_map_cols($param_href{map}, $dbh);
# Purpose    : retrieves columns from map table for hypergeometric test later
# Returns    : phylo, sample and total arefs
# Parameters : map table name + database handle
# Throws     : croaks if wrong number of parameters
# Comments   : 
# See Also   : part of _hypergeometric_test()
sub _retrieve_map_cols {
    my $log = Log::Log4perl::get_logger("main");
    $log->logcroak('_retrieve_map_cols() needs $param_href{map}') unless @_ == 2;
    my ($map_tbl, $dbh) = @_;

    #prepare the SELECT statement for full ps table
    my $statement_ps = sprintf( qq{
    SELECT phylostrata, COUNT(phylostrata) AS genes, species_name
    FROM %s
    GROUP BY phylostrata
    ORDER BY phylostrata
	}, $dbh->quote_identifier($map_tbl) );

    # map filters the column from bi-dimensional array
    my @phylo   = map { $_->[0] } @{ $dbh->selectall_arrayref($statement_ps) };
    my @sample  = map { $_->[1] } @{ $dbh->selectall_arrayref($statement_ps) };
    my @ps_name = map { $_->[2] } @{ $dbh->selectall_arrayref($statement_ps) };
    $log->trace( 'Returned phylostrata: {', join('}{', @phylo), '}' );
 
    #calculate total from @col_genes;
    my $total = sum(@sample);
	my $phylostrata = scalar @phylo;
    my @totals = ($total) x $phylostrata;

    return (\@phylo, \@ps_name, \@sample, \@totals);
}


### INTERNAL UTILITY ###
# Usage      : my ($quant_aref, $hit_aref) = _retrieve_term_cols($param_href{term}, $phylo_aref, $dbh);
# Purpose    : retrieves columns from term table for hypergeometric test later
# Returns    : quant and hit arefs
# Parameters : term table name, phylostrata aref + database handle
# Throws     : croaks if wrong number of parameters
# Comments   : 
# See Also   : part of _hypergeometric_test()
sub _retrieve_term_cols {
    my $log = Log::Log4perl::get_logger("main");
    $log->logcroak('_retrieve_term_cols() needs a $param_href{term}') unless @_ == 3;
    my ($term_tbl, $phylo_aref, $dbh) = @_;

    #prepare the SELECT statement for term table
    my $statement_term = sprintf( qq{
    SELECT phylostrata, COUNT(phylostrata) AS genes
    FROM %s
    GROUP BY phylostrata
    ORDER BY phylostrata
    }, $dbh->quote_identifier($term_tbl) );

    #prepare missing values (extra work)
    # get array of phylo nad genes pairs:
    my $ps_aref = $dbh->selectcol_arrayref( $statement_term, { Columns => [ 1, 2 ] } );
    my %missing_ps = @$ps_aref;    # build hash from key-value pairs so $missing_ps{$ps} => genes
	$log->trace("my raw phylostrata and genes from func column @$ps_aref");

    #add missing values to the hash
    foreach my $ps ( @$phylo_aref ) {
        $missing_ps{$ps} = 0 unless exists $missing_ps{$ps};
    }

    #transform back to array to print to Excel
    my @sorted_cols;
    foreach my $ps ( sort { $a <=> $b } keys %missing_ps ) {
        push @sorted_cols, $ps, $missing_ps{$ps};
    }
	$log->trace("my sorted columns from $term_tbl: @sorted_cols");
    
    #pull even - phylostrata (ex keys) and odd - genes (ex values) from array
    #my @evens_phylo = @sorted_cols[grep !($_ % 2), 0..$#sorted_cols];    # even-index elements
    my @quant  = @sorted_cols[grep $_ % 2,  0..$#sorted_cols];       # odd-index  elements
	$log->trace( "my genes from func table: @quant" );

    #calculate hit from @col_genes;
    my $hit = sum(@quant);
	my $phylostrata = scalar @$phylo_aref;
    my @hits = ($hit) x $phylostrata;

    return (\@quant, \@hits);
}


### INTERNAL UTILITY ###
# Usage      : _add_chart(term => $term_tbl, map => $map_tbl, workbook => $workbook, sheet => $log_odds_sheet, start => $start_line, end => $end_line);
# Purpose    : inserts chart in log-odds sheet near each map
# Returns    : nothing
# Parameters : term => $term_tbl, map => $map_tbl, workbook => $workbook, sheet => $log_odds_sheet, start => $start_line, end => $end_line
# Throws     : croaks if wrong number of parameters
# Comments   : 
# See Also   : 
sub _add_chart {
    my $log = Log::Log4perl::get_logger("main");
    $log->logcroak('_add_chart() needs a $param_href') unless @_ == 1;
    my ($param_href) = @_;

	# create 2 charts: one that will be embeded to hyper sheet and second on separate sheet
	my $chart_single = $param_href->{workbook}->add_chart( type => 'line', name => "$param_href->{map}_x_$param_href->{term}", embedded => 0 );   #subtype not available
	my $chart_emb    = $param_href->{workbook}->add_chart( type => 'line', name => "$param_href->{map}_x_$param_href->{term}", embedded => 1 );   #subtype not available

	# configure both charts the same
	foreach my $chart ($chart_single, $chart_emb) {
		_configure_chart( {chart => $chart, %{$param_href} } );
	}

	# Insert the chart into the a worksheet. (second one will be printed on separate sheet automatically)
	$param_href->{sheet}->insert_chart( "S$param_href->{start}", $chart_emb, 0, 0, 1.5, 1.5 );   #scale by 150%

    return;
}


### INTERNAL UTILITY ###
# Usage      : _configure_chart($chart);
# Purpose    : run configuration step for all charts
# Returns    : nothing
# Parameters : $param_href with chart object to configure
# Throws     : croaks if wrong number of parameters
# Comments   : 
# See Also   : 
sub _configure_chart {
    my $log = Log::Log4perl::get_logger("main");
    $log->logcroak('_configure_chart() needs $param_href}') unless @_ == 1;
    my ($param_href) = @_;
	my $chart = $param_href->{chart};

	# Configure the chart.
	$chart->add_series(
		name       => "$param_href->{map}_x_$param_href->{term}",
	    categories => "=$param_href->{sheet_name}!A$param_href->{start}:A$param_href->{end}",
	    values     => "=$param_href->{sheet_name}!J$param_href->{start}:J$param_href->{end}",
		line       => { color => 'blue', width => 3.25 },
	);

	# Add a chart title and some axis labels.
	$chart->set_x_axis( name => 'Phylostrata', visible => 1, label_position => 'low', major_gridlines => { visible => 1 }, position_axis => 'between' );
	# visible => 0 removes garbage in x_axis
	$chart->set_y_axis( name => 'Log_odds', major_gridlines => { visible => 1 } );
 
	# Set an Excel chart style. Colors with white outline and shadow.
	$chart->set_style( 10 );
	
	# Display data in hidden rows or columns on the chart.
	$chart->show_blanks_as( 'zero' );   #gap also possible

    return;
}


### INTERNAL UTILITY ###
# Usage      : _chart_all( { plot =>\%plot_hash, workbook => $workbook, sheet_name => "hyper_$term_tbl", term => $term_tbl } );
# Purpose    : chart all maps on single sheet (and chart)
# Returns    : nothing
# Parameters : 
# Throws     : croaks if wrong number of parameters
# Comments   : 
# See Also   : 
sub _chart_all {
    my $log = Log::Log4perl::get_logger("main");
    $log->logcroak('_chart_all() needs a $param_href') unless @_ == 1;
    my ($param_href) = @_;
    my %plot_hash = %{ $param_href->{plot} };

	# create a chart (separate sheet)
	my $chart = $param_href->{workbook}->add_chart( type => 'line', name => "Chart_all_$param_href->{term}", embedded => 0 );

	#	# Configure the chart.
	#	while (my ($series_name, $pos_aref) = each %{ $param_href->{plot} } ) {
	#		$chart->add_series(
	#			name       => "$series_name",
	#		    categories => "=$param_href->{sheet_name}!A$pos_aref->[0]:A$pos_aref->[1]",
	#		    values     => "=$param_href->{sheet_name}!I$pos_aref->[0]:I$pos_aref->[1]",
	#			line       => { width => 3 },
	#		);
	#	}

	foreach my $series_name ( map { $_->[0] } sort { $a->[1] <=> $b->[1] } map { [ $_, /\A(?:\D+)(\d+)(?:.+)\z/ ] } keys %plot_hash ) {
		my $pos_aref = $plot_hash{$series_name};
		$chart->add_series(
			name       => "$series_name",
		    categories => "=$param_href->{sheet_name}!A$pos_aref->[0]:A$pos_aref->[1]",
		    values     => "=$param_href->{sheet_name}!J$pos_aref->[0]:J$pos_aref->[1]",
			line       => { width => 3 },
		);
	}


	# Add a chart title and some axis labels.
	$chart->set_x_axis( name => 'Phylostrata', visible => 1, label_position => 'low', major_gridlines => { visible => 1 }, position_axis => 'between' );
	# visible => 0 removes garbage in x_axis
	$chart->set_y_axis( name => 'Log_odds', major_gridlines => { visible => 1 } );
 
	# Set an Excel chart style. Colors with white outline and shadow.
	$chart->set_style( 10 );
	
	# Display data in hidden rows or columns on the chart.
	$chart->show_blanks_as( 'zero' );   #gap also possible

	#	# this method adds Up-Down bars to Line charts to indicate the difference between the first and last data series
	#	$chart->set_up_down_bars(
	#		up   => { fill => { color => 'green' } },
	#		down => { fill => { color => 'red' } },
	#	);
	#
	#	# this method adds Drop Lines to charts to show the Category value of points in the data.
	#	$chart->set_high_low_lines( line => { color => 'red', dash_type => 'square_dot' } );



    return;
}


### INTERNAL UTILITY ###
# Usage      : _calculate_information( { entropy =>\%entropy_hash, phylo_cnt => $phylo_log_cnt_href, workbook => $workbook, sheet => $entropy_sheet, black_bold => $black_bold, red_bold => $red_bold } );
# Purpose    : calculates information per map and prints to Excel
# Returns    : nothing
# Parameters : 
# Throws     : croaks if wrong number of parameters
# Comments   : 
# See Also   : 
sub _calculate_information {
    my $log = Log::Log4perl::get_logger("main");
    $log->logcroak('_calculate_information() needs a $param_href') unless @_ == 1;
    my ($param_href) = @_;
    my %entropy_hash = %{ $param_href->{entropy} };
	my %phylo_log_cnt_copy = %{ $param_href->{phylo_cnt} };

	# calculate information per map
	my %info_hash;
	my %sum_info_hash;
	my %ps_log_hash;
	foreach my $map_name ( map { $_->[0] } sort { $a->[1] <=> $b->[1] } map { [ $_, /\A(?:\D+)(\d+)(?:.+)\z/ ] } keys %entropy_hash ) {
		my $aref = $entropy_hash{$map_name};

		# information content per map
		my $info_content = 0;
		foreach my $e_value ( @{ $aref->[1] } ) {
			if ($e_value < 0.05) {
				$info_content++;
			}
		}
		$info_hash{$map_name} = $info_content;

		# log_odds per map
		my ($up, $zero, $down) = (0, 0, 0);
		foreach my $log_odd ( @{ $aref->[0] } ) {
			if ( ($log_odd eq '-Inf') or ($log_odd == 0) or ($log_odd =~ m/#/) ) {
				$zero++;
			}
			elsif ($log_odd > 0) {
				$up++;
			}
			elsif ($log_odd < 0) {
				$down++;
			}
		}
		$sum_info_hash{$map_name} = [$up, $zero, $down];
	}

	# print to Excel info_term sheet
	my $line_cnt=0;
    $param_href->{sheet}->write( $line_cnt, 0, "INFORMATION CONTENT PER MAP", $param_href->{red_bold} );
    $line_cnt++;
	$param_href->{sheet}->write( $line_cnt, 0,  'Map_term',            $param_href->{black_bold} );
	$param_href->{sheet}->write( $line_cnt, 1,  'Information_content', $param_href->{black_bold} );
	$param_href->{sheet}->write( $line_cnt, 2,  'Log_odds_UP',         $param_href->{black_bold} );
	$param_href->{sheet}->write( $line_cnt, 3,  'Log_odds_ZERO',       $param_href->{black_bold} );
	$param_href->{sheet}->write( $line_cnt, 4,  'Log_odds_DOWN',       $param_href->{black_bold} );
    $line_cnt += 2;   # to relative notation

	# information content
	foreach my $map_name ( map { $_->[0] } sort { $a->[1] <=> $b->[1] } map { [ $_, /\A(?:\D+)(\d+)(?:.+)\z/ ] } keys %info_hash ) {
		$param_href->{sheet}->write( "A$line_cnt", $map_name );
		$param_href->{sheet}->write( "B$line_cnt", $info_hash{$map_name} );
		$line_cnt++;
	}

	# log_odds per map
	$line_cnt = 3;   #return to first line of column
	foreach my $map_name ( map { $_->[0] } sort { $a->[1] <=> $b->[1] } map { [ $_, /\A(?:\D+)(\d+)(?:.+)\z/ ] } keys %sum_info_hash ) {
		$param_href->{sheet}->write( "C$line_cnt", $sum_info_hash{$map_name}->[0] );
		$param_href->{sheet}->write( "D$line_cnt", $sum_info_hash{$map_name}->[1] );
		$param_href->{sheet}->write( "E$line_cnt", $sum_info_hash{$map_name}->[2] );
		$line_cnt++;
	}
    $line_cnt += 2;

	# cumulative information per phylostrata
	$param_href->{sheet}->write( $line_cnt, 0,  'Phylostrata',   $param_href->{black_bold} );
	$param_href->{sheet}->write( $line_cnt, 1,  'Log_odds_UP',   $param_href->{black_bold} );
	$param_href->{sheet}->write( $line_cnt, 2,  'Log_odds_ZERO', $param_href->{black_bold} );
	$param_href->{sheet}->write( $line_cnt, 3,  'Log_odds_DOWN', $param_href->{black_bold} );
	$param_href->{sheet}->write( $line_cnt, 4,  'Ratio_per_ps',  $param_href->{black_bold} );
	$param_href->{sheet}->write( $line_cnt, 5,  'ps_plus_ratio', $param_href->{black_bold} );
    $line_cnt += 2;   # to relative notation

	my $phylostrata = scalar keys %phylo_log_cnt_copy;
	my $ratio_sum;
	foreach my $ps ( sort { $a <=> $b } keys %phylo_log_cnt_copy ) {
		my $up = $phylo_log_cnt_copy{$ps}->[0];
		my $zero = $phylo_log_cnt_copy{$ps}->[1];
		my $down = $phylo_log_cnt_copy{$ps}->[2];
		my $map_num = ($up + $zero + $down);
		$param_href->{sheet}->write( "A$line_cnt", $ps );
		$param_href->{sheet}->write( "B$line_cnt", $up );
		$param_href->{sheet}->write( "C$line_cnt", $zero );
		$param_href->{sheet}->write( "D$line_cnt", $down );
		my $ratio =
		  - $up/$map_num   * log3($up/$map_num)
		  - $zero/$map_num * log3($zero/$map_num)
		  - $down/$map_num * log3($down/$map_num);
		$param_href->{sheet}->write( "E$line_cnt", $ratio );
		$ratio_sum += $ratio;
		$line_cnt++;
	}
	$param_href->{sheet}->write( "D$line_cnt", "Ratio_sum", $param_href->{black_bold} );
	$param_href->{sheet}->write( "E$line_cnt", $ratio_sum,  $param_href->{black_bold} );

	# calculate real information
	$line_cnt++;
	my $information = $phylostrata - $ratio_sum;
	$param_href->{sheet}->write( "D$line_cnt", "Information", $param_href->{black_bold} );
	$param_href->{sheet}->write( "E$line_cnt", $information,  $param_href->{black_bold} );

	# calculate relative information po bazi 3
	$line_cnt++;
	my $information_rel = $information/$phylostrata;
	$param_href->{sheet}->write( "D$line_cnt", "Info_rel",        $param_href->{red_bold} );
	# Add a Format (percentage)
    my $format_perc = $param_href->{workbook}->add_format(); $format_perc->set_num_format( '[Red]0.00%;[Red]-0.00%;0.00%' ); $format_perc->set_bold();
	$param_href->{sheet}->write( "E$line_cnt", $information_rel,  $format_perc );

	# calculate relative information u bitovima
	$line_cnt++;
	my $information_rel_bit = log2($information_rel * 100);
	$param_href->{sheet}->write( "D$line_cnt", "Info_in_bit",        $param_href->{red_bold} );
	$param_href->{sheet}->write( "E$line_cnt", $information_rel_bit, $param_href->{black_bold} );


    return;
}


### INTERNAL UTILITY ###
# Usage      : log2($zero/$phylostrata)
# Purpose    : calculates log po bazi 2
# Returns    : log po bazi 2
# Parameters : number
# Throws     : croaks if wrong number of parameters
# Comments   : 
# See Also   : 
sub log2 {
	my $n = shift;
	if ($n == 0) {
		return 0;
	}
    return log($n)/log(2);
}


### INTERNAL UTILITY ###
# Usage      : log3($zero/$phylostrata)
# Purpose    : calculates log po bazi 3
# Returns    : log po bazi 3
# Parameters : number
# Throws     : croaks if wrong number of parameters
# Comments   : returns zero if number it calculates is zero
# See Also   : 
sub log3 {
	my $n = shift;
	if ($n == 0) {
		return 0;
	}
    return log($n)/log(3);
}


### INTERNAL UTILITY ###
# Usage      : my ($excel_href) = _create_excel_for_collect_maps($outfile);
# Purpose    : creates Excel workbook and sheet needed for --mode=collect_maps
# Returns    : workbook, sheet and formats
# Parameters : $outfile
# Throws     : croaks if wrong number of parameters
# Comments   : 
# See Also   : --mode=collect_maps
sub _create_excel_for_collect_maps {
    my $log = Log::Log4perl::get_logger("main");
    $log->logcroak('_create_excel_for_collect_maps() needs {$outfile}') unless @_ == 1;
    my ($outfile) = @_;

    # Create a new Excel workbook
	if (-f $outfile) {
		unlink $outfile and $log->warn( "Action: unlinked Excel $outfile" );
	}
    my $workbook = Excel::Writer::XLSX->new("$outfile") or $log->logcroak( "Problems creating new Excel file: $!" );

    # Add a worksheet (log-odds for calculation);
    my $maps_sheet = $workbook->add_worksheet("MAPS");
    $log->trace( 'Report: Excel file: ',          $outfile );
    $log->trace( 'Report: Excel workbook: ',      $workbook );
    $log->trace( 'Report: Excel MAPS_sheet: ',    $maps_sheet );

    # Add a Format (bold black)
    my $black_bold = $workbook->add_format(); $black_bold->set_bold(); $black_bold->set_color('black');
    # Add a Format (bold red)
    my $red_bold = $workbook->add_format(); $red_bold->set_bold(); $red_bold->set_color('red'); 
	# Add a Format (red)
    my $red_val = $workbook->add_format(); $red_val->set_color('red');
	# Add a Format (green)
    my $green_val = $workbook->add_format(); $green_val->set_color('green');
	# Add a Format (percentage)
    my $format_perc = $workbook->add_format(); $format_perc->set_num_format( '0.00%;[Red]-0.00%;0.00%' );

    return ( { workbook => $workbook, sheet => $maps_sheet, black_bold => $black_bold, red_bold => $red_bold, red => $red_val, green => $green_val, perc => $format_perc } );
}


### INTERNAL UTILITY ###
# Usage      : _add_bare_map_chart( { map => $map_name, workbook => $workbook, sheet => $excel_href->{sheet}, sheet_name => "MAPS", start => $sum_start, end => $sum_end } );
# Purpose    : inserts chart in MAPS sheet near each map
# Returns    : nothing
# Parameters : Excel related
# Throws     : croaks if wrong number of parameters
# Comments   : 
# See Also   :--mode=collect_maps
sub _add_bare_map_chart {
    my $log = Log::Log4perl::get_logger("main");
    $log->logcroak('_add_bare_map_chart() needs a $param_href') unless @_ == 1;
    my ($chart_href) = @_;

	# create 2 charts: one that will be embeded to MAPS sheet and second on separate sheet
	my $chart_single = $chart_href->{workbook}->add_chart( type => 'line', name => "$chart_href->{map}", embedded => 0 );   #subtype not available
	my $chart_emb    = $chart_href->{workbook}->add_chart( type => 'line', name => "$chart_href->{map}", embedded => 1 );   #subtype not available

	# configure both charts the same
	foreach my $chart ($chart_single, $chart_emb) {
		_configure_chart_for_collect_maps( {chart => $chart, %{$chart_href} } );
	}

	# Insert the chart into the worksheet. (second one will be printed on separate sheet automatically)
	$chart_href->{sheet}->insert_chart( "I$chart_href->{start}", $chart_emb, 0, 0, 1.5, 1.5 );   #scale by 150%

    return;
}


### INTERNAL UTILITY ###
# Usage      : _configure_chart_for_collect_maps($chart);
# Purpose    : run configuration step for all charts
# Returns    : nothing
# Parameters : $param_href with chart object to configure
# Throws     : croaks if wrong number of parameters
# Comments   : 
# See Also   : 
sub _configure_chart_for_collect_maps {
    my $log = Log::Log4perl::get_logger("main");
    $log->logcroak('_configure_chart_for_collect_maps() needs $chart_href}') unless @_ == 1;
    my ($chart_href) = @_;
	my $chart = $chart_href->{chart};

	# Configure the chart.
	$chart->add_series(
		name       => "$chart_href->{map}",
	    categories => "=$chart_href->{sheet_name}!A$chart_href->{start}:A$chart_href->{end}",
	    values     => "=$chart_href->{sheet_name}!E$chart_href->{start}:E$chart_href->{end}",
		line       => { color => 'blue', width => 3.25 },
	);

	# Add a chart title and some axis labels.
	$chart->set_x_axis( name => 'Phylostrata', visible => 1, label_position => 'low', major_gridlines => { visible => 1 }, position_axis => 'between' );
	# visible => 0 removes garbage in x_axis
	$chart->set_y_axis( name => '% of genes per phylostrata', major_gridlines => { visible => 1 } );
 
	# Set an Excel chart style. Colors with white outline and shadow.
	$chart->set_style( 10 );
	
	# Display data in hidden rows or columns on the chart.
	$chart->show_blanks_as( 'zero' );   #gap also possible

    return;
}


### INTERNAL UTILITY ###
# Usage      : _chart_all_for_collect_maps( { plot =>\%plot_hash, workbook => $excel_href->{workbook}, sheet_name => "MAPS" } );
# Purpose    : chart all maps on single sheet (and chart)
# Returns    : nothing
# Parameters : 
# Throws     : croaks if wrong number of parameters
# Comments   : 
# See Also   : --mode=collect_maps
sub _chart_all_for_collect_maps {
    my $log = Log::Log4perl::get_logger("main");
    $log->logcroak('_chart_all_for_collect_maps() needs a $param_href') unless @_ == 1;
    my ($param_href) = @_;
    my %plot_hash = %{ $param_href->{plot} };

	# create a chart (separate sheet)
	my $chart_genes = $param_href->{workbook}->add_chart( type => 'line', name => "Chart_all_genes", embedded => 0 );
	my $chart_perc  = $param_href->{workbook}->add_chart( type => 'line', name => "Chart_all_perc",  embedded => 0 );

	foreach my $series_name ( map { $_->[0] } sort { $a->[1] <=> $b->[1] } map { [ $_, /\A(?:\D+)(\d+)(?:.+)\z/ ] } keys %plot_hash ) {
		my $pos_aref = $plot_hash{$series_name};
		$chart_genes->add_series(
			name       => "$series_name",
		    categories => "=$param_href->{sheet_name}!A$pos_aref->[0]:A$pos_aref->[1]",
		    values     => "=$param_href->{sheet_name}!D$pos_aref->[0]:D$pos_aref->[1]",
			line       => { width => 3 },
		);

		$chart_perc->add_series(
			name       => "$series_name",
		    categories => "=$param_href->{sheet_name}!A$pos_aref->[0]:A$pos_aref->[1]",
		    values     => "=$param_href->{sheet_name}!E$pos_aref->[0]:E$pos_aref->[1]",
			line       => { width => 3 },
		);
	}

	# Add a chart title and some axis labels.
	$chart_genes->set_x_axis( name => 'Phylostrata', visible => 1, label_position => 'low', major_gridlines => { visible => 1 }, position_axis => 'between' );
	$chart_perc->set_x_axis(  name => 'Phylostrata', visible => 1, label_position => 'low', major_gridlines => { visible => 1 }, position_axis => 'between' );
	$chart_genes->set_y_axis( name => 'Num of genes per phylostrata', major_gridlines => { visible => 1 } );
	$chart_perc->set_y_axis(  name => '% of genes per phylostrata', major_gridlines => { visible => 1 } );
 
	# Set an Excel chart style. Colors with white outline and shadow.
	$chart_genes->set_style( 10 );
	$chart_perc->set_style( 10 );
	
	# Display data in hidden rows or columns on the chart.
	$chart_genes->show_blanks_as( 'zero' );   #gap also possible
	$chart_perc->show_blanks_as( 'zero' );   #gap also possible

    return;
}


### INTERFACE SUB ###
# Usage      : --mode=multi_maps
# Purpose    : load and create maps and association maps for multiple e_values and one term
# Returns    : nothing
# Parameters : $param_href
# Throws     : croaks if wrong number of parameters
# Comments   : writes to Excel file
# See Also   : 
sub multi_maps {
    my $log = Log::Log4perl::get_logger("main");
    $log->logcroak('multi_maps() needs a $param_href') unless @_ == 1;
    my ($param_href) = @_;

	my $out         = $param_href->{out}         or $log->logcroak( 'no $out specified on command line!' );
	my $in          = $param_href->{in}          or $log->logcroak( 'no $in specified on command line!' );
	my $outfile     = $param_href->{outfile}     or $log->logcroak( 'no $outfile specified on command line!' );
	my $infile      = $param_href->{infile}      or $log->logcroak( 'no $infile specified on command line!' );
	my $column_list = $param_href->{column_list} or $log->logcroak( 'no $column_list specified on command line!' );
	my $term_sub_name = $param_href->{term_sub_name} or $log->logcroak( 'no $term_sub_name specified on command line!' );
	my $map_sub_name  = $param_href->{map_sub_name} or $log->logcroak( 'no $map_sub_name specified on command line!' );

	# dispatch table to import one term (specific part)
	my %term_dispatch = (
        _term_prepare   => \&_term_prepare,                 # term has prot_id column

    );

	# dispatch table to import map (specific part)
	my %map_dispatch = (
        _import_map           => \&_import_map,             # normal map
        _import_map_with_expr => \&_import_map_with_expr,   # expression map

    );

	# collect maps from IN
	my $sorted_maps_aref = _sorted_files_in( $in, 'phmap_names' );

	# get new handle
    my $dbh = _dbi_connect($param_href);

	# create new Excel workbook that will hold calculations
	my ($workbook, $log_odds_sheet, $entropy_sheet, $black_bold, $red_bold) = _create_excel($outfile, $infile);

	# create hash to hold all coordinates of start - end lines holding data
	my %plot_hash;

	# create hash to hold all real_log_odds and fdr_p_values for entropy analysis (information)
	my %entropy_hash;
	my $calc_info_href;

	my ($map_tbl, $term_tbl);   # name needed outside loop
	# foreach map create and load into database (general reusable)
	foreach my $map (@$sorted_maps_aref) {

		# import map
        if ( exists $map_dispatch{$map_sub_name} ) {
            $map_tbl = $map_dispatch{$map_sub_name}->(  { map_file => $map, dbh => $dbh, %{$param_href} } );
        }
        else {
            $log->logcroak( "Unrecognized coderef --map_sub_name={$map_sub_name} on command line thus aborting");
        }
	
		# import one term (specific part)
        if ( exists $term_dispatch{$term_sub_name} ) {
            $term_tbl = $term_dispatch{$term_sub_name}->(  { infile => $infile, dbh => $dbh, column_list => $column_list } );
        }
        else {
            $log->logcroak( "Unrecognized coderef --term_sub_name={$term_sub_name} on command line thus aborting");
        }
	
		# connect term
		_update_term_with_map($term_tbl, $map_tbl, $dbh);
	
		# calculate hypergeometric test and print to Excel
		my ($start_line, $end_line, $phylo_log_cnt_href, $real_log_odd_aref, $fdr_p_value_aref) = _hypergeometric_test( { term => $term_tbl, map => $map_tbl, sheet => $log_odds_sheet, black_bold => $black_bold, red_bold => $red_bold, %{$param_href} } );
		say "$start_line-$end_line";

		# collect all coordinates of start and end lines to hash
		# series name is key, coordinates are value (aref)
		$plot_hash{"${map_tbl}_x_$term_tbl"} = [$start_line, $end_line];

		# collect real_log_odds and FDR_P_value for information calculation
		$entropy_hash{"${map_tbl}_x_$term_tbl"} = [$real_log_odd_aref, $fdr_p_value_aref];

		# hash ref for _calculate_information() need to persist after loop
		$calc_info_href = $phylo_log_cnt_href;

		# insert chart for each map-term combination near maps
		_add_chart( { term => $term_tbl, map => $map_tbl, workbook => $workbook, sheet => $log_odds_sheet, sheet_name => "hyper_$term_tbl", start => $start_line, end => $end_line } );
	
	}   # end foreach map

	# create chart with all maps on it
	_chart_all( { plot =>\%plot_hash, workbook => $workbook, sheet_name => "hyper_$term_tbl", term => $term_tbl } );

	# calculate entropy here using %entropy_hash
	_calculate_information(  { entropy =>\%entropy_hash, phylo_cnt => $calc_info_href, workbook => $workbook, sheet => $entropy_sheet, black_bold => $black_bold, red_bold => $red_bold } );

	# close the Excel file
	$workbook->close() or $log->logdie( "Error closing Excel file: $!" );

	$dbh->disconnect;

    return;
}


### INTERNAL UTILITY ###
# Usage      : $term_tbl = $term_sub_name->( { infile => $infile, dbh => $dbh, column_list => $column_list } );
# Purpose    : imports and prepares term table
# Returns    : term table name
# Parameters : ($infile, $dbh, $relation);
# Throws     : croaks if wrong number of parameters
# Comments   : 
# See Also   : --mode=multi_maps
sub _term_prepare {
    my $log = Log::Log4perl::get_logger("main");
    $log->logcroak('_term_prepare() needs {$term_href}') unless @_ == 1;
    my ($term_href) = @_;
	my $dbh = $term_href->{dbh};

	# get name of term table
	my $term_tbl = path($term_href->{infile})->basename;
	($term_tbl) = $term_tbl =~ m/\A([^\.]+)\.(.+)\z/;
	$term_tbl   .= '_term';


    # create term table
    my $create_query = sprintf( qq{
	CREATE TABLE %s (
	id INT UNSIGNED AUTO_INCREMENT NOT NULL,
	gene_name VARCHAR(20) NULL,
	gene_id VARCHAR(20) NULL,
	prot_id VARCHAR(20) NULL,
	phylostrata TINYINT UNSIGNED NULL,
	ti INT UNSIGNED NULL,
	species_name VARCHAR(200) NULL,
	extra MEDIUMTEXT NULL,
	PRIMARY KEY(id),
	KEY(gene_id),
	KEY(prot_id)
    ) }, $dbh->quote_identifier($term_tbl) );
	_create_table( { table_name => $term_tbl, dbh => $dbh, query => $create_query } );
	$log->trace("Report: $create_query");

	# load data infile (needs column list or empty)
	#my $column_list = '(gene_name, gene_id)';
	_load_table_into($term_tbl, $term_href->{infile}, $dbh, $term_href->{column_list});

    return $term_tbl;
}


### INTERNAL UTILITY ###
# Usage      : my $map_tbl = _import_map_with_expr( { map_file => $map, dbh => $dbh, %{$param_href} } );
# Purpose    : imports map with header
# Returns    : name of map table
# Parameters : input dir, full path to map file and database handle
# Throws     : croaks if wrong number of parameters
# Comments   : creates temp files without header for LOAD data infile
# See Also   : --mode=multi_maps
sub _import_map_with_expr {
    my $log = Log::Log4perl::get_logger("main");
    $log->logcroak('_import_map_with_expr() needs {$map_href}') unless @_ == 1;
    my ($map_href) = @_;

	my $map_tbl = _import_map( $map_href );

	# import expression file
	my $expr_tbl= path( $map_href->{expr_file} )->basename;
	($expr_tbl) = $expr_tbl =~ m/\A([^\.]+)\.txt\z/;
	my $create_expr = sprintf( qq{
	CREATE TABLE IF NOT EXISTS %s (
	stage TINYINT UNSIGNED NOT NULL,
	gene_id VARCHAR(40) NULL,
	prot_id VARCHAR(40) NOT NULL,
	term VARCHAR(255) NOT NULL,
	phylostrata TINYINT UNSIGNED NULL,
	ti INT UNSIGNED NULL,
	species_name VARCHAR(200) NULL,
	PRIMARY KEY(prot_id, stage, term),
	KEY(phylostrata),
	KEY(ti),
	KEY(species_name)
    ) }, $map_href->{dbh}->quote_identifier($expr_tbl) );
	_create_table( { table_name => $expr_tbl, dbh => $map_href->{dbh}, query => $create_expr } );
	$log->trace("Report: $create_expr");

	# load expression file
    my $load_expr = qq{
    LOAD DATA INFILE '$map_href->{expr_file}'
    INTO TABLE $expr_tbl } . q{ FIELDS TERMINATED BY '\t'
    LINES TERMINATED BY '\n'
	(stage, prot_id, term)
    };
	$log->trace("Report: $load_expr");
	my $rows_expr;
	eval { $rows_expr = $map_href->{dbh}->do( $load_expr ) };
	$log->error( "Action: loading into table $expr_tbl failed: $@" ) if $@;
	$log->debug( "Action: table $expr_tbl inserted $rows_expr rows!" ) unless $@;

	# update expression table with map
	_update_term_with_map($expr_tbl, $map_tbl, $map_href->{dbh});

	# drop map table
	my $drop_map_q = sprintf( qq{
		DROP TABLE IF EXISTS %s
	}, $map_href->{dbh}->quote_identifier($map_tbl) );
	eval { $map_href->{dbh}->do( $drop_map_q ) };
	$log->error( "Action: drop table $map_tbl failed: $@" ) if $@;
	$log->debug( "Action: table $map_tbl dropped!" ) unless $@;
	

	# rename expr_tbl to map_tbl
	my $rename_q = sprintf( qq{
		RENAME TABLE %s TO %s
	}, $map_href->{dbh}->quote_identifier($expr_tbl), $map_href->{dbh}->quote_identifier($map_tbl) );
	eval { $map_href->{dbh}->do( $rename_q ) };
	$log->error( "Action: renaming table $expr_tbl into $map_tbl failed: $@" ) if $@;
	$log->debug( "Action: table $expr_tbl renamed into $map_tbl!" ) unless $@;

    return $map_tbl;
}













1;
__END__

=encoding utf-8

=head1 NAME

StratiphyParallel - It's modulino to run PhyloStrat in parallel, collect information from maps and run multiple log-odds analyses on them.

=head1 SYNOPSIS

    # recommended usage (all modes can use options from config file or command line or mixed)
    # run Phylostrat in parallel
    StratiphyParallel.pm --mode=stratiphy_parallel --infile /home/msestak/prepare_blast/out/dm_plus/dm_all_plus_14_12_2015 --tax_id=7227 -v -v

    # collect phylo summary maps
    StratiphyParallel.pm --mode=collect_maps --in=/home/msestak/prepare_blast/out/dr_plus/ --outfile=/home/msestak/prepare_blast/out/dr_04_02_2016.xlsx -v -v

    # import maps and one term and calculate hypergeometric test for every term map
    StratiphyParallel.pm --mode=multi_maps --term_sub_name=_term_prepare --column_list=gene_id,prot_id -i ./data/ -d dm_multi -if ./data/dm_oxphos.txt -o ./data/ -of ./data/dm_oxphos_17_02_2016.xlsx -v



=head1 DESCRIPTION

StratiphyParallel is modulino to run PhyloStrat in parallel, collect information from maps and run multiple log-odds analyses on them.

 --mode=mode                   Description
 --mode=stratiphy_parallel     - runs Phylostrat in parallel with fork
 --mode=collect_maps           - collects phylo summary maps
 --mode=multi_maps             - collects maps and one term and calculates hypergeometric test

 For help write:
 StratiphyParallel.pm -h
 StratiphyParallel.pm -m

=head2 MODES

=over 4

=item stratiphy_parallel

 # options from command line
 StratiphyParallel.pm --mode=stratiphy_parallel --infile /home/msestak/prepare_blast/out/dm_plus/dm_all_plus_14_12_2015 --max_process=12 --e_value=3-30 --tax_id=7227 --nodes=/home/msestak/dropbox/Databases/db_02_09_2015/data/nr_raw/nodes.dmp.fmt.new.sync --names=/home/msestak/dropbox/Databases/db_02_09_2015/data/nr_raw/names.dmp.fmt.new -v -v

 # options from config
 StratiphyParallel.pm --mode=stratiphy_parallel

Runs Phylostrat in parallel with fork (defined by --max_process). It requires names (--names), nodes (--nodes) and blast output (--infile) files. It also needs tax_id (--tax_id) of species and range of BLAST e-values (--e_values) for which to run Phylostrat.


=item collect_maps

 # options from command line
 StratiphyParallel.pm --mode=collect_maps --in=/home/msestak/prepare_blast/out/dr_plus/ --outfile=/home/msestak/prepare_blast/out/dr_04_02_2016.xlsx -v -v

 # options from config
 StratiphyParallel.pm --mode=collect_maps

Collects phylo summary maps, compares them and writes them to Excel file. It creates chart for each map and also summary.

=item multi_maps

 # options from command line
 StratiphyParallel.pm --mode=multi_maps --term_sub_name=_term_prepare --column_list=gene_id,prot_id -i ./data/ -d dm_multi -if ./data/dm_oxphos.txt -o ./data/ -of ./data/dm_oxphos_17_02_2016.xlsx -ho localhost -p msandbox -u msandbox -po 5625 -s /tmp/mysql_sandbox5625.sock

 # options from config
 StratiphyParallel.pm --mode=multi_maps --term_sub_name=_term_prepare --column_list=gene_id,prot_id -i ./data/ -d dm_multi -if ./data/dm_oxphos.txt -o ./data/ -of ./data/dm_oxphos_17_02_2016.xlsx -v
 StratiphyParallel.pm --mode=multi_maps --term_sub=_term_prepare --column_list=gene_name,prot_id,extra --map_sub=_import_map_with_expr --expr_file=/msestak/workdir/dm_insitu/maps/annot_insitu.txt -i /msestak/workdir/dm_insitu/maps/ -d dm_multi -if /msestak/workdir/dm_insitu/maps/ectoderm.txt -o ./data/ -of /msestak/workdir/dm_insitu/maps/dm_ectoderm_22_02_2016.xlsx -v

Imports multiple maps and connects them with association term, calculates hypergeometric test and writes log-odds, hypergeometric test and charts to Excel. Input file is term file, term_sub_name is name of subroutine that will load term table and column_list is list of columns in term file to import. Out is R working directory and outfile is final Excel file.

=back

=head1 CONFIGURATION

All configuration is set in stratiphyparallel.cnf that is found in ./lib directory (it can also be set with --config option on command line). It follows L<< Config::Std|https://metacpan.org/pod/Config::Std >> format and rules.
Example:

 [General]
 #best to specify on command line because it changes
 #in          = /home/msestak/prepare_blast/out/dr_plus/
 #out         = .
 #infile      = /home/msestak/prepare_blast/out/dm_plus/dm_all_plus_14_12_2015
 #outfile     = /home/msestak/prepare_blast/out/dr_04_02_2016.xlsx
 
 [Stratiphy]
 max_process = 12
 e_value     = 3-30
 #tax_id      = 7227
 nodes       = /home/msestak/dropbox/Databases/db_02_09_2015/data/nr_raw/nodes.dmp.fmt.new.sync
 names       = /home/msestak/dropbox/Databases/db_02_09_2015/data/nr_raw/names.dmp.fmt.new
 
 [Maps]
 term_sub_name = _term_prepare
 map_sub_name  = _import_map_with_expr
 column_list   = gene_name,prot_id,extra
 expr_file     = /msestak/workdir/dm_insitu/maps/annot_insitu.txt
 
 [Database]
 host     = localhost
 database = pharyngula
 user     = msandbox
 password = msandbox
 port     = 5625
 socket   = /tmp/mysql_sandbox5625.sock
 
 [PS]
 1   =  1
 2   =  2
 3   =  2
 4   =  2
 5   =  3
 6   =  3
 7   =  3
 8   =  3
 9   =  4
 10  =  5
 11  =  5
 12  =  6
 13  =  7
 14  =  7
 15  =  7
 16  =  8
 17  =  8
 18  =  9
 19  =  9
 20  =  10
 21  =  10
 22  =  10
 23  =  10
 24  =  10
 25  =  10
 26  =  10
 27  =  10
 28  =  11
 29  =  11
 30  =  11
 31  =  11
 32  =  11
 33  =  11
 34  =  11
 35  =  11
 36  =  11
 37  =  11
 38  =  11
 39  =  11
 40  =  11
 41  =  11
 42  =  11
 43  =  11
 44  =  11
 45  =  11
 46  =  11
 47  =  12
 
 [TI]
 131567   =  131567
 2759     =  2759
 1708629  =  2759
 1708631  =  2759
 33154    =  33154
 1708671  =  33154
 1708672  =  33154
 1708673  =  33154
 33208    =  33208
 6072     =  6072
 1708696  =  6072
 33213    =  33213
 33317    =  33317
 1206794  =  33317
 88770    =  33317
 6656     =  6656
 197563   =  6656
 197562   =  197562
 6960     =  197562
 50557    =  50557
 85512    =  50557
 7496     =  50557
 33340    =  50557
 1708734  =  50557
 33392    =  50557
 1708735  =  50557
 1708736  =  50557
 7147     =  7147
 7203     =  7147
 43733    =  7147
 480118   =  7147
 480117   =  7147
 43738    =  7147
 43741    =  7147
 43746    =  7147
 7214     =  7147
 43845    =  7147
 46877    =  7147
 46879    =  7147
 186285   =  7147
 7215     =  7147
 32341    =  7147
 1708740  =  7147
 32346    =  7147
 32351    =  7147
 1708742  =  7147
 7227     =  7227
 
 [PSNAME]
 cellular_organisms  =  cellular_organisms
 Eukaryota           =  Eukaryota
 Unikonta            =  Eukaryota
 Apusozoa/Opisthokonta  =  Eukaryota
 Opisthokonta        =  Opisthokonta
 Holozoa             =  Opisthokonta
 Filozoa             =  Opisthokonta
 Metazoa/Choanoflagellida  =  Opisthokonta
 Metazoa             =  Metazoa
 Eumetazoa           =  Eumetazoa
 Cnidaria/Bilateria  =  Eumetazoa
 Bilateria           =  Bilateria
 Protostomia         =  Protostomia
 Ecdysozoa           =  Protostomia
 Panarthropoda       =  Protostomia
 Arthropoda          =  Arthropoda
 Mandibulata         =  Arthropoda
 Pancrustacea        =  Pancrustacea
 Hexapoda            =  Pancrustacea
 Insecta             =  Insecta
 Dicondylia          =  Insecta
 Pterygota           =  Insecta
 Neoptera            =  Insecta
 Phthiraptera/Endopterygota  =  Insecta
 Endopterygota       =  Insecta
 Coleoptera/Amphiesmenoptera/Diptera  =  Insecta
 Amphiesmenoptera/Diptera  =  Insecta
 Diptera             =  Diptera
 Brachycera          =  Diptera
 Muscomorpha         =  Diptera
 Eremoneura          =  Diptera
 Cyclorrhapha        =  Diptera
 Schizophora         =  Diptera
 Acalyptratae        =  Diptera
 Ephydroidea         =  Diptera
 Drosophilidae       =  Diptera
 Drosophilinae       =  Diptera
 Drosophilini        =  Diptera
 Drosophilina        =  Diptera
 Drosophiliti        =  Diptera
 Drosophila          =  Diptera
 Sophophora          =  Diptera
 melanogaster_group/obscura_group  =  Diptera
 melanogaster_group  =  Diptera
 melanogaster_subgroup  =  Diptera
 melanogaster/simulans/sechellia  =  Diptera
 Drosophila_melanogaster  =  Drosophila_melanogaster


=head1 LICENSE

Copyright (C) Martin Sebastijan Šestak.

This library is free software; you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation; either version 3, or (at your option) any later version.

StratiphyParallel is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU General Public License for more details.

=head1 AUTHOR

Martin Sebastijan Šestak
mocnii E<lt>msestak@irb.hrE<gt>

=cut


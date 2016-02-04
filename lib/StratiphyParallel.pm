#!/usr/bin/env perl
package StratiphyParallel;
use 5.010001;
use strict;
use warnings;
use File::Spec::Functions qw(:ALL);
use Path::Tiny;
use Carp;
use Getopt::Long;
use Pod::Usage;
use Capture::Tiny qw/capture/;
use Data::Dumper;
#use Regexp::Debugger;
use Log::Log4perl;
use File::Find::Rule;
use Config::Std { def_sep => '=' };   #MySQL uses =
use Parallel::ForkManager;
use Excel::Writer::XLSX;

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
    init_logging($verbose);
    ##########################
    # ... in some function ...
    ##########################
    my $log = Log::Log4perl::get_logger("main");

    # Logs both to Screen and File appender
    $log->info("This is start of logging for $0");
    $log->trace("This is example of trace logging for $0");

    #get dump of param_href if -v (verbose) flag is on (for debugging)
    my $dump_print = sprintf( Dumper($param_href) ) if $verbose;
    $log->debug( '$param_href = ', "$dump_print" ) if $verbose;

    #call write modes (different subs that print different jobs)
    my %dispatch = (
        stratiphy_parallel           => \&stratiphy_parallel,              # run Phylostrat in parallel
		collect_maps                 => \&collect_maps,                    # collect maps in Excel file

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
	#print 'config:', Dumper(\%config);
	#push all options into one hash no matter the section
	my %opts;
	foreach my $key (keys %config) {
		%opts = (%opts, %{ $config{$key} });
	}
	# put config location to %opts
	$opts{config} = $config_file;
	#say 'opts:', Dumper(\%opts);

	#cli part
	my @arg_copy = @ARGV;
	my (%cli, @mode);
	$cli{quiet} = 0;
	$cli{verbose} = 0;

	#mode, quiet and verbose can only be set on command line
    GetOptions(
        'help|h'        => \$cli{help},
        'man|m'         => \$cli{man},
		'config|cnf=s'  => \$cli{config},
        'in|i=s'        => \$cli{in},
        'infile|if=s'   => \$cli{infile},
        'out|o=s'       => \$cli{out},
        'outfile|of=s'  => \$cli{outfile},


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
		print STDERR 'My @ARGV: {', join( "} {", @arg_copy ), '}', "\n";
		#no warnings 'uninitialized';
		print STDERR "Extra options from config:", Dumper(\%opts);
	
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
# Parameters : doesn't need parameters (logfile is in same directory and same name as script -pl +log
# Throws     : croaks if it receives parameters
# Comments   : used to setup a logging framework
# See Also   : Log::Log4perl at https://metacpan.org/pod/Log::Log4perl
sub init_logging {
    croak 'init_logging() needs verbose parameter' unless @_ == 1;
    my ($verbose) = @_;

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
      log4perl.category.main              = $log_level, Logfile, Screen
     
      log4perl.appender.Logfile           = Log::Log4perl::Appender::File
      log4perl.appender.Logfile.Threshold = TRACE
      log4perl.appender.Logfile.filename  = $logfile
      log4perl.appender.Logfile.mode      = append
      log4perl.appender.Logfile.autoflush = 1
      log4perl.appender.Logfile.umask     = 0022
      log4perl.appender.Logfile.header_text = INVOCATION:$0 @ARGV
      log4perl.appender.Logfile.layout    = Log::Log4perl::Layout::PatternLayout
      log4perl.appender.Logfile.layout.ConversionPattern = [%d{yyyy/MM/dd HH:mm:ss,SSS}]%5p> %M line:%L==>%m%n
     
      log4perl.appender.Screen            = Log::Log4perl::Appender::ScreenColoredLevels
      log4perl.appender.Screen.stderr     = 1
      log4perl.appender.Screen.layout     = Log::Log4perl::Layout::PatternLayout
      log4perl.appender.Screen.layout.ConversionPattern  = [%d{yyyy/MM/dd HH:mm:ss,SSS}]%5p> %M line:%L==>%m%n
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
    my $USER     = defined $param_href->{USER}     ? $param_href->{USER}     : 'msandbox';
    my $PASSWORD = defined $param_href->{PASSWORD} ? $param_href->{PASSWORD} : 'msandbox';
	
	if( $osname eq 'MSWin32' ) {	  
		my $HOST     = defined $param_href->{HOST}     ? $param_href->{HOST}     : 'localhost';
    	my $DATABASE = defined $param_href->{DATABASE} ? $param_href->{DATABASE} : 'blastdb';
    	my $PORT     = defined $param_href->{PORT}     ? $param_href->{PORT}     : 3306;
    	my $prepare  = 1;   #server side prepare is ON
		my $use_res  = 0;   #1 doesn't work with selectall_aref (O means it catches in application)

    	$data_source = "DBI:mysql:database=$DATABASE;host=$HOST;port=$PORT;mysql_server_prepare=$prepare;mysql_use_result=$use_res";
	}
	elsif ( $osname eq 'linux' ) {
		my $HOST     = defined $param_href->{HOST}     ? $param_href->{HOST}     : 'localhost';
    	my $DATABASE = defined $param_href->{DATABASE} ? $param_href->{DATABASE} : 'blastdb';
    	my $PORT     = defined $param_href->{PORT}     ? $param_href->{PORT}     : 3306;
    	my $SOCKET   = defined $param_href->{SOCKET}   ? $param_href->{SOCKET}   : '/var/lib/mysql/mysql.sock';
    	my $prepare  = 1;   #server side prepare is ON
		my $use_res  = 0;   #1 doesn't work with selectall_aref (O means it catches in application)

    	$data_source = "DBI:mysql:database=$DATABASE;host=$HOST;port=$PORT;mysql_socket=$SOCKET;mysql_server_prepare=$prepare;mysql_use_result=$use_res";
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
    my $dbh = DBI->connect( $data_source, $USER, $PASSWORD, \%conn_attrs );

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
	my @maps = File::Find::Rule->file()
                               ->name( '*.phmap_sum' )
                               ->in( $in );
	my @sorted_maps =
    map { $_->[0] }                                 #returns back to file path format
    sort { $a->[1] <=> $b->[1] }                    #compares numbers at second place in aref
    map { [ $_, /\A(?:\D+)(\d+)\.phmap_sum\z/ ] }   #puts number at second place of aref
    @maps;
    $log->trace( 'Array @sorted_maps (files in input directory sorted): ', "\n", join("\n", @sorted_maps) );

	# count number of lines in map and extract phylostrata
	my $test_map = $sorted_maps[0];
	my ($test_phylostrata, $test_tax_id, $test_phylostrata_name) = _test_map($test_map);
	my @test_phylostrata = @$test_phylostrata;
	my $lines = @test_phylostrata;
	my @test_tax_id = @$test_tax_id;
	my @test_phylostrata_name = @$test_phylostrata_name;

	# calculate offsets in comparison to first map (1e-3)
	my $diff_start = 3;                      #third line from top
	my $diff_end   = $lines + $diff_start;   #num of lines in file + 3

    # Create a new Excel workbook
	# !!! $filename_excel needs to be doubleQUOTED else it does not WORK (->new("$filename_excel"))
	if (-f $outfile) {
		unlink $outfile and $log->warn( "Action: unlinked $outfile" );
	}
    my $workbook = Excel::Writer::XLSX->new("$outfile") or $log->logcroak( "Problems creating new Excel file: $!" );

    # Add a worksheet which will hold all of the maps (DATA for maps)
	my $ps_sheet       = $workbook->add_worksheet('DATA');
    $log->debug( 'Excel file: ',      $outfile );
    $log->debug( 'Excel workbook: ',  $workbook );
	$log->debug( 'Excel worksheet: ', $ps_sheet );

    # Add a Format (bold black)
    my $header = $workbook->add_format(); $header->set_bold(); $header->set_color('black');
    # Add a Format (bold red)
    my $red = $workbook->add_format(); $red->set_bold(); $red->set_color('red'); 
	# Add a Format (red)
    my $red_val = $workbook->add_format(); $red_val->set_color('red');
	# Add a Format (green)
    my $green_val = $workbook->add_format(); $green_val->set_color('green');
	# Add a Format (percentage)
    my $format_perc = $workbook->add_format(); $format_perc->set_num_format( '0.00%;[Red]-0.00%;0.00%' ); $green_val->set_color('green');

    #add a counter for different files and lines
    state $line_counter = 0;

	# run for each map
	foreach my $map (@sorted_maps) {

		#skip non-uniform maps
		next if $map =~ /2014|2015|2016|2017/;

		# Add a caption to each worksheet (with name of map)
		my $map_name = path($map)->basename;
    	$ps_sheet->write( $line_counter, 0, $map_name, $red );
    	$line_counter++;

		# here comes header
		$ps_sheet->write( $line_counter, 0,  'phylostrata',      $header );
    	$ps_sheet->write( $line_counter, 1,  'tax_id',           $header );
    	$ps_sheet->write( $line_counter, 2,  'phylostrata_name', $header );
    	$ps_sheet->write( $line_counter, 3,  'genes',            $header );
    	$ps_sheet->write( $line_counter, 4,  '% of genes',       $header );
    	$ps_sheet->write( $line_counter, 5,  'diff in num',      $header );
    	$ps_sheet->write( $line_counter, 6,  'diff in %',        $header );

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
				#$ps_sheet->write_formula( $tmp_cnt_here - 1, 5, "{=D$tmp_cnt_here - D$tmp_cnt_diff}" );
				$ps_sheet->write_formula( $tmp_cnt_here - 1, 6, "{=E$tmp_cnt_here - E$tmp_cnt_diff}", $format_perc );
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
				$ps_sheet->write_col( "A$line_counter", \@phylostrata );
				$ps_sheet->write_col( "B$line_counter", \@tax_id );
				$ps_sheet->write_col( "C$line_counter", \@phylostrata_name );
				$ps_sheet->write_col( "D$line_counter", \@genes );
				$ps_sheet->write_col( "E$line_counter", \@perc_of_genes );
				my $end = $line_counter + @phylostrata;
				$ps_sheet->write_array_formula( "F$line_counter:F$end",    "{=(D$line_counter:D$end - D$diff_start:D$diff_end)}" );
				#$ps_sheet->write_array_formula( "G$line_counter:G$end",    "{=(E$line_counter:E$end - E$diff_start:E$diff_end)}", $format_perc );
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
				$ps_sheet->write_col( "A$line_counter", $new_phylostrata_aref );
				$ps_sheet->write_col( "B$line_counter", \@tax_id );
				$ps_sheet->write_col( "C$line_counter", \@phylostrata_name );
				$ps_sheet->write_col( "D$line_counter", \@genes );
				$ps_sheet->write_col( "E$line_counter", \@perc_of_genes );
				my $end = $line_counter + @$new_phylostrata_aref;
				$ps_sheet->write_array_formula( "F$line_counter:F$end",    "{=(D$line_counter:D$end - D$diff_start:D$diff_end)}" );

				#increase line_counter for number of indexes
				$line_counter += scalar @$empty_index_aref;
			}
	
			# calculate sum of genes
			$line_counter += $. - 1;  # for length of file
			my $sum_end = $line_counter;
			$ps_sheet->write_formula( $line_counter, 3, "{=SUM(D$sum_start:D$sum_end)}" );   #curly braces to write result to Excel

			# write more genes in green and less in red
			# Write a conditional format over a range.
			$ps_sheet->conditional_formatting( "F$sum_start:F$sum_end",
			    {
			        type     => 'cell',
			        criteria => '>',
			        value    => 0,
			        format   => $green_val,
			    }
			);
 
			# Write another conditional format over the same range.
			$ps_sheet->conditional_formatting( "F$sum_start:F$sum_end",
			    {
			        type     => 'cell',
			        criteria => '<',
			        value    => 0,
			        format   => $red_val,
			    }
			);
	
			# write conditional format for percentage
			$ps_sheet->conditional_formatting( "G$sum_start:G$sum_end",
			    {
			        type     => 'cell',
			        criteria => '>',
			        value    => 0,
			        format   => $green_val,
			    }
			);

			# make space for next map
			$line_counter += 2;      # +2 for next map name
	
		}   #end local $.
	}   # end foreach map

	$workbook->close() or $log->logdie( "Error closing Excel file: $!" );

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

    if (@$test_ref == @$yref) {
		die "they match in length";
	}
	else {
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
	}
    return \@new_phylostrata, \@empty_index;
}








1;
__END__

=encoding utf-8

=head1 NAME

StratiphyParallel - It's modulino to run PhyloStrat in parallel, collect information from maps and run multiple log-odds analyses on them.

=head1 SYNOPSIS

    # recommended usage (all modes can use options from config file or command line or mixed)
	# run Phylostrat in parallel
    StratiphyParallel.pm --mode=stratiphy_parallel

    # collect phylo summary maps
    StratiphyParallel.pm --mode=collect_maps --in=/home/msestak/prepare_blast/out/dr_plus/ --outfile=/home/msestak/prepare_blast/out/dr_04_02_2016.xlsx -v -v



=head1 DESCRIPTION

StratiphyParallel is modulino to run PhyloStrat in parallel, collect information from maps and run multiple log-odds analyses on them.

 --mode=mode                   Description
 --mode=stratiphy_parallel     - runs Phylostrat in parallel with fork
 --mode=collect_maps           - collects phylo summary maps
 
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

Collects phylo summary maps, compares them and writes them to Excel file.

=back

=head1 CONFIGURATION

All configuration in set in stratiphyparallel.cnf that is found in ./lib directory (it can also be set with --config option on command line). It follows L<< Config::Std|https://metacpan.org/pod/Config::Std >> format and rules.
Example:

 [General]
 nodes       = /home/msestak/dropbox/Databases/db_02_09_2015/data/nr_raw/nodes.dmp.fmt.new.sync
 names       = /home/msestak/dropbox/Databases/db_02_09_2015/data/nr_raw/names.dmp.fmt.new
 in          = /home/msestak/prepare_blast/out/dr_plus/
 #out         = .
 infile      = /home/msestak/prepare_blast/out/dm_plus/dm_all_plus_14_12_2015
 outfile     = /home/msestak/prepare_blast/out/dr_04_02_2016.xlsx
 max_process = 12
 e_value     = 3-30
 tax_id      = 7227
 
 [Database]
 host     = localhost
 database = test
 user     = msandbox
 password = msandbox
 port     = 5627
 socket   = /tmp/mysql_sandbox5627.sock

=head1 LICENSE

Copyright (C) Martin Sebastijan Šestak.

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=head1 AUTHOR

Martin Sebastijan Šestak
mocnii E<lt>msestak@irb.hrE<gt>

=cut


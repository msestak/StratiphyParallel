requires 'perl', '5.008001';

on 'test' => sub {
    requires 'Test::More', '0.98';
};

requires 'strict';
requires 'warnings';
requires 'autodie';
requires 'Exporter';
requires 'Carp';
requires 'Data::Dumper';
requires 'Path::Tiny';
requires 'DBI';
requires 'DBD::mysql';
requires 'Getopt::Long';
requires 'Pod::Usage';
requires 'Capture::Tiny';
requires 'Log::Log4perl';
requires 'File::Find::Rule';
requires 'Parallel::ForkManager';
requires 'Config::Std';
requires 'Excel::Writer::XLSX';
requires 'DBI';
requires 'DBD::mysql';

author_requires 'Term::ReadKey';
author_requires 'Regexp::Debugger';

# NAME

StratiphyParallel - It's modulino to run PhyloStrat in parallel, collect information from maps and run multiple log-odds analyses on them.

# SYNOPSIS

    StratiphyParallel.pm /home/msestak/prepare_blast/out/mm_plus/mm_all_plus_16_12_2015

# DESCRIPTION

StratiphyParallel is modulino to run PhyloStrat in parallel, collect information from maps and run multiple log-odds analyses on them.

    --mode=mode                Description
    --mode=stratiphy_parallel     installs MySQL::Sandbox and prompts for modification of .bashrc
    
    For help write:
    StratiphyParallel.pm -h
    StratiphyParallel.pm -m

## MODES

- stratiphy\_parallel

        # options from command line
        StratiphyParallel.pm --mode=stratiphy_parallel --infile /home/msestak/prepare_blast/out/dm_plus/dm_all_plus_14_12_2015 --max_process=12 --e_value=3-30 --tax_id=7227 --nodes=/home/msestak/dropbox/Databases/db_02_09_2015/data/nr_raw/nodes.dmp.fmt.new.sync --names=/home/msestak/dropbox/Databases/db_02_09_2015/data/nr_raw/names.dmp.fmt.new -v -v

        # options from config
        StratiphyParallel.pm --mode=stratiphy_parallel

    Runs Phylostrat in parallel with fork (defined by --max\_process). It requires names (--names), nodes (--nodes) and blast output (--infile) files. It also needs tax\_id (--tax\_id) of species and range of BLAST e-values (--e\_values) for which to run Phylostrat.

# CONFIGURATION

All configuration in set in stratiphyparallel.cnf that is found in ./lib directory (it can also be set with --config option on command line). It follows [Config::Std](https://metacpan.org/pod/Config::Std) format and rules.
Example:

    [General]
    nodes       = /home/msestak/dropbox/Databases/db_02_09_2015/data/nr_raw/nodes.dmp.fmt.new.sync
    names       = /home/msestak/dropbox/Databases/db_02_09_2015/data/nr_raw/names.dmp.fmt.new
    #in          = 
    #out         = .
    infile      = /home/msestak/prepare_blast/out/dm_plus/dm_all_plus_14_12_2015
    #outfile     = 
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

# LICENSE

Copyright (C) Martin Sebastijan Šestak.

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

# AUTHOR

Martin Sebastijan Šestak
mocnii <msestak@irb.hr>

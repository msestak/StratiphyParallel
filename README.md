# NAME

StratiphyParallel - It's modulino to run PhyloStrat in parallel, collect information from maps and run multiple log-odds analyses on them.

# SYNOPSIS

    # recommended usage (all modes can use options from config file or command line or mixed)
    # run Phylostrat in parallel
    StratiphyParallel.pm --mode=stratiphy_parallel --infile /home/msestak/prepare_blast/out/dm_plus/dm_all_plus_14_12_2015 --tax_id=7227 -v -v

    # collect phylo summary maps
    StratiphyParallel.pm --mode=collect_maps --in=/home/msestak/prepare_blast/out/dr_plus/ --outfile=/home/msestak/prepare_blast/out/dr_04_02_2016.xlsx -v -v

    # import maps and one term and calculate hypergeometric test for every term map
    StratiphyParallel.pm --mode=multi_maps --term_sub=_term_prepare --column_list=gene_id,prot_id -i ./data/ -d dm_multi -if ./data/dm_oxphos.txt -o ./data/ -of ./data/dm_oxphos_17_02_2016.xlsx -v

# DESCRIPTION

StratiphyParallel is modulino to run PhyloStrat in parallel, collect information from maps and run multiple log-odds analyses on them.

    --mode=mode                   Description
    --mode=stratiphy_parallel     - runs Phylostrat in parallel with fork
    --mode=collect_maps           - collects phylo summary maps
    --mode=multi_maps             - collects maps and one term and calculates hypergeometric test

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

- collect\_maps

        # options from command line
        StratiphyParallel.pm --mode=collect_maps --in=/home/msestak/prepare_blast/out/dr_plus/ --outfile=/home/msestak/prepare_blast/out/dr_04_02_2016.xlsx -v -v

        # options from config
        StratiphyParallel.pm --mode=collect_maps

    Collects phylo summary maps, compares them and writes them to Excel file. It creates chart for each map and also summary.

- multi\_maps

        # options from command line
        StratiphyParallel.pm --mode=multi_maps --term_sub=_term_prepare --column_list=gene_id,prot_id -i ./data/ -d dm_multi -if ./data/dm_oxphos.txt -o ./data/ -of ./data/dm_oxphos_17_02_2016.xlsx -ho localhost -p msandbox -u msandbox -po 5625 -s /tmp/mysql_sandbox5625.sock

        # options from config
        StratiphyParallel.pm --mode=multi_maps --term_sub=_term_prepare --column_list=gene_id,prot_id -i ./data/ -d dm_multi -if ./data/dm_oxphos.txt -o ./data/ -of ./data/dm_oxphos_17_02_2016.xlsx -v

    Imports multiple maps and connects them with association term, calculates hypergeometric test and writes log-odds, hypergeometric test and charts to Excel. Input file is term file, term\_sub is name of subroutine that will load term table and column\_list is list of columns in term file to import. Out is R working directory and outfile is final Excel file.

# CONFIGURATION

All configuration is set in stratiphyparallel.cnf that is found in ./lib directory (it can also be set with --config option on command line). It follows [Config::Std](https://metacpan.org/pod/Config::Std) format and rules.
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
    term_sub    = _term_prepare
    column_list = gene_id,prot_id
    
    [Database]
    host     = localhost
    database = pharyngula
    user     = msandbox
    password = msandbox
    port     = 5625
    socket   = /tmp/mysql_sandbox5625.sock

# LICENSE

Copyright (C) Martin Sebastijan Šestak.

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

# AUTHOR

Martin Sebastijan Šestak
mocnii <msestak@irb.hr>

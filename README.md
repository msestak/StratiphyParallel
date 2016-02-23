# NAME

StratiphyParallel - It's modulino to run PhyloStrat in parallel, collect information from maps and run multiple log-odds analyses on them.

# SYNOPSIS

    # recommended usage (all modes can use options from config file or command line or mixed)
    # run Phylostrat in parallel
    StratiphyParallel.pm --mode=stratiphy_parallel --infile /home/msestak/prepare_blast/out/dm_plus/dm_all_plus_14_12_2015 --tax_id=7227 -v -v

    # collect phylo summary maps
    StratiphyParallel.pm --mode=collect_maps --in=/home/msestak/prepare_blast/out/dr_plus/ --outfile=/home/msestak/prepare_blast/out/dr_04_02_2016.xlsx -v -v

    # import maps and one term and calculate hypergeometric test for every term map
    StratiphyParallel.pm --mode=multi_maps --term_sub_name=_term_prepare --column_list=gene_id,prot_id -i ./data/ -d dm_multi -if ./data/dm_oxphos.txt -o ./data/ -of ./data/dm_oxphos_17_02_2016.xlsx -v

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
        StratiphyParallel.pm --mode=multi_maps --term_sub_name=_term_prepare --column_list=gene_id,prot_id -i ./data/ -d dm_multi -if ./data/dm_oxphos.txt -o ./data/ -of ./data/dm_oxphos_17_02_2016.xlsx -ho localhost -p msandbox -u msandbox -po 5625 -s /tmp/mysql_sandbox5625.sock

        # options from config
        StratiphyParallel.pm --mode=multi_maps --term_sub_name=_term_prepare --column_list=gene_id,prot_id -i ./data/ -d dm_multi -if ./data/dm_oxphos.txt -o ./data/ -of ./data/dm_oxphos_17_02_2016.xlsx -v
        StratiphyParallel.pm --mode=multi_maps --term_sub=_term_prepare --column_list=gene_name,prot_id,extra --map_sub=_import_map_with_expr --expr_file=/msestak/workdir/dm_insitu/maps/annot_insitu.txt -i /msestak/workdir/dm_insitu/maps/ -d dm_multi -if /msestak/workdir/dm_insitu/maps/ectoderm.txt -o ./data/ -of /msestak/workdir/dm_insitu/maps/dm_ectoderm_22_02_2016.xlsx -v

    Imports multiple maps and connects them with association term, calculates hypergeometric test and writes log-odds, hypergeometric test and charts to Excel. Input file is term file, term\_sub\_name is name of subroutine that will load term table and column\_list is list of columns in term file to import. Out is R working directory and outfile is final Excel file.

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

# LICENSE

Copyright (C) Martin Sebastijan Šestak.

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

# AUTHOR

Martin Sebastijan Šestak
mocnii <msestak@irb.hr>

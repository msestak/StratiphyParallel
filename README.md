# NAME

StratiphyParallel - It's barebones modulino to build custom scripts. Useful snipets go here.

# SYNOPSIS

    StratiphyParallel.pm --mode=install_sandbox --sandbox=/msestak/sandboxes/ --opt=/msestak/opt/mysql/

# DESCRIPTION

StratiphyParallel is modulino used as starting point for modulino development. It includes config, command-line and logging management.

    --mode=mode                Description
    --mode=install_sandbox     installs MySQL::Sandbox and prompts for modification of .bashrc
    
    For help write:
    StratiphyParallel.pm -h
    StratiphyParallel.pm -m

## MODES

- install\_sandbox

        # options from command line
        StratiphyParallel.pm --mode=install_sandbox --sandbox=$HOME/sandboxes/ --opt=$HOME/opt/mysql/

        # options from config
        StratiphyParallel.pm --mode=install_sandbox

    Install MySQL::Sandbox, set environment variables (SANDBOX\_HOME and SANBOX\_BINARY) and create these directories if needed.

# CONFIGURATION

All configuration in set in barebones.cnf that is found in ./lib directory (it can also be set with --config option on command line). It follows [Config::Std](https://metacpan.org/pod/Config::Std) format and rules.
Example:

    [General]
    sandbox  = /home/msestak/sandboxes
    opt      = /home/msestak/opt/mysql
    out      = /msestak/gitdir/StratiphyParallel
    infile   = $HOME/mysql-5.6.27-linux-glibc2.5-x86_64.tar.gz
    
    [Database]
    host     = localhost
    database = test
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

#!/usr/bin/perl

use strict;
use warnings;
use 5.006;
use ExtUtils::MakeMaker;

WriteMakefile(
    NAME             => "piggly",
    DISTNAME         => "piggly",    
    AUTHOR           => "Piggly Core Developers",
    VERSION_FROM     => 'lib/piggly.pm',
    LICENSE          => "perl",
    MIN_PERL_VERSION => "5.006",
    EXE_FILES => [
        "bin/piggly",
    ],
);


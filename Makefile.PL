use 5.022;
use strict;
use warnings;
use ExtUtils::MakeMaker;

WriteMakefile(
    NAME             => 'AnyEvent::App::PerlLive',
    AUTHOR           => 'vividsnow',
    VERSION_FROM     => 'lib/AnyEvent/App/PerlLive.pm',
    ABSTRACT_FROM    => 'lib/AnyEvent/App/PerlLive.pm',
    LICENSE          => 'gpl_3',
    EXE_FILES        => ['perl-live.pl', 'perl-live-mcp.pl'],
    PREREQ_PM        => {
        'AnyEvent'       => '7.17',
        'PadWalker'      => '2.5',
        'Package::Stash' => '0.40',
        'JSON::PP'       => '0',
    },
    TEST_REQUIRES    => {
        'Test::More'     => '0.98',
    },
    META_MERGE       => {
        'meta-spec' => { version => 2 },
        resources   => {
            repository => {
                type => 'git',
                url  => 'https://github.com/vividsnow/perl-live.git',
                web  => 'https://github.com/vividsnow/perl-live',
            },
            bugtracker => {
                web => 'https://github.com/vividsnow/perl-live/issues',
            },
        },
        recommends => {
            'EV'                 => '0',
            'Package::Stash::XS' => '0',
        },
    },
    test => {
        TESTS => 'test/protocol.t test/mcp.t',
    },
    clean => { FILES => 'AnyEvent-App-PerlLive-*' },
);

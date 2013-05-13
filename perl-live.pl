use v5.12;
use warnings;
use AnyEvent;
use PadWalker 'peek_my';
use Package::Stash;
use Getopt::Std 'getopts';

getopts( g => my $Zinput = {} );
my $Zstash = Package::Stash->new('main');

my $Zwatcher = AE::io *STDIN, 0, sub {
    state ($Zbuf, $Zcontext);
    if (eof()) {
        scalar <>;
        eval substr($Zbuf, 0, length $Zbuf, '').'; $Zcontext = peek_my(0)';
        map { 
            $Zstash->add_symbol($_, $Zcontext->{$_}) 
        } grep { 
            !($_ ~~ [qw($Zbuf $Zcontext $Zinput $Zstash)])
        } keys$Zcontext if $Zinput->{g};
        warn if $@;
    } else { $Zbuf .= scalar <> }
};
AE::cv->recv;

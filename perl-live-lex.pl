use strict; use warnings;
use AnyEvent;
use Lexical::Persistence;
my $w = AE::io *STDIN, 0, do { 
    my ($c, $buf) = Lexical::Persistence->new;
    sub { if (eof()) {
        eval { $c->do($buf) }; warn if $@;
        scalar <>; undef $buf;
    } else { $buf .= scalar <> } }
};
AE::cv->recv;

use v5.16;
use AnyEvent;
my $w = AE::io *STDIN, 0, sub {
    state $buf;
    if (eof()) {
        eval $buf; warn if $@;
        scalar <>; undef $buf;
    } else { $buf .= scalar <> }
};
AE::cv->recv;

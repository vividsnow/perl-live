use strict; use warnings;

package z;
use Getopt::Std 'getopts';
our ($st, $in, $hint, $buf, $ctx, $w) = (Package::Stash->new('main'), {});
getopts( g => $in );

package main;
use utf8; use Encode 'decode_utf8';
# uncomment if need by default
# use feature qw'say state';
# use experimental qw'smartmatch autoderef switch postderef lexical_subs';
use PadWalker 'peek_my'; use Package::Stash ();
use AnyEvent;

$z::w = AE::io *STDIN, 0, sub {
    if (eof()) {
        scalar <>;
        BEGIN { ($^H,${^WARNING_BITS},%^H) = @{$z::hint} if $z::hint }
        eval 'BEGIN { ($^H,${^WARNING_BITS},%^H) = @{$z::hint} if $z::hint }'
             .decode_utf8(substr($z::buf, 0, length $z::buf, ''))
             .'; package main; $z::ctx = peek_my(0);'
             .'BEGIN { $z::hint = [$^H, ${^WARNING_BITS}, %^H] }';
        map $z::st->add_symbol($_, $z::ctx->{$_}), keys%$z::ctx if $z::in->{g};
        warn if $@ }
    else { $z::buf .= scalar <> } };

AE::cv->recv;

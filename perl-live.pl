#!/usr/bin/env perl
use utf8;
use strict;
use warnings;
use feature qw(say state);
use experimental grep {
    exists $feature::feature{$_} || exists $warnings::Offsets{"experimental::$_"}
} qw(smartmatch switch lexical_subs defer declared_refs refaliasing
     bitwise builtin for_list isa signatures try);
use Encode 'decode_utf8';
use Getopt::Std 'getopts';
use JSON::PP 'decode_json';
use PadWalker 'peek_my';
use Package::Stash ();
use AnyEvent;

$λ::st = Package::Stash->new('main');
$λ::in = {};
getopts('gpj', $λ::in) or die "Usage: perl perl-live.pl [-g] [-p|-j]\n";
binmode STDIN, ':raw';
binmode STDOUT, ':encoding(UTF-8)';
binmode STDERR, ':encoding(UTF-8)';
$| = 1;
$λ::buf = '';
$λ::cv = AE::cv;
$λ::status = 0;
$λ::files = {};
$λ::file_id = 0;
$SIG{INT} = sub { }; # Keep idle sessions alive.
$SIG{__WARN__} = sub { warn λ::diagnostic($_[0]) };

sub λ::diagnostic {
    my $message = $_[0];
    for my $file (keys %{$λ::files}) {
        my $original = $λ::files->{$file};
        $message =~ s/( at )\Q$file\E( line [0-9]+)/$1$original$2/g;
    }
    return $message;
}

# Keep evaluator internals out of the lexical pad exported by peek_my.
sub λ::eval_code {
    $λ::ctx = {};
    $λ::source_file = $_[1] // '(perl live)';
    $λ::file = $λ::source_file;
    # Alias filenames that cannot be represented in a #line directive.
    if ($λ::file =~ /[\r\n]/ || ($λ::file =~ /"/ && $λ::file =~ /(?:\A"|\s)/)) {
        $λ::file = '(perl-live source '.++$λ::file_id.')';
    }
    $λ::files->{Encode::encode_utf8($λ::file)} = $λ::source_file;
    $λ::directive_file = $λ::file =~ /"/ ? $λ::file : qq("$λ::file");
    {
        local $SIG{INT} = sub { die "Evaluation interrupted\n" };
        eval 'BEGIN { ($^H,${^WARNING_BITS},%^H) = @{$λ::hint} if $λ::hint }'
             ."\n#line ".($_[2] // 1)." $λ::directive_file\n"
             .$_[0]
             ."\n; package main; \$λ::ctx = peek_my(0);"
             .'BEGIN { $λ::hint = [$^H,${^WARNING_BITS},%^H] }';
        $λ::error = $@;
    }
    if ($λ::in->{g}) {
        $λ::st->add_symbol($_, $λ::ctx->{$_}) for keys %{$λ::ctx};
    }
    warn $λ::error if length $λ::error;
}

sub λ::finish {
    if (@_) {
        warn $_[0];
        $λ::status = 1;
    }
    undef $λ::w;
    $λ::cv->send;
}

$λ::w = AE::io *STDIN, 0, sub {
    if ($λ::in->{p} || $λ::in->{j}) {
        # Length-prefixed UTF-8 source (-p) or JSON metadata (-j).
        my $read = sysread STDIN, my $chunk, 65536;
        if (!defined $read) {
            return if $!{EINTR} || $!{EAGAIN};
            λ::finish("Cannot read input: $!\n");
            return;
        }
        if (!$read) {
            λ::finish(defined $λ::size || length $λ::buf
                      ? "Incomplete evaluation frame\n" : ());
            return;
        }
        $λ::buf .= $chunk;
        while (1) {
            unless (defined $λ::size) {
                my $newline = index $λ::buf, "\n";
                last if $newline < 0;
                my $header = substr $λ::buf, 0, $newline + 1, '';
                unless ($header =~ /\A([0-9]+)\n\z/) {
                    λ::finish("Invalid evaluation frame\n");
                    return;
                }
                $λ::size = 0 + $1;
            }
            last if length $λ::buf < $λ::size;
            my $payload = substr $λ::buf, 0, $λ::size, '';
            if ($λ::in->{j}) {
                my $request = eval { decode_json($payload) };
                if ($@ || ref($request) ne 'HASH'
                    || !defined($request->{code}) || ref($request->{code})
                    || (exists($request->{file})
                        && (!defined($request->{file}) || ref($request->{file})))
                    || (exists($request->{line})
                        && (!defined($request->{line}) || ref($request->{line})
                            || $request->{line} !~ /\A[1-9][0-9]*\z/))) {
                    λ::finish("Invalid evaluation request\n");
                    return;
                }
                λ::eval_code($request->{code}, $request->{file}, $request->{line});
            }
            else { λ::eval_code(decode_utf8($payload)) }
            undef $λ::size;
        }
    }
    elsif (eof(STDIN)) {
        STDIN->clearerr if -t STDIN;
        λ::eval_code(decode_utf8(substr $λ::buf, 0, length $λ::buf, ''));
        λ::finish() unless -t STDIN;
    }
    else {
        my $line = <STDIN>;
        $λ::buf .= $line if defined $line;
    }
};

print "PERL-LIVE READY 1\n" if $λ::in->{j};
$λ::cv->recv;
exit $λ::status;

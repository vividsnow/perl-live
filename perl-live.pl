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

$z::st = Package::Stash->new('main');
$z::in = {};
getopts('gpj', $z::in) or die "Usage: perl perl-live.pl [-g] [-p|-j]\n";
binmode STDIN, ':raw';
binmode STDOUT, ':encoding(UTF-8)';
binmode STDERR, ':encoding(UTF-8)';
$| = 1;
$z::buf = '';
$z::cv = AE::cv;
$z::status = 0;
$z::files = {};
$z::file_id = 0;
$SIG{INT} = sub { }; # Keep idle sessions alive.
$SIG{__WARN__} = sub { warn z::diagnostic($_[0]) };

sub z::diagnostic {
    my $message = $_[0];
    for my $file (keys %{$z::files}) {
        my $original = $z::files->{$file};
        $message =~ s/( at )\Q$file\E( line [0-9]+)/$1$original$2/g;
    }
    return $message;
}

# Keep evaluator internals out of the lexical pad exported by peek_my.
sub z::eval_code {
    $z::ctx = {};
    $z::source_file = $_[1] // '(perl live)';
    $z::file = $z::source_file;
    # Alias filenames that cannot be represented in a #line directive.
    if ($z::file =~ /[\r\n]/ || ($z::file =~ /"/ && $z::file =~ /(?:\A"|\s)/)) {
        $z::file = '(perl-live source '.++$z::file_id.')';
    }
    $z::files->{Encode::encode_utf8($z::file)} = $z::source_file;
    $z::directive_file = $z::file =~ /"/ ? $z::file : qq("$z::file");
    {
        local $SIG{INT} = sub { die "Evaluation interrupted\n" };
        eval 'BEGIN { ($^H,${^WARNING_BITS},%^H) = @{$z::hint} if $z::hint }'
             ."\n#line ".($_[2] // 1)." $z::directive_file\n"
             .$_[0]
             ."\n; package main; \$z::ctx = peek_my(0);"
             .'BEGIN { $z::hint = [$^H,${^WARNING_BITS},%^H] }';
        $z::error = $@;
    }
    if ($z::in->{g}) {
        $z::st->add_symbol($_, $z::ctx->{$_}) for keys %{$z::ctx};
    }
    warn $z::error if length $z::error;
}

sub z::finish {
    if (@_) {
        warn $_[0];
        $z::status = 1;
    }
    undef $z::w;
    $z::cv->send;
}

$z::w = AE::io *STDIN, 0, sub {
    if ($z::in->{p} || $z::in->{j}) {
        # Length-prefixed UTF-8 source (-p) or JSON metadata (-j).
        my $read = sysread STDIN, my $chunk, 65536;
        if (!defined $read) {
            return if $!{EINTR} || $!{EAGAIN};
            z::finish("Cannot read input: $!\n");
            return;
        }
        if (!$read) {
            z::finish(defined $z::size || length $z::buf
                      ? "Incomplete evaluation frame\n" : ());
            return;
        }
        $z::buf .= $chunk;
        while (1) {
            unless (defined $z::size) {
                my $newline = index $z::buf, "\n";
                last if $newline < 0;
                my $header = substr $z::buf, 0, $newline + 1, '';
                unless ($header =~ /\A([0-9]+)\n\z/) {
                    z::finish("Invalid evaluation frame\n");
                    return;
                }
                $z::size = 0 + $1;
            }
            last if length $z::buf < $z::size;
            my $payload = substr $z::buf, 0, $z::size, '';
            if ($z::in->{j}) {
                my $request = eval { decode_json($payload) };
                if ($@ || ref($request) ne 'HASH'
                    || !defined($request->{code}) || ref($request->{code})
                    || (exists($request->{file})
                        && (!defined($request->{file}) || ref($request->{file})))
                    || (exists($request->{line})
                        && (!defined($request->{line}) || ref($request->{line})
                            || $request->{line} !~ /\A[1-9][0-9]*\z/))) {
                    z::finish("Invalid evaluation request\n");
                    return;
                }
                z::eval_code($request->{code}, $request->{file}, $request->{line});
            }
            else { z::eval_code(decode_utf8($payload)) }
            undef $z::size;
        }
    }
    elsif (eof(STDIN)) {
        STDIN->clearerr if -t STDIN;
        z::eval_code(decode_utf8(substr $z::buf, 0, length $z::buf, ''));
        z::finish() unless -t STDIN;
    }
    else {
        my $line = <STDIN>;
        $z::buf .= $line if defined $line;
    }
};

print "PERL-LIVE READY 1\n" if $z::in->{j};
$z::cv->recv;
exit $z::status;

use strict;
use warnings;
use Cwd qw(abs_path);
use File::Temp qw(tempdir);
use FindBin;
use JSON::PP ();

my $root = abs_path("$FindBin::Bin/..");
my $temporary = tempdir('perl-live-check-XXXXXX', TMPDIR => 1, CLEANUP => 1);
my $emacs = $ENV{EMACS} // 'emacs';
$ENV{PERL_LIVE_TEST_PERL} = $^X;

sub run {
    my $status = system { $_[0] } @_;
    die "Cannot run $_[0]: $!\n" if $status == -1;
    exit($status & 127 ? 128 + ($status & 127) : $status >> 8) if $status;
}

chdir $root or die "Cannot enter $root: $!";
run($^X, '-MAnyEvent', '-MPadWalker', '-MPackage::Stash', '-MJSON::PP',
    '-e', 'printf "Perl %s; backend %s\n", $^V, AnyEvent::detect();');
run($^X, '-c', "$root/perl-live.pl");
run($^X, '-MTest::Harness=runtests', '-e', 'runtests(@ARGV);', glob 'test/*.t');
run($emacs, '--batch', '-Q', '-l', "$root/test/perl-live-tests.el",
    '-f', 'ert-run-tests-batch-and-exit');
my $encoder = JSON::PP->new->allow_nonref;
my $source = $encoder->encode('perl-live.el');
my $compiled = $encoder->encode("$temporary/perl-live.elc");
run($emacs, '--batch', '-Q', '--eval',
    '(progn (require (quote bytecomp))'
    .' (let ((byte-compile-error-on-warn t)'
    .'       (byte-compile-dest-file-function (lambda (_) '.$compiled.')))'
    .'   (unless (byte-compile-file '.$source.') (kill-emacs 1))))');
print "All checks passed.\n";

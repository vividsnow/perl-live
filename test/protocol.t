use utf8;
use strict;
use warnings;
use Test::More;
use Encode qw(encode_utf8);
use JSON::PP qw(encode_json);
use FindBin;
use IPC::Open3;
use IO::Select;
use Symbol qw(gensym);

my $script = "$FindBin::Bin/../perl-live.pl";

sub run_input {
    my ($input, @switches) = @_;
    my ($in, $out);
    my $err = gensym;
    my $pid = open3($in, $out, $err, $^X, $script, @switches);
    binmode $_, ':raw' for ($in, $out, $err);
    print {$in} $input or die "Cannot send test input: $!";
    close $in;
    my $output_fd = fileno $out;
    my ($stdout, $stderr) = ('', '');
    my $readers = IO::Select->new($out, $err);
    my $deadline = time + 5;
    while ($readers->count) {
        my $remaining = $deadline - time;
        my @ready = $remaining > 0 ? $readers->can_read($remaining) : ();
        unless (@ready) {
            kill 9, $pid;
            waitpid $pid, 0;
            die "Interpreter did not finish after stdin closed\n";
        }
        for my $fh (@ready) {
            my $read = sysread $fh, my $chunk, 65536;
            die "Cannot read test output: $!" unless defined $read;
            if ($read) {
                if (fileno($fh) == $output_fd) { $stdout .= $chunk }
                else { $stderr .= $chunk }
            }
            else {
                $readers->remove($fh);
                close $fh;
            }
        }
    }
    waitpid $pid, 0;
    return ($?, $stdout, $stderr);
}

sub frame {
    my $source = encode_utf8($_[0] . "\n");
    return length($source) . "\n" . $source;
}

sub request_frame {
    my ($source, $file, $line) = @_;
    my $request = encode_json({
        code => $source,
        file => $file // '(test)',
        line => $line // 1,
    });
    return length($request) . "\n" . $request;
}

{
    my ($status, $out, $err) = run_input(
        frame('my $answer = 41;') . frame('print ++$answer, qq(\n);'), '-g', '-p');
    is $status, 0, 'framed input exits after stdin closes';
    is $out, "42\n", 'multiple frames preserve variables';
    is $err, '', 'framed input produces no warnings';
}
{
    my ($status, $out, $err) = run_input(
        frame('print qq(café привет 😀\n);'), '-p');
    is $status, 0, 'Unicode frame exits successfully';
    is $out, encode_utf8("café привет 😀\n"), 'frame lengths and output use UTF-8 bytes';
    is $err, '', 'Unicode output produces no warnings';
}
{
    my ($status, $out, $err) = run_input(encode_utf8('print qq(café\n);'), '-g');
    is $status, 0, 'plain input exits after permanent EOF';
    is $out, encode_utf8("café\n"), 'plain input still evaluates';
    is $err, '', 'plain input produces no warnings';
}
{
    my ($status, $out, $err) = run_input("invalid\n", '-p');
    isnt $status, 0, 'invalid frame header fails';
    like $err, qr/Invalid evaluation frame/, 'invalid header reports the cause';
}
{
    my ($status, $out, $err) = run_input("100\nprint 42;", '-p');
    isnt $status, 0, 'truncated frame fails';
    like $err, qr/Incomplete evaluation frame/, 'truncated frame reports the cause';
}

{
    my ($status, $out, $err) = run_input(
        request_frame('my $answer = 41; # no trailing newline')
            . request_frame('say ++$answer;'), '-g', '-j');
    is $status, 0, 'metadata requests exit successfully';
    is $out, "PERL-LIVE READY 1\n42\n", 'startup handshake and metadata frames coexist';
    is $err, '', 'a trailing comment does not swallow evaluator bookkeeping';
}
{
    my $file = '/tmp/source with spaces.pl';
    my ($status, $out, $err) = run_input(
        request_frame("die 'boom';", $file, 27)
            . request_frame('say 42;'), '-j');
    is $status, 0, 'runtime errors retain a usable interpreter';
    like $err, qr/\Q$file\E line 27/, 'runtime diagnostics retain filename and source line';
    is $out, "PERL-LIVE READY 1\n42\n", 'evaluation continues after a runtime error';
}
{
    my $file = '/tmp/source with spaces.pl';
    my ($status, $out, $err) = run_input(
        request_frame('my $broken = ;', $file, 42), '-j');
    like $err, qr/\Q$file\E line 42/, 'compile diagnostics retain the source location';
}
{
    my $file = '/tmp/source with"quotes\\here.pl';
    my ($status, $out, $err) = run_input(
        request_frame("die 'boom';", $file, 7), '-j');
    like $err, qr/\Q$file\E line 7/, 'source filenames preserve quotes and backslashes';
}
{
    my $file = '/tmp/café привет.pl';
    my ($status, $out, $err) = run_input(
        request_frame("die 'boom';", $file, 9), '-j');
    my $expected = encode_utf8("$file line 9");
    like $err, qr/\Q$expected\E/, 'source filenames preserve Unicode characters';
}
{
    my $file = '/tmp/café привет.pl';
    my ($status, $out, $err) = run_input(
        request_frame("sub fail_later { die 'boom' };", $file, 11)
            . request_frame('fail_later();', '/tmp/caller.pl', 3), '-j');
    my $expected = encode_utf8("$file line 11");
    like $err, qr/\Q$expected\E/, 'errors retain locations from earlier evaluations';
}
{
    my $file = '/tmp/source with"quotes.pl';
    my ($status, $out, $err) = run_input(
        request_frame("warn 'careful';", $file, 5), '-j');
    like $err, qr/\Q$file\E line 5/, 'warnings retain filenames requiring a line-directive alias';
}
{
    my $request = encode_json({ code => 'print qq(café привет 😀\n);', file => '(test)', line => 1 });
    my ($status, $out, $err) = run_input(length($request) . "\n" . $request, '-j');
    is $out, "PERL-LIVE READY 1\n" . encode_utf8("café привет 😀\n"),
        'JSON frames use byte lengths for Unicode source';
    is $err, '', 'Unicode metadata requests produce no warnings';
}
for my $payload ('{', '[]', '{"code":[]}', '{"code":"1","line":0}', '{"code":"1","file":{}}') {
    my ($status, $out, $err) = run_input(length($payload) . "\n" . $payload, '-j');
    isnt $status, 0, 'invalid metadata request fails';
    like $err, qr/Invalid evaluation request/, 'invalid metadata reports the cause';
}

done_testing;

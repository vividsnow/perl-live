use utf8;
use strict;
use warnings;
use Test::More;
use Encode qw(encode_utf8 decode_utf8);
use JSON::PP qw(encode_json decode_json);
use FindBin;
use IPC::Open3;
use IO::Select;
use Symbol qw(gensym);

my $server_script = "$FindBin::Bin/../perl-live-mcp.pl";
my ($in, $out);
my $err = gensym;
my $pid = open3($in, $out, $err, $^X, $server_script);
binmode $_, ':raw' for ($in, $out, $err);

sub rpc_call {
    my ($req) = @_;
    my $json = encode_json($req);
    print {$in} $json . "\n";

    my $line = <$out>;
    die "Server closed stdout unexpectedly\n" unless defined $line;
    return decode_json(decode_utf8($line));
}

my $init_res = rpc_call({
    jsonrpc => '2.0',
    id => 1,
    method => 'initialize',
    params => { protocolVersion => '2024-11-05' }
});
is $init_res->{id}, 1, 'initialize returns matching id';
is $init_res->{result}{serverInfo}{name}, 'perl-live', 'serverInfo name is perl-live';

my $tools_res = rpc_call({
    jsonrpc => '2.0',
    id => 2,
    method => 'tools/list',
    params => {}
});
is $tools_res->{id}, 2, 'tools/list returns matching id';
my @tool_names = sort map { $_->{name} } @{$tools_res->{result}{tools}};
is_deeply \@tool_names, ['perl_live_eval', 'perl_live_restart', 'perl_live_status'], 'expected tools registered';

my $status_res = rpc_call({
    jsonrpc => '2.0',
    id => 3,
    method => 'tools/call',
    params => {
        name => 'perl_live_status',
        arguments => {}
    }
});
is $status_res->{id}, 3, 'status call returns matching id';
like $status_res->{result}{content}[0]{text}, qr/Session Status: running/, 'status reports running session';

my $eval1_res = rpc_call({
    jsonrpc => '2.0',
    id => 4,
    method => 'tools/call',
    params => {
        name => 'perl_live_eval',
        arguments => {
            code => 'my $accumulator = 100;'
        }
    }
});
is $eval1_res->{id}, 4, 'first eval returns matching id';
is $eval1_res->{result}{isError}, JSON::PP::false, 'first eval has no error';

my $eval2_res = rpc_call({
    jsonrpc => '2.0',
    id => 5,
    method => 'tools/call',
    params => {
        name => 'perl_live_eval',
        arguments => {
            code => 'say ++$accumulator;'
        }
    }
});
is $eval2_res->{result}{content}[0]{text}, "101\n", 'second eval reuses state and produces 101';
is $eval2_res->{result}{isError}, JSON::PP::false, 'second eval has no error';

my $eval3_res = rpc_call({
    jsonrpc => '2.0',
    id => 6,
    method => 'tools/call',
    params => {
        name => 'perl_live_eval',
        arguments => {
            code => 'say "café привет 😀";'
        }
    }
});
is $eval3_res->{result}{content}[0]{text}, "café привет 😀\n", 'Unicode output preserved without mangling';

my $eval4_res = rpc_call({
    jsonrpc => '2.0',
    id => 7,
    method => 'tools/call',
    params => {
        name => 'perl_live_eval',
        arguments => {
            code => 'die "something went wrong";'
        }
    }
});
is $eval4_res->{result}{isError}, JSON::PP::true, 'die marks result as error';
like $eval4_res->{result}{content}[0]{text}, qr/something went wrong/, 'error text returned in content';

my $restart_res = rpc_call({
    jsonrpc => '2.0',
    id => 8,
    method => 'tools/call',
    params => {
        name => 'perl_live_restart',
        arguments => {}
    }
});
is $restart_res->{result}{isError}, JSON::PP::false, 'restart succeeded';

my $eval5_res = rpc_call({
    jsonrpc => '2.0',
    id => 9,
    method => 'tools/call',
    params => {
        name => 'perl_live_eval',
        arguments => {
            code => 'say ++$accumulator;'
        }
    }
});
is $eval5_res->{result}{isError}, JSON::PP::true, 'undeclared accumulator fails strict check after restart';
like $eval5_res->{result}{content}[0]{text}, qr/requires explicit package name/, 'error confirms symbol was cleared';

my $eval6_res = rpc_call({
    jsonrpc => '2.0',
    id => 10,
    method => 'tools/call',
    params => {
        name => 'perl_live_eval',
        arguments => {
            code => 'my $new_var = 77; say $new_var * 2;'
        }
    }
});
is $eval6_res->{result}{content}[0]{text}, "154\n", 'fresh declaration evaluates cleanly';

close $in;
waitpid $pid, 0;
done_testing;

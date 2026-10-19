#!/usr/bin/env perl
use utf8;
use strict;
use warnings;
use FindBin;
use Cwd qw(abs_path getcwd);
use IPC::Open3 qw(open3);
use Symbol qw(gensym);
use IO::Select;
use Encode qw(encode_utf8 decode_utf8);
use JSON::PP qw(encode_json decode_json);

binmode STDIN, ':raw';
binmode STDOUT, ':raw';
binmode STDERR, ':encoding(UTF-8)';
$| = 1;

my $root_dir = abs_path("$FindBin::Bin");
my $backend_script = $ENV{PERL_LIVE_SCRIPT}
                  // (-f "$root_dir/perl-live.pl" ? "$root_dir/perl-live.pl" : "perl-live.pl");
my $session_pid;
my ($session_in, $session_out);
my $session_err;
my $session_eval_count = 0;
my $session_start_time = time;
my $current_switches = "-g";

sub start_backend {
    my ($switches) = @_;
    stop_backend() if $session_pid;

    $current_switches = $switches if defined $switches;
    $session_err = gensym;
    my @cmd = ($^X, $backend_script, split(/\s+/, $current_switches), "-j");
    $session_pid = open3($session_in, $session_out, $session_err, @cmd);
    binmode $_, ':raw' for ($session_in, $session_out, $session_err);

    my $ready_line = <$session_out>;
    unless ($ready_line && $ready_line =~ /^PERL-LIVE READY/) {
        my $err_out = '';
        sysread $session_err, $err_out, 4096;
        stop_backend();
        die "Failed to initialize perl-live backend: $err_out\n";
    }
    $session_eval_count = 0;
    $session_start_time = time;
}

sub stop_backend {
    return unless $session_pid;
    close $session_in if $session_in;
    close $session_out if $session_out;
    close $session_err if $session_err;
    kill('TERM', $session_pid) if kill(0, $session_pid);
    waitpid($session_pid, 0);
    undef $session_pid;
    undef $session_in;
    undef $session_out;
    undef $session_err;
}

sub eval_in_backend {
    my ($code, $file, $line, $timeout) = @_;
    start_backend($current_switches) unless $session_pid && kill(0, $session_pid);

    $file //= '(perl live)';
    $line //= 1;
    $timeout //= 15;

    my $token = sprintf("%08x%08x", int(rand(0xffffffff)), int(rand(0xffffffff)));
    my $code_req = encode_json({
        code => $code . "\n",
        file => $file,
        line => $line,
    });
    my $barrier_req = encode_json({
        code => "print qq(__B_OUT_${token}__\n); warn qq(__B_ERR_${token}__\n);\n",
        file => '(barrier)',
        line => 1,
    });

    my $code_frame = length(encode_utf8($code_req)) . "\n" . encode_utf8($code_req);
    my $barrier_frame = length(encode_utf8($barrier_req)) . "\n" . encode_utf8($barrier_req);

    print {$session_in} $code_frame;
    print {$session_in} $barrier_frame;

    my ($stdout, $stderr) = ('', '');
    my $sel = IO::Select->new($session_out, $session_err);
    my ($got_out, $got_err) = (0, 0);
    my $deadline = time + $timeout;
    my $interrupted = 0;

    while ($sel->count && !($got_out && $got_err)) {
        my $remaining = $deadline - time;
        if ($remaining <= 0 && !$interrupted) {
            $interrupted = 1;
            kill('INT', $session_pid);
            $deadline = time + 2;
        }

        my @ready = $sel->can_read(0.1);
        for my $fh (@ready) {
            my $read = sysread $fh, my $buf, 65536;
            if (defined $read && $read > 0) {
                if (fileno($fh) == fileno($session_out)) {
                    $stdout .= $buf;
                    if ($stdout =~ s/__B_OUT_${token}__\n//) {
                        $got_out = 1;
                    }
                } else {
                    $stderr .= $buf;
                    if ($stderr =~ s/__B_ERR_${token}__\n//) {
                        $got_err = 1;
                    }
                }
            } elsif (defined $read && $read == 0) {
                $sel->remove($fh);
            }
        }

        if (!kill(0, $session_pid)) {
            stop_backend();
            last;
        }
    }

    $session_eval_count++;
    return (decode_utf8($stdout), decode_utf8($stderr), $interrupted);
}

my %tools = (
    perl_live_eval => {
        name => 'perl_live_eval',
        description => 'Evaluate Perl code inside the persistent live interpreter session. Package variables, declared subroutines, and pragmas persist across calls without shell overhead.',
        inputSchema => {
            type => 'object',
            properties => {
                code => {
                    type => 'string',
                    description => 'Perl source code to evaluate.',
                },
                timeout => {
                    type => 'number',
                    description => 'Timeout in seconds (default: 15). Interrupts evaluation cleanly if exceeded without losing session state.',
                },
                file => {
                    type => 'string',
                    description => 'Optional virtual or source filename for diagnostics (default: "(perl live)").',
                },
                line => {
                    type => 'integer',
                    description => 'Optional starting line number for diagnostics (default: 1).',
                },
            },
            required => ['code'],
        },
    },
    perl_live_restart => {
        name => 'perl_live_restart',
        description => 'Restart the persistent Perl live interpreter session, clearing all package symbols and lexical state.',
        inputSchema => {
            type => 'object',
            properties => {
                switches => {
                    type => 'string',
                    description => 'Interpreter switches (default: "-g" to export lexicals as package variables).',
                },
            },
        },
    },
    perl_live_status => {
        name => 'perl_live_status',
        description => 'Get status of the persistent Perl live session (PID, uptime, eval count, backend path).',
        inputSchema => {
            type => 'object',
            properties => {},
        },
    },
);

sub handle_tool_call {
    my ($name, $args) = @_;
    $args //= {};

    if ($name eq 'perl_live_eval') {
        my $code = $args->{code};
        unless (defined $code && length $code) {
            return {
                content => [{ type => 'text', text => 'Error: "code" argument is required.' }],
                isError => JSON::PP::true,
            };
        }
        my ($out, $err, $interrupted) = eval_in_backend(
            $code, $args->{file}, $args->{line}, $args->{timeout}
        );

        my $result_text = '';
        if (length $out) {
            $result_text .= $out;
        }
        if (length $err) {
            $result_text .= ($result_text ? "\n[stderr]\n" : "") . $err;
        }
        if (!length($out) && !length($err)) {
            $result_text = "(evaluated successfully, no output)\n";
        }
        if ($interrupted) {
            $result_text .= "\n(evaluation timed out and was interrupted)";
        }

        return {
            content => [{ type => 'text', text => $result_text }],
            isError => (length($err) || $interrupted) ? JSON::PP::true : JSON::PP::false,
        };
    }
    elsif ($name eq 'perl_live_restart') {
        eval { start_backend($args->{switches}) };
        if ($@) {
            return {
                content => [{ type => 'text', text => "Failed to restart session: $@" }],
                isError => JSON::PP::true,
            };
        }
        return {
            content => [{ type => 'text', text => "Perl live session restarted (PID $session_pid, switches: $current_switches)." }],
            isError => JSON::PP::false,
        };
    }
    elsif ($name eq 'perl_live_status') {
        my $alive = ($session_pid && kill(0, $session_pid)) ? 1 : 0;
        my $uptime = $alive ? (time - $session_start_time) : 0;
        my $info = sprintf(
            "Session Status: %s\nPID: %s\nUptime: %ds\nEvaluations count: %d\nSwitches: %s\nPerl: %s (%s)\nBackend: %s",
            $alive ? 'running' : 'stopped',
            $alive ? $session_pid : 'none',
            $uptime,
            $session_eval_count,
            $current_switches,
            $^X, $^V,
            $backend_script
        );
        return {
            content => [{ type => 'text', text => $info }],
            isError => JSON::PP::false,
        };
    }

    return {
        content => [{ type => 'text', text => "Unknown tool: $name" }],
        isError => JSON::PP::true,
    };
}

$SIG{TERM} = sub { stop_backend(); exit 0; };
$SIG{INT}  = sub { stop_backend(); exit 0; };

while (defined(my $line = <STDIN>)) {
    $line =~ s/[\r\n]+$//;
    next unless length $line;

    my $req = eval { decode_json($line) };
    next unless $req && ref($req) eq 'HASH';

    my $id = $req->{id};
    my $method = $req->{method} // '';

    if ($method eq 'initialize') {
        eval { start_backend($current_switches) };
        my $resp = {
            jsonrpc => '2.0',
            id => $id,
            result => {
                protocolVersion => '2024-11-05',
                capabilities => {
                    tools => {},
                },
                serverInfo => {
                    name => 'perl-live',
                    version => '0.01',
                },
            },
        };
        print encode_json($resp) . "\n";
    }
    elsif ($method eq 'notifications/initialized') {
    }
    elsif ($method eq 'ping') {
        print encode_json({ jsonrpc => '2.0', id => $id, result => {} }) . "\n";
    }
    elsif ($method eq 'tools/list') {
        my @list = values %tools;
        my $resp = {
            jsonrpc => '2.0',
            id => $id,
            result => {
                tools => \@list,
            },
        };
        print encode_json($resp) . "\n";
    }
    elsif ($method eq 'tools/call') {
        my $params = $req->{params} // {};
        my $tool_name = $params->{name} // '';
        my $tool_args = $params->{arguments} // {};
        my $result = handle_tool_call($tool_name, $tool_args);
        my $resp = {
            jsonrpc => '2.0',
            id => $id,
            result => $result,
        };
        print encode_json($resp) . "\n";
    }
    else {
        if (defined $id) {
            my $resp = {
                jsonrpc => '2.0',
                id => $id,
                error => {
                    code => -32601,
                    message => "Method not found: $method",
                },
            };
            print encode_json($resp) . "\n";
        }
    }
}

stop_backend();
exit 0;

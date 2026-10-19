package AnyEvent::App::PerlLive;

use utf8;
use strict;
use warnings;
use FindBin;
use File::Spec;

our $VERSION = '0.01';

sub script_path {
    my $class = shift;
    my $script = File::Spec->catfile($FindBin::Bin, 'perl-live.pl');
    return $script if -f $script;
    require IPC::Cmd;
    return IPC::Cmd::can_run('perl-live.pl') // 'perl-live.pl';
}

1;

__END__

=pod

=encoding utf-8

=head1 NAME

AnyEvent::App::PerlLive - Persistent Perl live-coding interpreter and REPL backend

=head1 SYNOPSIS

From the command line:

    perl-live.pl -g

In standalone or framed input mode:

    echo 'my $x = 41; say ++$x;' | perl-live.pl -g

From Emacs (with C<perl-live.el>):

    (require 'perl-live)
    (add-hook 'cperl-mode-hook #'perl-live-mode)
    (add-hook 'perl-mode-hook  #'perl-live-mode)

=head1 DESCRIPTION

C<AnyEvent::App::PerlLive> provides a persistent, event-driven Perl evaluation environment.
Top-level lexical declarations (C<my>) become package variables, lexical pragmas
and compiler hints persist across evaluations, and errors maintain accurate source
filenames and line numbers.

Driven by L<AnyEvent>, it integrates seamlessly with asynchronous backends such
as L<EV> and L<EV::WebKit>.

=head1 SCRIPTS

=over 4

=item L<perl-live.pl>

The core evaluation server. Supports raw EOF input, length-prefixed UTF-8 streams
(C<-p>), and length-prefixed JSON metadata requests (C<-j>).

=item L<perl-live-mcp.pl>

Model Context Protocol (MCP) server providing live Perl evaluation tools for AI coding assistants.

=back

=head1 SEE ALSO

L<AnyEvent>, L<PadWalker>, L<Package::Stash>.

GitHub repository: L<https://github.com/vividsnow/perl-live>

=head1 AUTHOR

vividsnow

=head1 LICENSE AND COPYRIGHT

This program is free software; you can redistribute it and/or modify it
under the terms of the GNU General Public License as published by the Free
Software Foundation, version 3.

=cut

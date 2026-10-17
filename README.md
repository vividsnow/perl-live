# Perl live coding

Evaluate Perl from Emacs in a persistent interpreter, with a separate session
and REPL for each project.

## Install

Requires Perl 5.22+ and Emacs 28.1+. Install the Perl dependencies:

```sh
cpanm --installdeps .
```

Dependencies: AnyEvent, PadWalker, Package::Stash, and JSON::PP. EV and
Package::Stash::XS are optional accelerators.

Keep `perl-live.el` and `perl-live.pl` together and add this to your Emacs config:

```elisp
(add-to-list 'load-path "/path/to/perl-live")
(require 'perl-live)
(add-hook 'cperl-mode-hook #'perl-live-mode)
(add-hook 'perl-mode-hook #'perl-live-mode)
```

Or enable `M-x perl-live-mode` in a single buffer.

## Use

| Key | Action |
| --- | --- |
| `C-c C-l` | Start or show the session |
| `C-c C-p` | Stop |
| `C-c C-r` | Restart |
| `C-c C-k` | Interrupt evaluation |
| `C-c C-z` | Switch to the REPL |
| `C-c C-c` | Evaluate the current line or active region |
| `C-M-x` | Evaluate inside the braces enclosing point |

Evaluation starts a session when needed. Top-level `my` declarations become
package variables, so later evaluations can reuse them. Lexical pragmas persist;
default features are enabled when supported by the running Perl. Input and output
use UTF-8.

Evaluate these lines separately:

```perl
my $answer = 41;
say ++$answer; # 42
```

In the REPL, Return evaluates input, `M-p` / `M-n` browse history, and `C-c C-c`
interrupts evaluation. Interrupting keeps existing variables; declarations in an
unfinished evaluation are not exported. Restarting clears the session.

Errors retain source filenames and line numbers. Click an error or use
`M-g n` / `M-g p` to visit it. Save source buffers for file navigation.

## Configure

Sessions use the Emacs project root, an enclosing `cpanfile` directory, or the
current directory. Set `perl-live-project-directory` to override detection.

Use `M-x customize-group RET perl-live RET` for options. `perl-live-bin` selects
the interpreter; when it is `"perl"`, an already loaded `perlenv` selects it in the
project directory. Set `perl-live-switches` to `""` to disable variable export.

Directory-local variables can configure each project, for example in `.dir-locals.el`:

```elisp
((nil . ((perl-live-bin . "/path/to/project/perl")
         (perl-live-switches . "-g"))))
```

Restart after changing the interpreter or switches. REPL commands retain the
settings used to start the session. Startup errors appear in its buffer.

## Without Emacs

```sh
perl perl-live.pl -g
```

Enter Perl, then press Ctrl+D on a new line to evaluate. Ctrl+C interrupts an
evaluation; `exit;` ends the session. Piped input evaluates at EOF and exits.

## Develop

```sh
perl test/check.pl
```

Runs syntax checks, Perl and Emacs tests, and Elisp byte compilation. Uses the
current Perl; set `EMACS` to select Emacs. Set `PERL_ANYEVENT_MODEL` to `Perl` or
`EV` to select a backend. CI covers both on Perl 5.22, 5.40, and 5.42, with Emacs
28.2 and 30.2.

[Original demo](http://blogs.perl.org/users/egor/2013/05/perl-live-coding.html).

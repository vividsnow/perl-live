# perl live coding

## usage

```lisp
; put perl-live.el and perl-live.pl in `/path/to/somewhere`
(add-to-list 'load-path "/path/to/somewhere")
(require 'perl-live)
```

Create `cperl-mode` buffer and use these keybindings:

 * "C-c C-l" - start live perl session
 * "C-c C-p" - stop it
 * "C-c C-c" - eval current line or region
 * "C-M-x" - eval everything between matching braces

Open `*perl live*` buffer in other frame/window to check output. Also, use `*perl live*` as REPL ([comint-mode](http://www.emacswiki.org/emacs/ComintMode)).

In order to have persistent variables between evals without magic, declare them using `use vars qw($one @two %three)` or
use main package vars like: `$'somevar` or `$::somevar` or create other package on-the-fly.
Modify `perl-live.pl` if you want to preload other modules or predeclare context lexicals using `my/state`.
By default `my` declarations at top level are converted to globals. Evaluating of 'use some_pragma' persists.

## customize

```lisp
(defvar perl-live-bin "/path/to/perl") ; path to perl binary - default: "perl" or `perlenv-get-perl-path` if `perlenv.el` loaded
(defvar perl-live-script "/path/to/perl-live.pl") ; path to interpreter script - default: "perl-live.pl" at same dir where you put perl-live.el
(defvar perl-live-switches "/path/to/perl-live.pl") ; default: "-g" - make "my" global
```

## requirements

### perl

 * > 5.12 (not tested on earlier versions)
 * [AnyEvent](http://metacpan.org/release/AnyEvent) + optionally [EV](http://metacpan.org/release/EV)
 * [PadWalker](http://metacpan.org/release/PadWalker)
 * [Package::Stash::XS](https://metacpan.org/release/Package-Stash-XS), which requires [Package::Stash](https://metacpan.org/pod/Package::Stash)

### emacs

 * [cperl-mode](https://github.com/jrockway/cperl-mode) for predefined keybindings:

sample `cperl-mode` indentation config:
```lisp
(setq cperl-close-paren-offset -4 cperl-continued-statement-offset 4
    cperl-indent-level 4 cperl-indent-parens-as-block t
    cperl-tabs-always-indent t cperl-indent-subs-specially nil)
```

### usage without emacs

```bash
~$ perl perl-live.pl -g # run
# enter perl code
# hit Ctrl+D on a new line to evaluate
#     Ctrl+C to interrupt
```

----------------

#### elsewhere

 * [blog post w/ demo screencast](http://blogs.perl.org/users/egor/2013/05/perl-live-coding.html)

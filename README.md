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
 * "C-c C-c" - eval current line  
 * "C-c C-r" - eval region  
 * "C-M-x" - eval everything between matching braces  

Open `*perl live*` buffer in other frame/window to check output. Also, use `*perl live*` as REPL (comint-mode).

In order to have persistent variables between evals, declare them using `use vars qw($one @two %three)` or use main package vars like: `$'somevar` or `$::somevar` or create other package on-the-fly. Modify `perl-live.pl` if you want to preload other modules or predeclare context lexicals using `my/state`.

## customize

```lisp
(defvar perl-live-bin "/path/to/perl") ; path to perl binary - default: "perl" or `perlenv-get-perl-path` if `perlenv.el` loaded
(defvar perl-live-script "/path/to/perl-live.pl") ; path to interpreter script - default: "perl-live.pl" at same dir where you put perl-live.el
```

## requirements

### emacs

 * [cperl-mode](https://github.com/jrockway/cperl-mode) for predefined keybindings:
   here is sample `cperl-mode` config:
   ```lisp
   (setq cperl-close-paren-offset -4 cperl-continued-statement-offset 4
    cperl-indent-level 4 cperl-indent-parens-as-block t
    cperl-tabs-always-indent t cperl-indent-subs-specially nil)
   ```

### perl

 * [AnyEvent](http://metacpan.org/release/AnyEvent)

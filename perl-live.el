(defconst perl-live-bin (perlenv-get-perl-path) "path to perl binary") ; use perlenv.el to provide path
(defconst perl-live-script (substitute-in-file-name "$HOME/dev/perl-live/perl-live.pl") "path to script for live coding")
(defconst perl-live-name "perl live" "name for process and buffer")

(defun perl-live-eval (text) "eval string in perl interpreter" (interactive "s")
  (message (format "sending %d chars" (length text))) ; notify minibuffer
  (process-send-string perl-live-name (format "%s\n" text))
  (process-send-eof perl-live-name)) 
(defun perl-live-eval-region (start end) "eval region" (interactive "r")
  (perl-live-eval (buffer-substring-no-properties start end))
  (deactivate-mark)) 
(defun perl-live-eval-line () "eval line" (interactive)
  (save-excursion ((lambda (p) (perl-live-eval-region (car p) (cdr p))) (bounds-of-thing-at-point 'line)))
  (forward-line)) 
(defun perl-live-eval-sexp () "eval between braces" (interactive)
  (save-excursion ((lambda (p) (perl-live-eval-region (+ 1 (car p)) (- (cdr p) 1))) (bounds-of-thing-at-point 'sexp))))

(cperl-define-key "\C-c\C-r" 'perl-live-eval-region)
(cperl-define-key "\C-c\C-c" 'perl-live-eval-line)
(cperl-define-key "\C-\M-x" 'perl-live-eval-sexp)

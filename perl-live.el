(require 'ansi-color)

(defcustom perl-live-bin
  (if (featurep 'perlenv) (perlenv-get-perl-path) "perl")
  "path to perl binary"
  :group 'perl-live
  :type 'string) ; use perlenv by default
(defcustom perl-live-script
  (format "%sperl-live.pl" (file-name-directory (or load-file-name buffer-file-name)))
  "path to script for live coding"
  :group 'perl-live
  :type 'string)
(defcustom perl-live-switches "-g" "live script switches" ; -g for globalize context
  :group 'perl-live
  :type 'string)

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
(defun perl-live-eval-region-or-line () "eval line or region" (interactive)
  (if (and transient-mark-mode mark-active)
      (perl-live-eval-region (region-beginning) (region-end)) (perl-live-eval-line)))
(defun perl-live-eval-sexp () "eval between braces" (interactive)
  (save-excursion ((lambda (p) (perl-live-eval-region (+ 1 (car p)) (- (cdr p) 1))) (bounds-of-thing-at-point 'sexp))))

(defun perl-live-run () "run perl-live commint session" (interactive)
  (if (string= (process-status perl-live-name) "run")
      (message "already run")
    (if (featurep 'comint)
        (progn
          (make-comint perl-live-name perl-live-bin nil perl-live-script perl-live-switches)
          (with-current-buffer (format "*%s*" perl-live-name)
            (mapcar (lambda (v) (set (make-local-variable v) 't))
             (list 'ansi-color-for-comint-mode
               'comint-scroll-to-bottom-on-input
               'comint-scroll-to-bottom-on-output
               'comint-move-point-for-output))
            (set (make-local-variable 'comint-input-sender)
                 '(lambda (proc string)
                    (comint-send-string proc (format "%s\n" string))
                    (process-send-eof proc)))))
      (start-process perl-live-name (format "*%s*" perl-live-name) perl-live-bin perl-live-script perl-live-switches))
    (message (format "check output at *%s* buffer" perl-live-name))))

(defun perl-live-stop () "stop perl-live session" (interactive)
  (delete-process perl-live-name)
  (message (format "process %s killed" perl-live-name)))

(defun perl-live-restart () "restart perl-live session" (interactive)
  (delete-process perl-live-name) (sleep-for 0 100) (perl-live-run))


(if (featurep 'cperl-mode)
    (progn
      (cperl-define-key "\C-c\C-c" 'perl-live-eval-region-or-line)
      (cperl-define-key "\C-\M-x" 'perl-live-eval-sexp)
      (cperl-define-key "\C-c\C-l" 'perl-live-run)
      (cperl-define-key "\C-c\C-p" 'perl-live-stop)))

(provide 'perl-live)

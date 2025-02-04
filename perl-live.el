;;; perl-live.el --- Live Perl Coding -*-lexical-binding: t; -*-

;;  Author: vividsnow.tumblr.com

;; This file is not part of GNU Emacs.

;; This program is free software: you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation, either version 3 of the License, or
;; (at your option) any later version.
;;
;; This program is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.
;;
;; You should have received a copy of the GNU General Public License
;; along with this program.  If not, see <http://www.gnu.org/licenses/>.

;;;---------------------------------------------------------------------------
;;; Commentary:

(require 'comint)
(require 'ansi-color)

(defcustom perl-live-bin (if (and (featurep 'perlenv)
                                  (fboundp 'perlenv-get-perl-path))
                             (perlenv-get-perl-path)
                           "perl")
  "Path to perl binary, use perlenv by default."
  :group 'perl-live
  :type 'string)

(defcustom perl-live-script (format "%sperl-live.pl"
                                    (file-name-directory
                                     (or load-file-name buffer-file-name)))
  "path to script for live coding"
  :group 'perl-live
  :type 'string)

(defcustom perl-live-switches "-g"
  "live script switches, -g for globalize context"
  :group 'perl-live
  :type 'string)

(defconst perl-live-name "perl live"
  "name for process and buffer")

(defun perl-live-eval (text)
  "Eval string in perl interpreter."
  (interactive "s")
  (message (format "sending %d chars" (length text))) ; notify minibuffer
  (process-send-string perl-live-name (format "%s\n" text))
  (process-send-eof perl-live-name))

(defun perl-live-eval-region (start end)
  "Eval region."
  (interactive "r")
  (perl-live-eval (buffer-substring-no-properties start end))
  (deactivate-mark))

(defun perl-live-eval-line ()
  "Eval line."
  (interactive)
  (save-excursion
    ((lambda (p) (perl-live-eval-region (car p) (cdr p)))
     (bounds-of-thing-at-point 'line)))
  (forward-line))

(defun perl-live-eval-region-or-line ()
  "Eval line or region."
  (interactive)
  (if (and transient-mark-mode mark-active)
      (perl-live-eval-region (region-beginning) (region-end))
    (perl-live-eval-line)))

(defun perl-live-eval-sexp ()
  "Eval between braces."
  (interactive)
  (save-excursion
    ((lambda (p) (perl-live-eval-region (+ 1 (car p)) (- (cdr p) 1)))
     (bounds-of-thing-at-point 'sexp))))

(defun perl-live-run ()
  "Run perl-live commint session."
  (interactive)
  (if (string= (process-status perl-live-name) "run")
      (message "already run")
    (if (featurep 'comint)
        (progn
          (make-comint perl-live-name perl-live-bin nil perl-live-script perl-live-switches)
          (with-current-buffer (format "*%s*" perl-live-name)
            (mapc (lambda (v) (set (make-local-variable v) 't))
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

(defun perl-live-stop ()
  "stop perl-live session"
  (interactive)
  (delete-process perl-live-name)
  (message (format "process %s killed" perl-live-name)))

(defun perl-live-restart ()
  "restart perl-live session"
  (interactive)
  (delete-process perl-live-name)
  (sleep-for 0 100)
  (perl-live-run))


(if (and (featurep 'cperl-mode)
         (boundp 'cperl-mode-map))
    (progn
      (define-key cperl-mode-map "\C-c\C-c" 'perl-live-eval-region-or-line)
      (define-key cperl-mode-map "\C-\M-x" 'perl-live-eval-sexp)
      (define-key cperl-mode-map "\C-c\C-l" 'perl-live-run)
      (define-key cperl-mode-map "\C-c\C-p" 'perl-live-stop)))

(provide 'perl-live)

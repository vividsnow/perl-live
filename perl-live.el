;;; perl-live.el --- Evaluate Perl in persistent project sessions -*- lexical-binding: t; -*-

;; Author: vividsnow <https://github.com/vividsnow>
;; Contributors: Pierre Rouleau
;; URL: https://github.com/vividsnow/perl-live
;; SPDX-License-Identifier: GPL-3.0-or-later
;; Version: 0.2.0
;; Package-Requires: ((emacs "28.1"))
;; Keywords: languages, processes

;;; Commentary:

;; Enable perl-live-mode for a persistent Perl interpreter per project.

;;; Code:

(require 'comint)
(require 'ansi-color)
(require 'compile)
(require 'json)
(require 'project)
(require 'subr-x)

(defgroup perl-live nil
  "Evaluate Perl code in persistent project sessions."
  :group 'perl
  :link '(url-link "https://github.com/vividsnow/perl-live")
  :prefix "perl-live-")

(defcustom perl-live-bin "perl"
  "Perl executable.  When this is perl, use perlenv if it is already loaded."
  :group 'perl-live
  :type 'string)

(defcustom perl-live-script
  (expand-file-name
   "perl-live.pl"
   (if-let* ((file (or load-file-name buffer-file-name)))
       (file-name-directory file)
     default-directory))
  "Path to the interpreter script."
  :group 'perl-live
  :type 'file)

(defcustom perl-live-switches "-g"
  "Interpreter switches, parsed as shell-style quoted arguments.
The default -g exports top-level lexical variables as package variables."
  :group 'perl-live
  :type 'string)

(defcustom perl-live-project-directory nil
  "Session directory, or nil to detect it from the current buffer.
Detection uses the project root, an enclosing cpanfile directory, or the
current directory."
  :group 'perl-live
  :type '(choice (const :tag "Detect automatically" nil) directory)
  :local t)

(defcustom perl-live-startup-timeout 5
  "Seconds to wait for an interpreter to report that it is ready."
  :group 'perl-live
  :type 'number)

(defconst perl-live-name "perl live" "Prefix for session process and buffer names.")
(defconst perl-live--ready-message "PERL-LIVE READY 1\n")
(defvar perl-live--sessions (make-hash-table :test 'equal))
(defvar-local perl-live--session-root nil)

(add-to-list 'compilation-error-regexp-alist-alist
             '(perl-live " at \\(.+?\\) line \\([0-9]+\\)\\(?:[,.]\\|$\\)" 1 2))

(defun perl-live--root ()
  "Return the canonical directory identifying the current session."
  (file-name-as-directory
   (file-truename
    (expand-file-name
     (or perl-live--session-root
         perl-live-project-directory
         (when-let* ((project (project-current nil)))
           (project-root project))
         (locate-dominating-file default-directory "cpanfile")
         default-directory)))))

(defun perl-live--session-name (root)
  "Return a readable, unique process name for ROOT."
  (format "%s:%s:%s" perl-live-name
          (file-name-nondirectory (directory-file-name root))
          (substring (secure-hash 'sha1 root) 0 8)))

(defun perl-live--process (&optional start)
  "Return the current project's live process.
When START is non-nil, start a missing session."
  (let ((process (gethash (perl-live--root) perl-live--sessions)))
    (cond
     ((and process (process-live-p process)) process)
     (start (perl-live-run))
     (t (user-error "No Perl live session for %s" (perl-live--root))))))

(defun perl-live--send-input (process text &optional file line)
  "Send TEXT to PROCESS, optionally identifying source FILE and LINE."
  (let* ((request (json-encode
                   (list (cons 'code (concat text "\n"))
                         (cons 'file (or file "(perl live)"))
                         (cons 'line (or line 1)))))
         (size (string-bytes (encode-coding-string request 'utf-8-unix))))
    (comint-send-string process (format "%d\n%s" size request))))

(defun perl-live--filter (process text)
  "Handle startup framing for PROCESS, then pass TEXT to the comint filter."
  (if (process-get process 'perl-live-ready)
      (comint-output-filter process text)
    (let ((pending (concat (process-get process 'perl-live-startup) text)))
      (if-let* ((offset (string-match (regexp-quote perl-live--ready-message) pending)))
          (progn
            (process-put process 'perl-live-ready t)
            (process-put process 'perl-live-startup nil)
            (comint-output-filter
             process (concat (substring pending 0 offset)
                             (substring pending (+ offset (length perl-live--ready-message))))))
        (process-put process 'perl-live-startup pending)))))

(defun perl-live--sentinel (process event)
  "Keep interpreter PROCESS startup errors and exit EVENT visible."
  (when (memq (process-status process) '(exit signal failed closed))
    (when (buffer-live-p (process-buffer process))
      (with-current-buffer (process-buffer process)
        (let ((inhibit-read-only t))
          (save-excursion
            (goto-char (point-max))
            (insert (or (process-get process 'perl-live-startup) "")
                    (format "\nPerl live %s" event))))))
    (when-let* ((root (process-get process 'perl-live-root)))
      (when (eq process (gethash root perl-live--sessions))
        (remhash root perl-live--sessions)))
    (process-put process 'perl-live-startup nil)))

(defun perl-live--await-ready (process)
  "Wait for PROCESS to finish startup, reporting useful failures."
  (let ((deadline (+ (float-time) perl-live-startup-timeout)))
    (while (and (process-live-p process)
                (not (process-get process 'perl-live-ready))
                (< (float-time) deadline))
      (accept-process-output process 0.05))
    (unless (and (process-live-p process) (process-get process 'perl-live-ready))
      (let* ((buffer (process-buffer process))
             (output (with-current-buffer buffer
                       (string-trim
                        (buffer-substring-no-properties
                         (or (process-get process 'perl-live-startup-start) (point-min))
                         (point-max)))))
             (detail (if (string-empty-p output)
                         (or (process-get process 'perl-live-startup)
                             "Interpreter did not report ready before the timeout")
                       (car (split-string output "\n" t)))))
        (user-error "Perl live failed to start: %s (see %s)"
                    detail (buffer-name buffer))))
    process))

(defun perl-live--kill-session ()
  "Stop the process belonging to a killed REPL buffer."
  (when-let* ((process (get-buffer-process (current-buffer))))
    (when (eq process (gethash perl-live--session-root perl-live--sessions))
      (remhash perl-live--session-root perl-live--sessions))
    (delete-process process)))

(defvar perl-live-repl-mode-map
  (let ((map (make-sparse-keymap)))
    (define-key map (kbd "C-c C-c") #'perl-live-interrupt)
    (define-key map (kbd "C-c C-k") #'perl-live-interrupt)
    map)
  "Keymap for `perl-live-repl-mode'.")

(define-derived-mode perl-live-repl-mode comint-mode "Perl Live"
  "Comint mode for a persistent Perl interpreter."
  (setq-local comint-input-sender #'perl-live--send-input
              ansi-color-for-comint-mode t
              comint-scroll-to-bottom-on-input t
              comint-scroll-to-bottom-on-output t
              comint-move-point-for-output t)
  (compilation-shell-minor-mode 1)
  (setq-local compilation-error-regexp-alist '(perl-live))
  (add-hook 'kill-buffer-hook #'perl-live--kill-session nil t))

;;;###autoload
(defun perl-live-run ()
  "Start or reuse the current project's interpreter and return its process."
  (interactive)
  (let* ((root (perl-live--root))
         (default-directory root)
         (process (gethash root perl-live--sessions)))
    (unless (and process (process-live-p process))
      (let* ((requested-bin (if (and (equal perl-live-bin "perl")
                                     (fboundp 'perlenv-get-perl-path))
                                (perlenv-get-perl-path)
                              perl-live-bin))
             (bin (or (and (file-name-directory requested-bin)
                           (executable-find (expand-file-name requested-bin root)))
                      (executable-find requested-bin)))
             (script (expand-file-name perl-live-script root))
             (switches perl-live-switches)
             (name (perl-live--session-name root))
             buffer startup-start)
        (unless bin
          (user-error "Perl executable not found: %s" requested-bin))
        (unless (file-readable-p script)
          (user-error "Perl live script is not readable: %s" script))
        (setq buffer (get-buffer-create (format "*%s*" name)))
        (when process (delete-process process))
        (with-current-buffer buffer
          (unless (derived-mode-p 'perl-live-repl-mode) (perl-live-repl-mode))
          (setq default-directory root
                perl-live--session-root root)
          (setq-local perl-live-bin bin
                      perl-live-script script
                      perl-live-switches switches)
          (setq startup-start (point-max)))
        (setq process
              (make-process :name name :buffer buffer
                            :command (append (list bin script "-j")
                                             (split-string-and-unquote switches))
                            :connection-type 'pipe :coding 'utf-8-unix
                            :noquery t :filter #'perl-live--filter
                            :sentinel #'perl-live--sentinel))
        (process-put process 'perl-live-root root)
        (process-put process 'perl-live-startup-start startup-start)
        (puthash root process perl-live--sessions)
        (condition-case error-data
            (perl-live--await-ready process)
          ((error quit)
           (delete-process process)
           (remhash root perl-live--sessions)
           (signal (car error-data) (cdr error-data))))))
    (when (called-interactively-p 'interactive)
      (display-buffer (process-buffer process)))
    process))

;;;###autoload
(defun perl-live-eval (text &optional file line)
  "Evaluate TEXT in the current project's interpreter.
FILE and LINE identify the source location used in diagnostics."
  (interactive "sPerl expression: ")
  (perl-live--send-input (perl-live--process t) text
                         (or file buffer-file-name (buffer-name))
                         (or line (line-number-at-pos (point) t))))

;;;###autoload
(defun perl-live-eval-region (start end)
  "Evaluate the region from START to END with its source location."
  (interactive "r")
  (perl-live-eval (buffer-substring-no-properties start end)
                  (or buffer-file-name (buffer-name))
                  (line-number-at-pos start t))
  (deactivate-mark))

;;;###autoload
(defun perl-live-eval-line ()
  "Evaluate the current line and advance to the next line."
  (interactive)
  (perl-live-eval-region (line-beginning-position) (line-end-position))
  (forward-line))

;;;###autoload
(defun perl-live-eval-region-or-line ()
  "Evaluate the active region, or the current line."
  (interactive)
  (if (use-region-p)
      (perl-live-eval-region (region-beginning) (region-end))
    (perl-live-eval-line)))

(defun perl-live--block-bounds ()
  "Return bounds inside the enclosing braces, or report a user error."
  (save-excursion
    (let* ((state (syntax-ppss))
           (open (cond
                  ((and (eq (char-after) ?{) (not (nth 3 state)) (not (nth 4 state)))
                   (point))
                  ((and (eq (char-before) ?})
                        (not (nth 3 (syntax-ppss (1- (point)))))
                        (not (nth 4 (syntax-ppss (1- (point))))))
                   (condition-case nil (scan-sexps (point) -1) (scan-error nil)))
                  (t (nth 1 state)))))
      (while (and open (not (eq (char-after open) ?{)))
        (setq open (nth 1 (syntax-ppss open))))
      (unless open (user-error "Point is not inside a brace-delimited block"))
      (let ((end (condition-case nil (scan-sexps open 1) (scan-error nil))))
        (unless end (user-error "The enclosing block has unmatched braces"))
        (cons (1+ open) (1- end))))))

;;;###autoload
(defun perl-live-eval-sexp ()
  "Evaluate inside the braces enclosing point."
  (interactive)
  (let ((bounds (perl-live--block-bounds)))
    (perl-live-eval-region (car bounds) (cdr bounds))))

;;;###autoload
(defun perl-live-stop ()
  "Stop the current project's session if it exists."
  (interactive)
  (let* ((root (perl-live--root))
         (process (gethash root perl-live--sessions)))
    (remhash root perl-live--sessions)
    (when process (delete-process process))
    (when (called-interactively-p 'interactive)
      (message "Perl live session stopped for %s" root))))

;;;###autoload
(defun perl-live-restart ()
  "Restart the current project's interpreter, or start a missing session."
  (interactive)
  (perl-live-stop)
  (let ((process (perl-live-run)))
    (when (called-interactively-p 'interactive)
      (display-buffer (process-buffer process)))
    process))

;;;###autoload
(defun perl-live-interrupt ()
  "Interrupt the current evaluation while retaining the session."
  (interactive)
  (interrupt-process (perl-live--process))
  (when (called-interactively-p 'interactive)
    (message "Perl live evaluation interrupted")))

;;;###autoload
(defun perl-live-switch-to-repl ()
  "Show the current project's REPL, starting it if needed."
  (interactive)
  (pop-to-buffer (process-buffer (perl-live--process t))))

(defvar perl-live-mode-map
  (let ((map (make-sparse-keymap)))
    (define-key map (kbd "C-c C-l") #'perl-live-run)
    (define-key map (kbd "C-c C-p") #'perl-live-stop)
    (define-key map (kbd "C-c C-r") #'perl-live-restart)
    (define-key map (kbd "C-c C-k") #'perl-live-interrupt)
    (define-key map (kbd "C-c C-z") #'perl-live-switch-to-repl)
    (define-key map (kbd "C-c C-c") #'perl-live-eval-region-or-line)
    (define-key map (kbd "C-M-x") #'perl-live-eval-sexp)
    map)
  "Keymap for `perl-live-mode'.")

;;;###autoload
(define-minor-mode perl-live-mode
  "Evaluate Perl in a persistent interpreter belonging to the current project."
  :lighter " Perl-Live"
  :keymap perl-live-mode-map
  :group 'perl-live)

(provide 'perl-live)
;;; perl-live.el ends here

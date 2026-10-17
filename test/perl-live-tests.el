;;; perl-live-tests.el --- Integration tests -*- lexical-binding: t; -*-

;;; Commentary:

;; Integration tests for perl-live.

;;; Code:

(require 'ert)
(require 'cl-lib)
(add-to-list 'load-path
             (expand-file-name ".." (file-name-directory load-file-name)))
(require 'perl-live)

(defvar perl-live-test--bin
  (or (getenv "PERL_LIVE_TEST_PERL") perl-live-bin))

(defun perl-live-test--cleanup (root)
  (maphash (lambda (_ process)
             (let ((buffer (process-buffer process)))
               (delete-process process)
               (when (buffer-live-p buffer) (kill-buffer buffer))))
           perl-live--sessions)
  (dolist (buffer (buffer-list))
    (with-current-buffer buffer
      (when (and perl-live--session-root
                 (file-in-directory-p perl-live--session-root root))
        (kill-buffer buffer))))
  (delete-directory root t))

(defmacro perl-live-test--with-project (&rest body)
  (declare (indent 0) (debug t))
  `(let* ((root (make-temp-file "perl-live-test-" t))
          (perl-live--sessions (make-hash-table :test 'equal))
          (perl-live-bin perl-live-test--bin))
     (unwind-protect
         (with-temp-buffer
           (setq default-directory (file-name-as-directory root))
           (write-region "" nil (expand-file-name "cpanfile" root) nil 'silent)
           ,@body)
       (perl-live-test--cleanup root))))

(defun perl-live-test--wait-output (process start marker)
  (let ((buffer (process-buffer process))
        (deadline (+ (float-time) 5))
        output)
    (while (progn
             (setq output
                   (with-current-buffer buffer
                     (buffer-substring-no-properties start (point-max))))
             (not (string-match (regexp-quote marker) output)))
      (unless (and (process-live-p process) (< (float-time) deadline))
        (ert-fail (format "Evaluation did not finish: %S" output)))
      (accept-process-output process 0.05))
    (substring output 0 (match-beginning 0))))

(defun perl-live-test--capture (send &optional barrier-sender)
  "Collect output from SEND up to a separate evaluation barrier."
  (let* ((process (perl-live--process t))
         (start (with-current-buffer (process-buffer process) (point-max))))
    (funcall send process)
    (funcall (or barrier-sender #'perl-live--send-input)
             process "print qq(__PERL_LIVE_TEST_DONE__\\n);")
    (perl-live-test--wait-output process start "__PERL_LIVE_TEST_DONE__\n")))

(defun perl-live-test--eval (source &optional sender)
  (let ((send (or sender #'perl-live--send-input)))
    (perl-live-test--capture
     (lambda (process) (funcall send process source)) send)))

(ert-deftest perl-live-mode-bindings-are-local ()
  (require 'cperl-mode)
  (with-temp-buffer
    (cperl-mode)
    (let ((original (key-binding (kbd "C-c C-c"))))
      (should-not (eq original #'perl-live-eval-region-or-line))
      (perl-live-mode 1)
      (should (eq (key-binding (kbd "C-c C-c")) #'perl-live-eval-region-or-line))
      (should (eq (key-binding (kbd "C-M-x")) #'perl-live-eval-sexp))
      (should (eq (key-binding (kbd "C-c C-k")) #'perl-live-interrupt))
      (perl-live-mode -1)
      (should (eq (key-binding (kbd "C-c C-c")) original)))))

(ert-deftest perl-live-repeated-evaluations-and-globals ()
  (perl-live-test--with-project
    (let ((process-connection-type t))
      (should-not (process-tty-name (perl-live-run))))
    (should (equal "" (perl-live-test--eval "my $answer = 41;")))
    (should (equal "42\n" (perl-live-test--eval "print ++$answer, qq(\\n);")))
    (should (equal "" (perl-live-test--eval "my @list = (1, 2, 3);")))
    (should (equal "3\n" (perl-live-test--eval "print scalar @list, qq(\\n);")))))

(ert-deftest perl-live-long-source-line ()
  (perl-live-test--with-project
    (should
     (equal "200000\n"
            (perl-live-test--eval
             (concat "print length(q{" (make-string 200000 ?x) "}), qq(\\n);"))))))

(ert-deftest perl-live-unicode-input-and-output ()
  (perl-live-test--with-project
    (should (equal "café привет 😀\n"
                   (perl-live-test--eval "print qq(café привет 😀\\n);")))
    (should (equal "6\n"
                   (perl-live-test--eval "print length(q{привет}), qq(\\n);")))
    (let ((error-output (perl-live-test--eval "die qq(café привет\\n);")))
      (should (string-match-p "café привет" error-output))
      (should-not (string-match-p "Wide character" error-output)))))

(ert-deftest perl-live-recovers-after-errors ()
  (perl-live-test--with-project
    (should (string-match-p "intentional failure"
                            (perl-live-test--eval "die qq(intentional failure\\n);")))
    (should (equal "42\n" (perl-live-test--eval "print 6 * 7, qq(\\n);")))
    (should (string-match-p "syntax error"
                            (perl-live-test--eval "my $broken = ;")))
    (should (equal "56\n" (perl-live-test--eval "print 7 * 8, qq(\\n);")))))

(ert-deftest perl-live-pragmas-persist ()
  (perl-live-test--with-project
    (should (equal "" (perl-live-test--eval "no strict 'vars';")))
    (should (equal "12\n"
                   (perl-live-test--eval
                    "$undeclared = 12; print $undeclared, qq(\\n);")))))

(ert-deftest perl-live-default-features-persist ()
  (perl-live-test--with-project
    (should (equal "1\n"
                   (perl-live-test--eval
                    "sub next_number { state $n = 0; ++$n }; say next_number();")))
    (should (equal "2\n" (perl-live-test--eval "say next_number();")))))

(ert-deftest perl-live-comint-input-sender ()
  (perl-live-test--with-project
    (let* ((process (perl-live-run))
           (sender (buffer-local-value 'comint-input-sender (process-buffer process))))
      (should (equal "42\n" (perl-live-test--eval "print 6 * 7, qq(\\n);" sender)))
      (should (equal "48\n" (perl-live-test--eval "print 6 * 8, qq(\\n);" sender))))))

(ert-deftest perl-live-empty-switches-disable-globalization ()
  (perl-live-test--with-project
    (let ((perl-live-switches ""))
      (should (equal "" (perl-live-test--eval "my $private = 17;")))
      (should (string-match-p "Global symbol.*private"
                              (perl-live-test--eval "print $private, qq(\\n);"))))))

(ert-deftest perl-live-stop-and-restart-without-session ()
  (perl-live-test--with-project
    (perl-live-stop)
    (should (= 0 (hash-table-count perl-live--sessions)))
    (let ((first (perl-live-restart)))
      (should (process-live-p first))
      (should (eq first (perl-live-run)))
      (let ((second (perl-live-restart)))
        (should-not (eq first second))
        (should-not (process-live-p first))
        (should (process-live-p second))))
    (perl-live-stop)
    (perl-live-stop)))

(ert-deftest perl-live-evaluation-starts-a-missing-session ()
  (perl-live-test--with-project
    (should (= 0 (hash-table-count perl-live--sessions)))
    (perl-live-eval "my $answer = 41;")
    (should (equal "42\n" (perl-live-test--eval "say ++$answer;")))))

(ert-deftest perl-live-startup-reports-missing-executable ()
  (perl-live-test--with-project
    (let* ((perl-live-bin (expand-file-name "missing-perl" root))
           (error-data (should-error (perl-live-run) :type 'user-error)))
      (should (string-match-p "Perl executable not found" (cadr error-data)))
      (should (= 0 (hash-table-count perl-live--sessions))))))

(ert-deftest perl-live-startup-reports-missing-script ()
  (perl-live-test--with-project
    (let* ((perl-live-script (expand-file-name "missing.pl" root))
           (error-data (should-error (perl-live-run) :type 'user-error)))
      (should (string-match-p "script is not readable" (cadr error-data))))))

(ert-deftest perl-live-startup-reports-missing-dependency ()
  (perl-live-test--with-project
    (should (equal "old output\n" (perl-live-test--eval "print qq(old output\\n);")))
    (perl-live-stop)
    (let ((perl-live-script (expand-file-name "broken.pl" root)))
      (write-region "use PerlLive::MissingDependency;\n" nil perl-live-script nil 'silent)
      (let ((error-data (should-error (perl-live-run) :type 'user-error)))
        (should (string-match-p "MissingDependency" (cadr error-data)))
        (should (= 0 (hash-table-count perl-live--sessions)))))))

(ert-deftest perl-live-startup-timeout-cleans-up ()
  (perl-live-test--with-project
    (let ((perl-live-script (expand-file-name "slow.pl" root))
          (perl-live-startup-timeout 0.1))
      (write-region "sleep 30;\n" nil perl-live-script nil 'silent)
      (should-error (perl-live-run) :type 'user-error)
      (should (= 0 (hash-table-count perl-live--sessions))))))

(ert-deftest perl-live-interrupt-keeps-session-state ()
  (perl-live-test--with-project
    (should (equal "" (perl-live-test--eval "my $answer = 41;")))
    (let* ((process (perl-live--process))
           (start (with-current-buffer (process-buffer process) (point-max))))
      (perl-live--send-input process "print qq(__BUSY__\\n); while (1) {}")
      (perl-live-test--wait-output process start "__BUSY__\n")
      (perl-live-interrupt)
      (perl-live-test--wait-output process start "Evaluation interrupted\n")
      (should (eq process (perl-live--process)))
      (should (equal "42\n" (perl-live-test--eval "say ++$answer;"))))))

(ert-deftest perl-live-block-from-inside-an-identifier ()
  (with-temp-buffer
    (cperl-mode)
    (insert "if (1) {\n    print 42;\n}\n")
    (goto-char (point-min))
    (search-forward "print")
    (backward-char 2)
    (let (captured)
      (cl-letf (((symbol-function 'perl-live-eval)
                 (lambda (text &rest _) (setq captured text))))
        (perl-live-eval-sexp))
      (should (equal "\n    print 42;\n" captured)))))

(ert-deftest perl-live-block-through-nested-parentheses ()
  (with-temp-buffer
    (cperl-mode)
    (insert "if (1) {\n    print(join(q{,}, @values));\n}\n")
    (goto-char (point-min))
    (search-forward "@values")
    (let* ((bounds (perl-live--block-bounds))
           (source (buffer-substring-no-properties (car bounds) (cdr bounds))))
      (should (equal "\n    print(join(q{,}, @values));\n" source)))))

(ert-deftest perl-live-block-ignores-braces-in-strings-and-comments ()
  (with-temp-buffer
    (cperl-mode)
    (insert "if (1) {\n    print \"a } brace\"; # }\n}\n")
    (goto-char (point-min))
    (search-forward "brace")
    (let ((bounds (perl-live--block-bounds)))
      (should (equal "\n    print \"a } brace\"; # }\n"
                     (buffer-substring-no-properties (car bounds) (cdr bounds)))))))

(ert-deftest perl-live-block-at-opening-or-after-closing-brace ()
  (with-temp-buffer
    (cperl-mode)
    (insert "{ print 42; }")
    (goto-char (point-min))
    (should (equal '(2 . 13) (perl-live--block-bounds)))
    (goto-char (point-max))
    (should (equal '(2 . 13) (perl-live--block-bounds)))))

(ert-deftest perl-live-block-rejects-missing-or-unmatched-braces ()
  (with-temp-buffer
    (cperl-mode)
    (insert "print 42;")
    (goto-char (point-min))
    (should-error (perl-live--block-bounds) :type 'user-error)
    (erase-buffer)
    (insert "if (1) { print 42;")
    (goto-char (point-max))
    (should-error (perl-live--block-bounds) :type 'user-error)))

(ert-deftest perl-live-source-locations-and-error-navigation ()
  (perl-live-test--with-project
    (setq buffer-file-name (expand-file-name "source with spaces.pl" root))
    (insert (make-string 26 ?\n) "die 'boom';\n")
    (write-region (point-min) (point-max) buffer-file-name nil 'silent)
    (goto-char (point-min))
    (forward-line 26)
    (let* ((source-buffer (current-buffer))
           (start (point))
           (end (line-end-position))
           (output (perl-live-test--capture
                    (lambda (_) (perl-live-eval-region start end))))
           (repl (process-buffer (perl-live--process))))
      (should (string-match-p
               (regexp-quote (format "at %s line 27" buffer-file-name)) output))
      (save-window-excursion
        (with-current-buffer repl
          (goto-char (point-min))
          (next-error 1 t))
        (with-current-buffer source-buffer
          (should (= 27 (line-number-at-pos))))))))

(ert-deftest perl-live-project-sessions-are-independent ()
  (perl-live-test--with-project
    (let ((a (expand-file-name "a" root))
          (b (expand-file-name "b" root))
          process-a process-b)
      (dolist (directory (list a b))
        (make-directory directory)
        (write-region "" nil (expand-file-name "cpanfile" directory) nil 'silent))
      (let ((default-directory (file-name-as-directory a)))
        (should (equal "" (perl-live-test--eval "my $answer = 41;")))
        (setq process-a (perl-live--process))
        (should (equal (concat a "\n")
                       (perl-live-test--eval "use Cwd; print getcwd(), qq(\\n);"))))
      (let ((default-directory (file-name-as-directory b)))
        (should (equal "" (perl-live-test--eval "my $answer = 99;")))
        (setq process-b (perl-live--process))
        (should-not (eq process-a process-b))
        (should (equal "100\n" (perl-live-test--eval "say ++$answer;"))))
      (let ((default-directory (file-name-as-directory a)))
        (should (equal "42\n" (perl-live-test--eval "say ++$answer;")))
        (perl-live-stop))
      (should (process-live-p process-b)))))

(ert-deftest perl-live-repl-retains-project-settings ()
  (perl-live-test--with-project
    (let ((perl-live-switches ""))
      (let* ((process (perl-live-run))
             (buffer (process-buffer process)))
        (with-current-buffer buffer
          (should (equal perl-live-bin perl-live-test--bin))
          (should (equal "" perl-live-switches))
          (should (equal (file-name-as-directory (file-truename root))
                         (perl-live--root)))
          (should (process-live-p (perl-live-restart))))))))

(ert-deftest perl-live-killing-repl-stops-session ()
  (perl-live-test--with-project
    (let ((process (perl-live-run)))
      (kill-buffer (process-buffer process))
      (should-not (process-live-p process))
      (should (= 0 (hash-table-count perl-live--sessions))))))

(ert-deftest perl-live-projects-with-same-name-and-different-interpreters ()
  (skip-unless (file-executable-p "/bin/sh"))
  (perl-live-test--with-project
    (let ((a (expand-file-name "one/project" root))
          (b (expand-file-name "two/project" root))
          (wrapper (expand-file-name "custom-perl" root))
          process-a process-b)
      (write-region (format "#!/bin/sh\nexec %s \"$@\"\n"
                            (shell-quote-argument (executable-find perl-live-test--bin)))
                    nil wrapper nil 'silent)
      (set-file-modes wrapper #o755)
      (dolist (directory (list a b))
        (make-directory directory t)
        (write-region "" nil (expand-file-name "cpanfile" directory) nil 'silent))
      (let ((default-directory (file-name-as-directory a)))
        (setq process-a (perl-live-run)))
      (let ((default-directory (file-name-as-directory b))
            (perl-live-bin wrapper))
        (setq process-b (perl-live-run))
        (should (equal wrapper (car (process-command process-b))))
        (should (equal "42\n" (perl-live-test--eval "say 42;"))))
      (should-not (eq (process-buffer process-a) (process-buffer process-b)))
      (should-not (equal (process-name process-a) (process-name process-b))))))

(ert-deftest perl-live-project-relative-executable ()
  (skip-unless (file-executable-p "/bin/sh"))
  (perl-live-test--with-project
    (let ((bin-dir (expand-file-name "bin" root))
          (wrapper "bin/project-perl"))
      (make-directory bin-dir t)
      (write-region (format "#!/bin/sh\nexec %s \"$@\"\n"
                            (shell-quote-argument (executable-find perl-live-test--bin)))
                    nil (expand-file-name wrapper root) nil 'silent)
      (set-file-modes (expand-file-name wrapper root) #o755)
      (let ((perl-live-bin wrapper))
        (let ((process (perl-live-run)))
          (should (process-live-p process))
          (should (equal "42\n" (perl-live-test--eval "say 42;"))))))))

(defun perl-live-test--send-terminal (process text)
  (process-send-string process (concat text "\n"))
  (process-send-eof process))

(ert-deftest perl-live-terminal-interface ()
  (perl-live-test--with-project
    (let* ((process-connection-type t)
           (buffer (make-comint perl-live-name perl-live-test--bin nil perl-live-script "-g"))
           (process (get-buffer-process buffer)))
      (puthash (perl-live--root) process perl-live--sessions)
      (with-current-buffer buffer (setq perl-live--session-root (perl-live--root)))
      (unless (process-tty-name process)
        (ert-skip "A terminal connection is unavailable"))
      (set-process-coding-system process 'utf-8-unix 'utf-8-unix)
      (should (equal "41\n"
                     (perl-live-test--eval "my $answer = 41; say $answer;"
                                           #'perl-live-test--send-terminal)))
      (should (equal "42\n"
                     (perl-live-test--eval "say ++$answer;"
                                           #'perl-live-test--send-terminal))))))

(provide 'perl-live-tests)
;;; perl-live-tests.el ends here

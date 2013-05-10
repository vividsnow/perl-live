(start-process perl-live-name (format "*%s*" perl-live-name) perl-live-bin perl-live-script)
(delete-process perl-live-name)
(list-processes)

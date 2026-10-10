;;; pre-commit.el-test.el --- Tests for pre-commit.el -*- lexical-binding: t; -*-

;;; Code:

(require 'ert)
(require 'ert-x)

(add-to-list 'load-path (file-name-directory (directory-file-name default-directory)))

(require 'pre-commit)

(defmacro with-temp-git-repo (&rest body)
  "Execute BODY with `default-directory' bound to a fresh temporary Git repository.
A `.git' directory is created so that `vc-git-root' detects the repository."
  (declare (indent 0) (debug t))
  `(ert-with-temp-directory root
     (let ((default-directory root))
       (make-directory (expand-file-name ".git" root) t)
       ,@body)))

(ert-deftest pre-commit-available-hooks-no-git-repo-returns-nil ()
  (ert-with-temp-directory dir
    (let ((default-directory dir))
      (should (null (pre-commit-available-hooks))))))

(ert-deftest pre-commit-available-hooks-no-config-returns-nil ()
  (with-temp-git-repo
    (should (null (pre-commit-available-hooks)))))

(ert-deftest pre-commit-available-hooks-reads-yaml-config ()
  (with-temp-git-repo
    (let ((config (expand-file-name ".pre-commit-config.yaml" root)))
      (with-temp-buffer
        (insert "- repo: https://github.com/psf/black\n"
                "  rev: 23.0.0\n"
                "  hooks:\n"
                "    - id: black\n"
                "- repo: local\n"
                "  hooks:\n"
                "    - id: trailing-whitespace\n"
                "    - id: end-of-file-fixer\n")
        (write-region (point-min) (point-max) config)))
    (should (equal '("black" "end-of-file-fixer" "trailing-whitespace")
                   (pre-commit-available-hooks)))))

(ert-deftest pre-commit-available-hooks-falls-back-to-yml ()
  (with-temp-git-repo
    (let ((config (expand-file-name ".pre-commit-config.yml" root)))
      (with-temp-buffer
        (insert "- repo: local\n"
                "  hooks:\n"
                "    - id: my-hook\n")
        (write-region (point-min) (point-max) config)))
    (should (equal '("my-hook") (pre-commit-available-hooks)))))

(ert-deftest pre-commit-available-hooks-prefers-yaml-over-yml ()
  (with-temp-git-repo
    (let ((yaml-config (expand-file-name ".pre-commit-config.yaml" root))
          (yml-config (expand-file-name ".pre-commit-config.yml" root)))
      (with-temp-buffer
        (insert "- repo: local\n  hooks:\n    - id: from-yaml\n")
        (write-region (point-min) (point-max) yaml-config))
      (with-temp-buffer
        (insert "- repo: local\n  hooks:\n    - id: from-yml\n")
        (write-region (point-min) (point-max) yml-config)))
    (should (equal '("from-yaml") (pre-commit-available-hooks)))))

(ert-deftest pre-commit-available-hooks-multiple-spaces-before-id ()
  (with-temp-git-repo
    (let ((config (expand-file-name ".pre-commit-config.yaml" root)))
      (with-temp-buffer
        (insert "- repo: local\n"
                "  hooks:\n"
                "    -   id: my-hook\n"
                "    - id: other\n"
                "    - id:  still-another\r\n"
                "    -\tid:\tyet-another\n")
        (write-region (point-min) (point-max) config)))
    (should (equal '("my-hook" "other" "still-another" "yet-another")
                   (pre-commit-available-hooks)))))

(ert-deftest pre-commit-available-hooks-dedups-and-sorts ()
  (with-temp-git-repo
    (let ((config (expand-file-name ".pre-commit-config.yaml" root)))
      (with-temp-buffer
        (insert "- repo: local\n"
                "  hooks:\n"
                "    - id: zeta\n"
                "    - id: alpha\n"
                "    - id: zeta\n"
                "    - id: mid\n")
        (write-region (point-min) (point-max) config)))
    (should (equal '("alpha" "mid" "zeta")
                   (pre-commit-available-hooks)))))

(ert-deftest pre-commit-run-interactive-calls-run ()
  (with-temp-git-repo
    (let ((compile-called nil))
      (cl-letf (((symbol-function 'compile) (lambda (cmd) (setq compile-called cmd))))
        (call-interactively 'pre-commit-run)
        (should (equal "pre-commit run --color=always" compile-called))))))

(ert-deftest pre-commit-run-noninteractive-passes-args ()
  (with-temp-git-repo
    (let ((compile-called nil))
      (cl-letf (((symbol-function 'compile) (lambda (cmd) (setq compile-called cmd))))
        (pre-commit-run "--all-files")
        (should (equal "pre-commit run --color=always --all-files" compile-called))))))

(ert-deftest pre-commit-run-hook-noninteractive ()
  (with-temp-git-repo
    (let ((compile-called nil))
      (cl-letf (((symbol-function 'compile) (lambda (cmd) (setq compile-called cmd))))
        (pre-commit-run-hook "black")
        (should (equal "pre-commit run --color=always black" compile-called))))))

(ert-deftest pre-commit-run-hook-interactive ()
  (with-temp-git-repo
    (let ((compile-called nil))
      (with-temp-buffer
        (insert "- repo: local\n  hooks:\n    - id: black\n")
        (write-region (point-min) (point-max)
                      (expand-file-name ".pre-commit-config.yaml" root)))
      (cl-letf (((symbol-function 'completing-read) (lambda (&rest _) "black"))
                ((symbol-function 'compile) (lambda (cmd) (setq compile-called cmd))))
        (call-interactively 'pre-commit-run-hook)
        (should (equal "pre-commit run --color=always black" compile-called))))))

(ert-deftest pre-commit-run-on-file-noninteractive ()
  (with-temp-git-repo
    (let ((compile-called nil))
      (cl-letf (((symbol-function 'compile) (lambda (cmd) (setq compile-called cmd))))
        (pre-commit-run-on-file "/tmp/foo.el")
        (should (equal "pre-commit run --color=always --files /tmp/foo.el" compile-called))))))

(ert-deftest pre-commit-run-on-file-interactive ()
  (with-temp-git-repo
    (let ((compile-called nil))
      (cl-letf (((symbol-function 'compile) (lambda (cmd) (setq compile-called cmd))))
        (with-current-buffer (generate-new-buffer "test")
          (setq buffer-file-name "/tmp/foo.el")
          (call-interactively 'pre-commit-run-on-file)
          (should (equal "pre-commit run --color=always --files /tmp/foo.el" compile-called))
          (kill-buffer))))))

(ert-deftest pre-commit-run-hook-on-file-noninteractive ()
  (with-temp-git-repo
    (let ((compile-called nil))
      (cl-letf (((symbol-function 'compile) (lambda (cmd) (setq compile-called cmd))))
        (pre-commit-run-hook-on-file "black" "/tmp/foo.el")
        (should (equal "pre-commit run --color=always black --files /tmp/foo.el" compile-called))))))

(ert-deftest pre-commit-run-hook-on-file-interactive ()
  (with-temp-git-repo
    (let ((compile-called nil))
      (with-temp-buffer
        (insert "- repo: local\n  hooks:\n    - id: black\n")
        (write-region (point-min) (point-max)
                      (expand-file-name ".pre-commit-config.yaml" root)))
      (cl-letf (((symbol-function 'completing-read) (lambda (&rest _) "black"))
                ((symbol-function 'compile) (lambda (cmd) (setq compile-called cmd))))
        (with-current-buffer (generate-new-buffer "test")
          (setq buffer-file-name "/tmp/foo.el")
          (call-interactively 'pre-commit-run-hook-on-file)
          (should (equal "pre-commit run --color=always black --files /tmp/foo.el" compile-called))
          (kill-buffer))))))

(ert-deftest pre-commit-repeat-runs-last ()
  (with-temp-git-repo
    (let ((compile-called nil))
      (cl-letf (((symbol-function 'compile) (lambda (cmd) (setq compile-called cmd))))
        (pre-commit-run "--all-files")
        (pre-commit-repeat)
        (should (equal "pre-commit run --color=always --all-files" compile-called))))))

(ert-deftest pre-commit-repeat-errors-when-none ()
  (with-temp-git-repo
    (should-error (pre-commit-repeat) :type 'user-error)))

(ert-deftest pre-commit-dispatch-uncommitted-without-hook ()
  (with-temp-git-repo
    (let ((compile-called nil))
      (with-temp-buffer
        (insert "- repo: local\n  hooks:\n    - id: black\n")
        (write-region (point-min) (point-max)
                      (expand-file-name ".pre-commit-config.yaml" root)))
      (cl-letf (((symbol-function 'compile) (lambda (cmd) (setq compile-called cmd))))
        (setq pre-commit-selected-hook nil)
        (call-interactively 'pre-commit-dispatch-uncommitted)
        (should (equal "pre-commit run --color=always" compile-called))))))

(ert-deftest pre-commit-autoupdate-noninteractive ()
  (with-temp-git-repo
    (let ((compile-called nil))
      (cl-letf (((symbol-function 'compile) (lambda (cmd) (setq compile-called cmd))))
        (pre-commit-autoupdate)
        (should (equal "pre-commit autoupdate --color=always" compile-called))))))

(ert-deftest pre-commit-autoupdate-no-git-repo-errors ()
  (ert-with-temp-directory dir
    (let ((default-directory dir))
      (should-error (pre-commit-autoupdate) :type 'user-error))))

(ert-deftest pre-commit-autoupdate-does-not-affect-repeat ()
  (with-temp-git-repo
    (let ((compile-called nil))
      (cl-letf (((symbol-function 'compile) (lambda (cmd) (setq compile-called cmd))))
        (pre-commit-run "--all-files")
        (pre-commit-autoupdate)
        (pre-commit-repeat)
        (should (equal "pre-commit run --color=always --all-files" compile-called))))))

(ert-deftest pre-commit-validate-config-noninteractive-yaml ()
  (with-temp-git-repo
    (let ((config (expand-file-name ".pre-commit-config.yaml" root))
          (compile-called nil))
      (with-temp-buffer
        (insert "- repo: local\n  hooks:\n    - id: black\n")
        (write-region (point-min) (point-max) config))
      (cl-letf (((symbol-function 'compile) (lambda (cmd) (setq compile-called cmd))))
        (pre-commit-validate-config)
        (should (equal (format "pre-commit validate-config --color=always %s"
                               (shell-quote-argument config))
                       compile-called))))))

(ert-deftest pre-commit-validate-config-falls-back-to-yml ()
  (with-temp-git-repo
    (let ((config (expand-file-name ".pre-commit-config.yml" root))
          (compile-called nil))
      (with-temp-buffer
        (insert "- repo: local\n  hooks:\n    - id: black\n")
        (write-region (point-min) (point-max) config))
      (cl-letf (((symbol-function 'compile) (lambda (cmd) (setq compile-called cmd))))
        (pre-commit-validate-config)
        (should (equal (format "pre-commit validate-config --color=always %s"
                               (shell-quote-argument config))
                       compile-called))))))

(ert-deftest pre-commit-validate-config-no-config-errors ()
  (with-temp-git-repo
    (should-error (pre-commit-validate-config) :type 'user-error)))

(ert-deftest pre-commit-validate-config-does-not-affect-repeat ()
  (with-temp-git-repo
    (let ((config (expand-file-name ".pre-commit-config.yaml" root))
          (compile-called nil))
      (with-temp-buffer
        (insert "- repo: local\n  hooks:\n    - id: black\n")
        (write-region (point-min) (point-max) config))
      (cl-letf (((symbol-function 'compile) (lambda (cmd) (setq compile-called cmd))))
        (pre-commit-run "--all-files")
        (pre-commit-validate-config)
        (pre-commit-repeat)
        (should (equal "pre-commit run --color=always --all-files" compile-called))))))

(provide 'pre-commit.el-test)

;;; pre-commit.el-test.el ends here

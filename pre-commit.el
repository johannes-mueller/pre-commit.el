;;; pre-commit.el --- Emacs frontend for the pre-commit tool -*- lexical-binding: t; -*-

;; Copyright (C) 2025 Johannes Mueller

;; Author: Johannes Mueller <github@johannes-mueller.org>
;; Version: 0.1.0
;; Package-Requires: ((emacs "30.1") (transient "0.10.1"))
;; Keywords: tools, vc
;; URL: https://github.com/johannes-mueller/pre-commit.el

;; This file is not part of GNU Emacs.

;; This program is free software; you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation, either version 3 of the License, or
;; (at your option) any later version.

;; This program is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.

;; You should have received a copy of the GNU General Public License
;; along with this program.  If not, see <https://www.gnu.org/licenses/>.

;;; Commentary:

;; `pre-commit.el' provides functions and a transient interface to run
;; `pre-commit' commands from Emacs.

;;; Code:

(require 'cl-lib)
(require 'subr-x)
(require 'vc-git)
(require 'transient)

(defgroup pre-commit nil
  "Emacs frontend for the pre-commit tool."
  :group 'tools
  :prefix "pre-commit-")

(defcustom pre-commit-command "pre-commit"
  "The path to the `pre-commit' executable."
  :type 'string
  :group 'pre-commit)

(defcustom pre-commit-use-color t
  "Whether to use colored output when running pre-commit.
If non-nil, `--color=always' is passed to pre-commit.
If nil, `--color=never' is passed to pre-commit."
  :type 'boolean
  :group 'pre-commit)

(defvar pre-commit-selected-hook nil
  "Currently selected hook for dispatch commands.
When nil or empty string, run all hooks.")

(defvar pre-commit--last-command-table (make-hash-table :test 'equal)
  "Table mapping project roots to last run argument lists.")

(defun pre-commit--project-root ()
  "Return the Git project root for `default-directory', or nil if none."
  (vc-git-root default-directory))

(defun pre-commit--find-config ()
  "Find pre-commit config file in project root.
Return path to `.pre-commit-config.yaml' or `.yml', preferring `.yaml'.
Return nil if neither exists."
  (when-let* ((root (pre-commit--project-root))
              (yaml (expand-file-name ".pre-commit-config.yaml" root))
              (yml (expand-file-name ".pre-commit-config.yml" root)))
    (cond ((file-exists-p yaml) yaml)
          ((file-exists-p yml) yml))))

(defun pre-commit--read-lines (file)
  "Read all lines from FILE, returning a list of strings."
  (with-temp-buffer
    (insert-file-contents-literally file)
    (goto-char (point-min))
    (let ((lines nil))
      (while (not (eobp))
        (let ((line (buffer-substring-no-properties (line-beginning-position)
                                                    (line-end-position))))
          (push line lines))
        (forward-line 1))
      (nreverse lines))))

(defconst pre-commit--hook-id-regex
  "^[[:space:]]*-[[:space:]]*id:[[:space:]]*[^[:space:]]+")

(defconst pre-commit--hook-id-parse-regex
  "^-[[:space:]]*id:[[:space:]]*\\([^[:space:]]+\\)")

(defun pre-commit--extract-hook-ids-from-lines (lines)
  "Extract hook IDs from config LINES.
Looks for lines like: `  - id: hookname'.  Returns a sorted list of unique ids."
  (let ((ids nil))
    (dolist (line lines ids)
      (when (string-match-p pre-commit--hook-id-regex line)
        (let ((trimmed (string-trim line)))
          (when (string-match pre-commit--hook-id-parse-regex trimmed)
            (let ((id (match-string 1 trimmed)))
              (push id ids))))))
    (seq-uniq (sort ids #'string<))))

(defun pre-commit--extract-hooks-from-file (file)
  "Extract hook IDs from config FILE.  Returns sorted unique list."
  (when-let* (file)
    (pre-commit--extract-hook-ids-from-lines
     (pre-commit--read-lines file))))

;;;###autoload
(defun pre-commit-available-hooks ()
  "Return the list of available pre-commit hooks for the current project.
This is the sorted list of unique hook IDs defined in the pre-commit
configuration file (`pre-commit--find-config') of the current project.
Returns nil if no configuration file exists."
  (when-let* ((config (pre-commit--find-config)))
    (pre-commit--extract-hooks-from-file config)))

(defun pre-commit--select-hook ()
  "Prompt user to select a hook from available hooks in current project.
Signals `user-error' if no hooks are available."
  (if-let* ((hooks (pre-commit-available-hooks))
            (hooks (if (seq-empty-p hooks) nil hooks)))
      (completing-read "Select hook: " hooks nil t)
    (user-error "No pre-commit hooks found in config")))

(defun pre-commit--compose-command-string (args)
  "Compose shell command string for pre-commit with ARGS.
ARGS is a list of strings.  The color flag from `pre-commit-use-color' is
automatically appended after the subcommand."
  (let* ((color-flag (if pre-commit-use-color "--color=always" "--color=never"))
         (parts (cons pre-commit-command args))
         (subcommand (cadr parts))
         (rest-args (cddr parts)))
    (concat (shell-quote-argument (car parts)) " " (shell-quote-argument subcommand)
            " " color-flag
            (if rest-args
                (concat " " (mapconcat #'shell-quote-argument rest-args " "))
              ""))))

(defun pre-commit--record-last-command (root args)
  "Record ARGS as last run for project ROOT."
  (puthash root (copy-sequence args) pre-commit--last-command-table))

(defun pre-commit--lookup-last-command (root)
  "Look up last run args for project ROOT.  Returns list or nil."
  (gethash root pre-commit--last-command-table))

(defun pre-commit--run-in-root (root args)
  "Run pre-commit with ARGS in project ROOT without recording it.
Changes `default-directory' to ROOT and runs `compile'."
  (when root
    (let ((default-directory root))
      (compile (pre-commit--compose-command-string args)))))

(defun pre-commit--run-args-in-root (root args &optional extra-args)
  "Run pre-commit with ARGS in project ROOT.
Records ARGS for `pre-commit-repeat', then runs ARGS followed by
EXTRA-ARGS.  EXTRA-ARGS are not recorded, so that arguments coming
from a transient are re-evaluated on every invocation."
  (when root
    (pre-commit--record-last-command root args)
    (pre-commit--run-in-root root (append args extra-args))))

(defun pre-commit--maybe-run-args (args &optional extra-args)
  "Run pre-commit with ARGS in current project root, recording it.
EXTRA-ARGS are appended to the command but not recorded.
Signals `user-error' if not in a git repo."
  (if-let* ((root (pre-commit--project-root)))
      (pre-commit--run-args-in-root root args extra-args)
    (user-error "Not in a git repository")))

(defun pre-commit--maybe-run-args-no-record (args)
  "Run pre-commit with ARGS in current project root, without recording it.
Signals `user-error' if not in a git repo."
  (if-let* ((root (pre-commit--project-root)))
      (pre-commit--run-in-root root args)
    (user-error "Not in a git repository")))

(defun pre-commit--file-if-visiting ()
  "Return the value of the variable `buffer-file-name'.
Return nil if the current buffer does not visit a file."
  (buffer-file-name))

;;;###autoload
(defun pre-commit-run (&rest args)
  "Run pre-commit with ARGS.
ARGS are passed to the `run' subcommand of `pre-commit-command'.
If called interactively, runs `pre-commit run' with no extra args."
  (interactive)
  (pre-commit--maybe-run-args (cons "run" args)))

;;;###autoload
(defun pre-commit-run-hook (hook)
  "Run a specific HOOK.
If called interactively, prompts for HOOK."
  (interactive
   (list (pre-commit--select-hook)))
  (pre-commit--maybe-run-args (list "run" hook)))

;;;###autoload
(defun pre-commit-run-on-file (file)
  "Run all hooks on FILE.
If called interactively, runs on the value of the variable `buffer-file-name'
of the current buffer."
  (interactive
   (let ((f (buffer-file-name)))
     (unless f
       (user-error "Current buffer has no file"))
     (list f)))
  (pre-commit--maybe-run-args (list "run" "--files" file)))

;;;###autoload
(defun pre-commit-run-hook-on-file (hook file)
  "Run HOOK on FILE.
If called interactively, prompts for HOOK and uses current buffer's file."
  (interactive
   (let ((f (buffer-file-name)))
     (unless f
       (user-error "Current buffer has no file"))
     (list (pre-commit--select-hook) f)))
  (pre-commit--maybe-run-args (list "run" hook "--files" file)))

;;;###autoload
(defun pre-commit-repeat (&optional extra-args)
  "Repeat the last pre-commit run for the current project.
EXTRA-ARGS are appended to the replayed command and are not
recorded, so they are re-evaluated on every invocation.
Signals `user-error' if no previous run is recorded."
  (interactive (list (transient-args 'pre-commit-dispatch)))
  (if-let* ((root (pre-commit--project-root))
            (last (pre-commit--lookup-last-command root))
            (last (if (seq-empty-p last) nil last)))
      (pre-commit--run-args-in-root root last extra-args)
    (user-error "No previous pre-commit run recorded")))

;;;###autoload
(defun pre-commit-autoupdate ()
  "Update the pre-commit config to the latest repos' versions.
Signals `user-error' if not in a git repository."
  (interactive)
  (pre-commit--maybe-run-args-no-record (list "autoupdate")))

;;;###autoload
(defun pre-commit-validate-config ()
  "Validate the pre-commit configuration file of the current project.
Signals `user-error' if no configuration file exists."
  (interactive)
  (if-let* ((config (pre-commit--find-config)))
      (pre-commit--maybe-run-args-no-record (list "validate-config" config))
    (user-error "No pre-commit config file found")))

(defun pre-commit--select-hook-description ()
  "Return the description for the hook selection suffix.
Includes the currently selected hook, if any, with a hint that
activating the suffix again clears the selection."
  (if-let* ((h (pre-commit--dispatch-hook)))
      (format "Select hook (%s, select again to clear)" h)
    "Select hook"))

(defun pre-commit--no-hooks-p ()
  "Return non-nil if no pre-commit hooks are available in the current project."
  (null (pre-commit-available-hooks)))

(defun pre-commit--no-file-p ()
  "Return non-nil if the current buffer is not visiting a file."
  (not (pre-commit--file-if-visiting)))

(defun pre-commit--no-last-run-p ()
  "Return non-nil if no previous pre-commit run is recorded for the project."
  (not (when-let* ((root (pre-commit--project-root)))
         (pre-commit--lookup-last-command root))))

(defun pre-commit--no-uncommitted-changes-p ()
  "Return non-nil if the current project has no uncommitted changes."
  (not (when-let* ((root (pre-commit--project-root)))
         (let ((default-directory root))
           (process-lines "git" "status" "--porcelain")))))

(defun pre-commit--disable-file-scope-p ()
  "Return non-nil if the \"Current file\" scope should be disabled."
  (or (pre-commit--no-hooks-p) (pre-commit--no-file-p)))

(defun pre-commit--disable-uncommitted-p ()
  "Return non-nil if the \"Uncommitted changes\" scope should be disabled."
  (or (pre-commit--no-hooks-p) (pre-commit--no-uncommitted-changes-p)))

(defun pre-commit--disable-repeat-p ()
  "Return non-nil if the \"Repeat last\" action should be disabled."
  (or (pre-commit--no-hooks-p) (pre-commit--no-last-run-p)))

(defun pre-commit--no-config-p ()
  "Return non-nil if no pre-commit config file exists in the current project."
  (null (pre-commit--find-config)))

;;;###autoload (autoload 'pre-commit-dispatch "pre-commit")
(transient-define-prefix pre-commit-dispatch ()
  "Dispatch pre-commit commands."
  :man-page "pre-commit"
  :remember-value 'export
  [["Hook"
    ("h" pre-commit-select-hook
     :description pre-commit--select-hook-description
     :transient t
     :inapt-if pre-commit--no-hooks-p)]
   ["Options"
    ("-v" "Verbose" "--verbose")]]
  [["Scope"
    ("u" "Uncommitted changes" pre-commit-dispatch-uncommitted
     :inapt-if pre-commit--disable-uncommitted-p)
    ("a" "All files" pre-commit-dispatch-all
     :inapt-if pre-commit--no-hooks-p)
    ("f" "Current file" pre-commit-dispatch-file
     :inapt-if pre-commit--disable-file-scope-p)]
   ["Actions"
    ("r" "Repeat last" pre-commit-repeat
     :inapt-if pre-commit--disable-repeat-p)]
   ["Maintenance"
    ("U" "Autoupdate" pre-commit-autoupdate
     :inapt-if pre-commit--no-config-p)
    ("v" "Validate config" pre-commit-validate-config
     :inapt-if pre-commit--no-config-p)]])

(defun pre-commit-select-hook ()
  "Select a hook for dispatch.
If a hook is already selected, clear the selection instead, so that
dispatch commands run all hooks again."
  (interactive)
  (if (pre-commit--dispatch-hook)
      (progn
        (setq pre-commit-selected-hook nil)
        (message "Cleared selected hook"))
    (setq pre-commit-selected-hook (pre-commit--select-hook))
    (message "Selected hook: %s" (or pre-commit-selected-hook ""))))

(defun pre-commit--dispatch-hook ()
  "Return the selected hook string, or nil if none/empty."
  (when-let* ((h pre-commit-selected-hook))
    (unless (string= h "") h)))

(defun pre-commit--run-args (hook &rest extra)
  "Return `run' subcommand argument strings for HOOK and EXTRA.
When HOOK is nil, all hooks are run.  EXTRA are appended in order."
  (append (list "run") (when hook (list hook)) extra))

(defun pre-commit-dispatch-uncommitted (&optional extra-args)
  "Run pre-commit for uncommitted changes with selected hook.
EXTRA-ARGS are the arguments of the `pre-commit-dispatch' transient."
  (interactive (list (transient-args 'pre-commit-dispatch)))
  (pre-commit--maybe-run-args
   (pre-commit--run-args (pre-commit--dispatch-hook))
   extra-args))

(defun pre-commit-dispatch-all (&optional extra-args)
  "Run pre-commit for all files with selected hook.
EXTRA-ARGS are the arguments of the `pre-commit-dispatch' transient."
  (interactive (list (transient-args 'pre-commit-dispatch)))
  (pre-commit--maybe-run-args
   (pre-commit--run-args (pre-commit--dispatch-hook) "--all-files")
   extra-args))

(defun pre-commit-dispatch-file (&optional extra-args)
  "Run pre-commit for current file with selected hook.
EXTRA-ARGS are the arguments of the `pre-commit-dispatch' transient."
  (interactive (list (transient-args 'pre-commit-dispatch)))
  (if-let* ((f (pre-commit--file-if-visiting)))
      (pre-commit--maybe-run-args
       (pre-commit--run-args (pre-commit--dispatch-hook) "--files" f)
       extra-args)
    (user-error "Current buffer has no file")))

(provide 'pre-commit)

;;; pre-commit.el ends here

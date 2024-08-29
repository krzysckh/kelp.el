;;; kelp.el --- siple kelp client -*- lexical-binding: t -*-

;; Author: kpm <kpm@linux.pl>
;; Created: 29 Aug 2024
;; Keywords: network, kelp, emacs, lisp
;; URL: https://github.com/krzysckh/kelp.el
;;
;; Copyright (C) 2024 kpm <kpm@linux.pl>
;;
;; Redistribution and use in source and binary forms, with or without
;; modification, are permitted provided that the following conditions are
;; met:
;;
;;     * Redistributions of source code must retain the above copyright
;; notice, this list of conditions and the following disclaimer.
;;     * Redistributions in binary form must reproduce the above
;; copyright notice, this list of conditions and the following disclaimer
;; in the documentation and/or other materials provided with the
;; distribution.
;;
;; THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
;; "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT
;; LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR
;; A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT
;; OWNER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL,
;; SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT
;; LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE,
;; DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY
;; THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
;; (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
;; OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
;;
;; This file is not part of GNU Emacs.

;;; Code:

(require 'request)
(require 'f)
(require 'dash)
(require 'url)

(defvar kelp/db-location "~/.emacs.d/kelp-data.el")
(defvar kelp/instance "https://kelp.krzysckh.org")
(defvar kelp/auth-key nil)
(defvar kelp/load-path "~/.emacs.d/kelp/")

(setq kelp/available-scripts nil)
(setq kelp/prepared nil)

(defun kelp//json-read-l (&rest r)
  (let ((json-array-type 'list))
    (apply #'json-read r)))

(defun kelp/prepare ()
  (when (not kelp/prepared)
    (add-to-list 'load-path kelp/load-path)
    (when (not (file-exists-p kelp/load-path))
      (f-mkdir kelp/load-path))
    (if (file-exists-p kelp/db-location)
        (progn
          (setq kelp/prepared t)
          (setq kelp//installed (read (f-read kelp/db-location))))
      (progn
        (f-write "nil" 'utf-8 kelp/db-location)
        (kelp/prepare)))))

(defun kelp//save-db ()
  (f-write (prin1-to-string kelp//installed) 'utf-8 kelp/db-location))

(defun kelp/install (s &optional version)
  (kelp/prepare)
  (interactive
   (list (ido-completing-read "script-name: " (--map (symbol-name (car it)) kelp/available-scripts)) nil))
  (let* ((s (if (symbolp s) (symbol-name s) s))
         (sym (intern s))
         (version (if (null version) (-max (cdr (assoc sym kelp/available-scripts))) version)))
    (message "installing %s @ %s" s version)
    (request (concat kelp/instance "/api/?get=" (url-encode-url s) "&version=" (url-encode-url (number-to-string version)))
      :complete (cl-function (lambda (&key data &allow-other-keys)
                               (f-write data 'utf-8 (concat kelp/load-path "/" s))
                               (when (assoc sym kelp//installed)
                                 (setq kelp//installed (--filter (not (equal (car it) sym)) kelp//installed)))
                               (setq kelp//installed (append kelp//installed (list (cons sym version))))
                               (kelp//save-db))))))

(defun kelp/update ()
  (interactive)
  (kelp/refresh)
  (dolist (e kelp//installed)
    (let* ((s (car e))
           (v (cdr e))
           (mv (-max (cdr (assoc s kelp/available-scripts)))))
      (when (> mv v)
        (kelp/install s mv))))
  (message "kelp update done"))

(defun kelp/refresh (&optional cb)
  "refresh `kelp/available-scripts', call `cb' with the data if defined."
  (interactive)
  (request (concat kelp/instance "/api/?list")
    :sync t
    :parser #'kelp//json-read-l
    :complete (cl-function (lambda (&key data &allow-other-keys)
                             (setq kelp/available-scripts (--map (cons (car it) (cdr (assoc 'versions it))) data)))))
  (message "kelp refresh done"))

(defun kelp/list-scripts ()
  (interactive)
  (kelp/refresh)
  (let ((buf (get-buffer-create "*kelp-scripts*")))
    (with-current-buffer buf
      (erase-buffer)
      (dolist (v kelp/available-scripts)
        (insert "- ")
        (insert-button
         (symbol-name (car v))
         'face 'link
         'follow-link t
         'action (lambda (_) (kelp/install (car v) nil)))
        (insert "\n")))
    (switch-to-buffer buf)))

(defun kelp/publish-buffer ()
  (interactive)
  (let ((nam (read-string "Script name: " (buffer-name)))
        (description (read-string "Description: ")))
    (when (yes-or-no-p (concat "publish " nam " to " kelp/instance "?"))
      (request (concat kelp/instance "/api/?add")
        :type "POST"
        :data `((name . ,nam) (desc . ,description) (script . ,(buffer-string)) (auth . ,kelp/auth-key))
        :parser #'kelp//json-read-l
        :success (cl-function
                  (lambda (&key data &allow-other-keys)
                    (message "kelp/publish-buffer: %s" data)))))))

(provide 'kelp)

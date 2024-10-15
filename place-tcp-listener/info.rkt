#lang info

(define license 'BSD-3-Clause)
(define collection "net")
(define deps
  '("base"
    "place-tcp-listener-lib"))
(define build-deps
  '("base"
    "net-doc"
    "net-lib"
    "racket-doc"
    "scribble-lib"))
(define implies
  '("place-tcp-listener-lib"))
(define scribblings
  '(("scribblings/place-tcp-listener-manual.scrbl")))

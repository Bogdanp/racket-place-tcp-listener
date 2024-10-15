#lang racket/base

(require actor
         data/monocle
         net/tcp-sig
         net/tcp-unit
         racket/contract/base
         racket/match
         racket/place
         (only-in racket/tcp listen-port-number?)
         racket/unit
         "place-tcp-sig.rkt"
         "place-tcp-unit.rkt")

(define tcp-unit/c
  (unit/c
   (import)
   (export tcp^)))

(define place-tcp-unit/c
  (unit/c
   (import place-tcp^)
   (export tcp^)))

;; make-place-tcp@ ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(provide
 (contract-out
  [make-place-tcp@
   (-> (channel/c (list/c input-port? output-port?)) place-tcp-unit/c)]))

(define (make-place-tcp@ accept-ch)
  (unit
    (import)
    (export tcp^)
    (define-values/invoke-unit place-tcp@
      (import place-tcp^)
      (export tcp^))))


;; place-tcp-listener ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(provide
 (contract-out
  [place-tcp-listen
   (->* [(-> place-channel?)
         listen-port-number?]
        [#:boot-timeout (and/c positive? real?)
         #:parallelism exact-positive-integer?
         #:hostname (or/c #f string?)
         #:backlog exact-nonnegative-integer?
         #:reuse? boolean?
         #:tcp@ tcp-unit/c]
        place-tcp-listener*?)]
  [rename place-tcp-listener*? place-tcp-listener? (-> any/c boolean?)]
  [place-tcp-listener-addresses (-> place-tcp-listener*? (values string? (integer-in 1 65535)))]
  [place-tcp-listener-dead-evt (-> place-tcp-listener*? evt?)]
  [place-tcp-listener-stop (-> place-tcp-listener*? void?)]))

(struct place-tcp-listener* (host port actor))

(define (place-tcp-listener-addresses l)
  (values
   (place-tcp-listener*-host l)
   (place-tcp-listener*-port l)))

(define (place-tcp-listener-dead-evt l)
  (actor-dead-evt (place-tcp-listener*-actor l)))

(define (place-tcp-listener-stop l)
  (define place-listener
    (place-tcp-listener*-actor l))
  (void
   (sync
    (actor-dead-evt place-listener)
    (guard-evt
     (lambda ()
       (stop place-listener)
       (actor-dead-evt place-listener))))))

(struct state (listener current-idx stopped?))
(define-struct-lenses state)

(define-actor (place-tcp-listener
               places
               listener
               tcp-accept
               tcp-abandon-port
               tcp-close)
  #:state (state
           #;listener listener
           #;current-idx 0
           #;stopped? #f)
  #:event
  (lambda (st)
    (apply
     choice-evt
     (handle-evt
      (state-listener st)
      (lambda (_)
        (define idx (state-current-idx st))
        (define-values (in out)
          (tcp-accept (state-listener st)))
        (place-channel-put
         (vector-ref places idx)
         `(accept ,in ,out))
        (tcp-abandon-port out)
        (tcp-abandon-port in)
        (define next-idx
          ((add1 idx) . modulo . (vector-length places)))
        (&state-current-idx st next-idx)))
     (for/list ([ch (in-vector places)])
       (handle-evt
        (place-dead-evt ch)
        (lambda (_)
          (&state-stopped? st #t))))))
  #:stopped? state-stopped?
  #:on-stop
  (lambda (st)
    (tcp-close (state-listener st))
    (for ([place-ch (in-vector places)])
      (place-channel-put place-ch `(stop)))
    (for ([place-ch (in-vector places)])
      (sync (place-dead-evt place-ch))))
  (define (stop st)
    (values (&state-stopped? st #t) (void))))

(define (place-tcp-listen
         start-place port
         #:boot-timeout [boot-timeout 60]
         #:parallelism [parallelism (processor-count)]
         #:hostname [hostname #f]
         #:backlog [backlog (* parallelism 4096)]
         #:reuse? [reuse? #f]
         #:tcp@ [tcp@ tcp@])
  (parameterize-break #f
    (define-values/invoke-unit
      tcp@
      (import)
      (export tcp^))
    (define tcp-listener
      (tcp-listen port backlog reuse? hostname))
    (define-values (places boot-ready-chs)
      (for/lists [_places _boot-ready-chs]
                 ([pid (in-range parallelism)])
        (define place-ch (start-place))
        (define-values (boot-ready-in boot-ready-out)
          (place-channel))
        (place-channel-put place-ch `(init ,parallelism ,pid ,hostname ,port ,boot-ready-out))
        (values place-ch boot-ready-in)))
    (define place-listener
      (place-tcp-listener
       (list->vector places)
       tcp-listener
       tcp-accept
       tcp-abandon-port
       tcp-close))
    (define boot-deadline-evt
      (alarm-evt
       (+ (current-inexact-monotonic-milliseconds)
          (* boot-timeout 1000))
       #t))
    (let loop ([place-chs boot-ready-chs])
      (unless (null? place-chs)
        (apply
         sync/enable-break
         (handle-evt
          boot-deadline-evt
          (lambda (_)
            (error 'place-tpc-listen "boot timeout")))
         (for/list ([place-ch (in-list place-chs)])
           (handle-evt
            place-ch
            (lambda (_)
              (loop (remq place-ch place-chs))))))))
    (define-values (local-host local-port _remote-host _remote-port)
      (tcp-addresses tcp-listener #t))
    (place-tcp-listener* local-host local-port place-listener)))


;; place-tcp-receiver ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(provide
 (contract-out
  [start-place-tcp-receiver
   (-> place-channel?
       (values
        #;p exact-positive-integer?
        #;pid exact-nonnegative-integer?
        #;host (or/c #f string?)
        #;port listen-port-number?
        #;tcp@ tcp-unit/c
        #;evt evt?))]))

(struct receiver-state (stopped?))
(define-struct-lenses receiver-state)

(define (make-receiver-state)
  (receiver-state #f))

(define-actor (place-tcp-receiver place-ch accept-ch ready-ch)
  #:state (make-receiver-state)
  #:event
  (lambda (st)
    (handle-evt
     place-ch
     (match-lambda
       [`(init ,p ,pid ,host ,port ,place-ready-ch)
        (begin0 st
          (place-channel-put place-ready-ch #t)
          (channel-put ready-ch (list p pid host port)))]
       [`(accept ,in ,out)
        (begin0 st
          (channel-put accept-ch (list in out)))]
       [`(stop)
        (&receiver-state-stopped? st #t)])))
  #:stopped? receiver-state-stopped?)

(define (start-place-tcp-receiver place-ch)
  (parameterize-break #f
    (define ready-ch (make-channel))
    (define accept-ch (make-channel))
    (define tcp (make-place-tcp@ accept-ch))
    (define receiver
      (place-tcp-receiver place-ch accept-ch ready-ch))
    (define-values (p pid host port)
      (sync/enable-break
       (handle-evt
        ready-ch
        (lambda (args)
          (apply values args)))))
    (define receiver-dead-evt
      (actor-dead-evt receiver))
    (values p pid host port tcp receiver-dead-evt)))

#lang racket/unit

(require actor
         net/tcp-sig
         (prefix-in tcp: racket/tcp)
         "place-tcp-sig.rkt")

(import place-tcp^)
(export tcp^)

(struct place-tcp-listener (sema ports-ch actor)
  #:property prop:evt
  (lambda (l)
    (handle-evt
     (place-tcp-listener-sema l)
     (lambda (_) l))))

(define-actor (listener sema ports-ch)
  #:state #t ;; running?
  #:event
  (lambda (running?)
    (handle-evt
     accept-ch
     (lambda (ports)
       (begin0 running?
         (semaphore-post sema)
         (channel-put ports-ch ports)))))
  #:stopped? not
  (define (close _running?)
    (values #f (void))))

(define (make-place-tcp-listener)
  (define sema (make-semaphore))
  (define ports-ch (make-channel))
  (place-tcp-listener
   #;sema sema
   #;ports-ch ports-ch
   #;actor (listener sema ports-ch)))

(define (tcp-abandon-port p)
  (tcp:tcp-abandon-port p))

(define (tcp-accept l)
  (apply values (channel-get (place-tcp-listener-ports-ch l))))

(define (tcp-accept/enable-break l)
  (apply values (sync/enable-break (place-tcp-listener-ports-ch l))))

(define (tcp-accept-ready? l)
  (sync/timeout 0 (semaphore-peek-evt (place-tcp-listener-sema l))))

(define (tcp-addresses p [port-numbers? #f])
  (if (tcp:tcp-port? p)
      (tcp:tcp-addresses p port-numbers?)
      (if port-numbers?
          (values "0.0.0.0" 1 "0.0.0.0" 0)
          (values "0.0.0.0" "0.0.0.0"))))

(define (tcp-close l)
  (close (place-tcp-listener-actor l)))

(define (tcp-connect _hostname
                     _port-no
                     [_local-hostname #f]
                     [_local-port-no #f])
  (error 'tcp-connect "not supported"))

(define (tcp-connect/enable-break _hostname
                                  _port-no
                                  [_local-hostname #f]
                                  [_local-port-no #f])
  (error 'tcp-connect/enable-break "not supported"))

(define (tcp-listen _port-no
                    [_backlog 4]
                    [_reuse? #f]
                    [_hostname #f])
  (make-place-tcp-listener))

(define (tcp-listener? l)
  (place-tcp-listener? l))

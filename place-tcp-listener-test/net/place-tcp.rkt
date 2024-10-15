#lang racket/base

(require net/place-tcp
         net/tcp-sig
         racket/place
         racket/tcp
         racket/unit
         rackunit)

(define (start-failing-place)
  (place _ch
    (error 'start-failing-place "failed")))

(define (start-echo-place)
  (place ch
    (define-values (p pid host port tcp@ receiver-dead-evt)
      (start-place-tcp-receiver ch))
    (define-values/invoke-unit
      tcp@
      (import)
      (export tcp^))
    (define listener
      (tcp-listen port 4096 #t host))
    (let loop ()
      (sync
       (handle-evt receiver-dead-evt void)
       (handle-evt
        listener
        (lambda (_)
          (define-values (in out)
            (tcp-accept listener))
          (fprintf out "~a/~a: ~a~n" pid p (read-line in))
          (close-output-port out)
          (close-input-port in)
          (loop)))))))

(define (send+recv port message)
  (define-values (in out)
    (tcp-connect "127.0.0.1" port))
  (write-string message out)
  (close-output-port out)
  (begin0 (read-line in)
    (close-input-port in)))

(define place-tcp-suite
  (test-suite
   "place-tcp"

   (test-case "boot failure"
     (check-exn
      #rx"boot timeout"
      (lambda ()
        (place-tcp-listen
         #:boot-timeout 5
         #:parallelism 2
         start-failing-place 0))))

   (test-case "echo server with p=2"
     (define listener
       (place-tcp-listen
        #:parallelism 2
        start-echo-place 0))
     (define-values (_host port)
       (place-tcp-listener-addresses listener))
     (let ([n 10])
       (check-equal?
        (for/list ([_ (in-range n)])
          (send+recv port "hello"))
        (for/list ([i (in-range n)])
          (format "~a/2: hello" (i . modulo . 2)))))
     (place-tcp-listener-stop listener))))

(module+ test
  (require rackunit/text-ui)
  (run-tests place-tcp-suite))

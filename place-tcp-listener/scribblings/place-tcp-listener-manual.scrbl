#lang scribble/manual

@(require (for-label net/place-tcp
                     net/place-tcp-sig
                     net/place-tcp-unit
                     net/ssl-tcp-unit
                     net/tcp-sig
                     racket/base
                     racket/contract/base
                     racket/place
                     racket/tcp
                     racket/unit))

@title{Place TCP Listener}
@author[(author+email "Bogdan Popa" "bogdan@defn.io")]

@(define post-anchor
   (link
   "https://defn.io/2021/12/30/parallel-racket-web-server/"
    "Parallelizing the Racket Web Server"))

This package provides an implementation of a TCP listener that
accepts connections and dispatches them to @tech[#:doc '(lib
"scribblings/guide/guide.scrbl")]{places}, enabling its users to
parallelize their TCP servers, similar to the implementation described
in @|post-anchor|.

@section{Reference}
@defmodule[net/place-tcp]

@defproc[(place-tcp-listener? [v any/c]) boolean?]{
  Returns @racket[#t] when @racket[v] is a listener returned by
  @racket[place-tcp-listen].
}

@defproc[(place-tcp-listen [start-place (-> place-channel?)]
                           [port listen-port-number?]
                           [#:boot-timeout boot-timeout (and/c positive? real?) 60]
                           [#:parallelism parallelism exact-positive-integer? (processor-count)]
                           [#:hostname hostname (or/c #f string?) #f]
                           [#:backlog backlog exact-nonnegative-integer? (* parallelism 4096)]
                           [#:reuse? reuse? boolean? #f]
                           [#:tcp@ tcp@ (unit/c (import) (export tcp^)) racket/tcp]) place-tcp-listener?]{

  Starts a new TCP listener bound to @racket[port] on the interface(s)
  identified by @racket[hostname]. The listener starts new places by
  applying @racket[start-place]. It then sends the places any new
  connections that it accepts, in round-robin order. The places started
  by @racket[start-place] are expected to implement a specific protocol,
  therefore they must call @racket[start-place-tcp-receiver] on boot and
  pass it the place channel.

  The @racket[#:parallelism] argument controls the number of places
  started by the listener.

  The @racket[#:boot-timeout] argument determines how long the listener
  waits for the places it starts to finish booting. If all the places
  fail to boot within the allotted time, an exception is raised.

  The @racket[#:backlog] and @racket[#:reuse?] arguments have the same
  meaning as the @racket[max-allow-wait] and @racket[reuse?] arguments
  to @racket[tcp-listen], respectively.

  The @racket[#:tcp@] argument can be used to provide a different
  underlying @racket[tcp^] implementation (eg. @racket[make-ssl-tcp@]).

  For example:

  @racketblock[
    (define (start-echo-place)
      (place ch
        (define-values (p pid host port-no tcp@ receiver-dead-evt)
          (start-place-tcp-receiver ch))
        (define-values/invoke-unit
          tcp@
          (import)
          (export tcp^))
        (define listener
          (tcp-listen port-no 4096 #t host))
        (let loop ()
          (sync
           (handle-evt
            receiver-dead-evt
            (lambda (_)
              (tcp-close listener)))
           (handle-evt
            listener
            (lambda (_)
              (define-values (in out)
                (tcp-accept listener))
              (echo in out)
              (loop)))))))
    (code:line)
    (module+ main
      (define listener
        (place-tcp-listen start-echo-place 8000))
      (with-handlers ([exn:break? void])
        (sync/enable-break (place-tcp-listener-dead-evt listener)))
      (place-tcp-listener-stop listener))
  ]
}

@defproc[(place-tcp-listener-addresses [l place-tcp-listener?]) (values string? (integer-in 1 65535))]{
  Returns the address of the interface the listener is listening on and
  the port it's bound to.
}

@defproc[(place-tcp-listener-dead-evt [l place-tcp-listener?]) evt?]{
  Returns a synchronizable event that becomes ready for
  synchronization when the listener has stopped.
}

@defproc[(place-tcp-listener-stop [l place-tcp-listener?]) void?]{
  Stops the place TCP listener @racket[l].
}

@defproc[(start-place-tcp-receiver [place-channel place-channel?])
          (values exact-positive-integer?
                  exact-nonnegative-integer?
                  (or/c #f string?)
                  listen-port-number?
                  (unit/c (import) (export tcp^))
                  evt?)]{

  Starts a background thread that implements the place communication
  protocol expected by @racket[place-tcp-listen] and returns six
  values:

  @itemlist[
    @item{A positive integer, @racket[p], representing the number of receiver places.}
    @item{An integer representing the place's unique id in the range @tt{[0, p)}.}
    @item{The hostname passed to @racket[place-tcp-listen] in the main place.}
    @item{The port number passed to @racket[place-tcp-listen] in the main place.}
    @item{A @racket[tcp^] unit that can be used to accept new
    connections from the main place.}
    @item{An event that becomes ready for synchronization when the main
    place listener has been stopped.}
  ]
}

# SMTPClient

[![Build Status](https://travis-ci.org/aviks/SMTPClient.jl.svg?branch=master)](https://travis-ci.org/aviks/SMTPClient.jl)

[![SMTPClient](http://pkg.julialang.org/badges/SMTPClient_0.6.svg)](http://pkg.julialang.org/?pkg=SMTPClient&ver=0.6)

A [CURL](curl.haxx.se) based SMTP client with fairly low level API.
It is useful for sending emails from within Julia code.
Depends on [LibCURL.jl](https://github.com/JuliaWeb/LibCURL.jl/).

SMTPClient requires Julia 0.6 or higher.

## Installation

```julia
Pkg.add("SMTPClient")
```

The libCurl native library must be available.
It is usually installed with the base system in most Unix variants.

## Usage

```julia
using SMTPClient
opt = SendOptions(blocking = true, isSSL = true,
                  username = "you@gmail.com", passwd = "yourgmailpassword")
#Provide the message body as RFC5322 within an IO
body = IOBuffer("Date: Fri, 18 Oct 2013 21:44:29 +0100\nFrom: You <you@gmail.com>\nTo: me@test.com\nSubject: Julia Test\n\nTest Message")
resp = send("smtps://smtp.gmail.com:465", ["<me@test.com>"], "<you@gmail.com>", body, opt)
```

### Gmail Notes

Due to the security policy of Gmail,
you need to "allow less secure apps into your account":

- https://myaccount.google.com/lesssecureapps

## Function Reference

```julia
send(url, to-addresses, from-address, message-body, options)
```

Send an email.
  * `url` should be of the form `smtp://server:port` or `smtps://...`.
  * `to-address` is a one dimensional array of Strings.
  * `from-address` is a String. All addresses must be enclosed in angle brackets.
  * `message-body` must be a RFC5322 formatted message body provided via an `IO`.
  * `options` is an object of type `SendOptions`. It contains authentication information, as well as the option of whether the server requires TLS.


```julia
SendOptions(; blocking = true, isSSL = false, username = "", passwd = "")
```

Options are passed via the `SendOptions` constructor that takes keyword arguments.
The defaults are shown above.
If the username is blank, the password is not sent even if present.
If `blocking` is set to false, the `send` function is executed
via a `remotecall` to the current node and it will return a `Future` object.

Note that no keepalive is implemented.
New connections to the SMTP server are created for each message.

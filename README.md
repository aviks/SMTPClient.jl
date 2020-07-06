# SMTPClient

[![Build Status](https://travis-ci.org/aviks/SMTPClient.jl.svg?branch=master)](https://travis-ci.org/aviks/SMTPClient.jl)
[![Latest Version](https://juliahub.com/docs/SMTPClient/version.svg)](https://juliahub.com/ui/Packages/SMTPClient/Bx8Fn/)
[![Pkg Eval](https://juliahub.com/docs/SMTPClient/pkgeval.svg)](https://juliahub.com/ui/Packages/SMTPClient/Bx8Fn/)
[![Dependents](https://juliahub.com/docs/SMTPClient/deps.svg)](https://juliahub.com/ui/Packages/SMTPClient/Bx8Fn/?t=2)


A [CURL](curl.haxx.se) based SMTP client with fairly low level API.
It is useful for sending emails from within Julia code.
Depends on [LibCURL.jl](https://github.com/JuliaWeb/LibCURL.jl/).

The latest version of SMTPClient requires Julia 1.3 or higher. Versions of this package may be
available for older Julia versions, but are not fully supported.

## Installation

```julia
Pkg.add("SMTPClient")
```

The LibCURL native library is automatically installed using Julia's artifact system.

## Usage

```julia
using SMTPClient

opt = SendOptions(
  isSSL = true,
  username = "you@gmail.com",
  passwd = "yourgmailpassword")
#Provide the message body as RFC5322 within an IO
body = IOBuffer(
  "Date: Fri, 18 Oct 2013 21:44:29 +0100\r\n" *
  "From: You <you@gmail.com>\r\n" *
  "To: me@test.com\r\n" *
  "Subject: Julia Test\r\n" *
  "\r\n" *
  "Test Message\r\n")
url = "smtps://smtp.gmail.com:465"
rcpt = ["<me@test.com>", "<foo@test.com>"]
from = "<you@gmail.com>"
resp = send(url, rcpt, from, body, opt)
```

- Sending from file `IOStream` is supported:

  ```julia
  body = open("/path/to/mail")
  ```

### Gmail Notes

Due to the security policy of Gmail,
you need to "allow less secure apps into your account":

- https://myaccount.google.com/lesssecureapps

The URL for gmail can be either `smtps://smtp.gmail.com:465` or `smtp://smtp.gmail.com:587`.
(Note the extra `s` in the former.)
Both use SSL, and thus `isSSL` must be set to `true` in `SendOptions`. The latter starts
the connection with plain text, and converts it to secured before sending any data using a
protocol extension called `STARTTLS`. Gmail documentation suggests using this latter setup.

### Troubleshooting

Since this package is a pretty thin wrapper around a low level network protocol, it helps
to know the basics of SMTP while troubleshooting this package. Here is a [quick overview of SMTP](https://utcc.utoronto.ca/usg/technotes/smtp-intro.html). In particular, please pay attention to the difference
between the `envelope headers` and the `message headers`.

If you are having trouble with sending email, set `verbose=true` when creating the `SendOptions` object.
Please always do this before submitting a bugreport to this project.

When sending email over SSL, certificate verification is performed, which requires the presence of a
certificate authority bundle. This package uses the [CA bundle from the Mozilla](https://curl.haxx.se/docs/caextract.html) project. Currently there is no way to specify a private CA bundle. Modify the source if you need this.  

## Function Reference

```julia
send(url, to-addresses, from-address, message-body, options)
```

Send an email.
  * `url` should be of the form `smtp://server:port` or `smtps://...`.
  * `to-address` is a vector of `String`.
  * `from-address` is a `String`. All addresses must be enclosed in angle brackets.
  * `message-body` must be a RFC5322 formatted message body provided via an `IO`.
  * `options` is an object of type `SendOptions`. It contains authentication information, as well as the option of whether the server requires TLS.


```julia
SendOptions(; isSSL = false, verbose = false, username = "", passwd = "")
```

Options are passed via the `SendOptions` constructor that takes keyword arguments.
The defaults are shown above.

- `verbose`: enable `libcurl` verbose mode or not.
- If the `username` is blank, the `passwd` is not sent even if present.

Note that no keepalive is implemented.
New connections to the SMTP server are created for each message.

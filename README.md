# SMTPClient

---

> **2015-10-31**:
> This package is deprecated, and does not have an active maintainer.
> It is not recommended for use in new projects.
> Commit access may be given to anyone interested in taking on reviving,
> maintaining, or furthering development.
> If you are interested, please submit a PR that updates the package.

---

[![Build Status](https://travis-ci.org/JuliaDeprecated/SMTPClient.jl.svg?branch=master)](https://travis-ci.org/JuliaDeprecated/SMTPClient.jl)

[![SMTPClient](http://pkg.julialang.org/badges/SMTPClient_0.3.svg)](http://pkg.julialang.org/?pkg=SMTPClient&ver=0.3)
[![SMTPClient](http://pkg.julialang.org/badges/SMTPClient_0.4.svg)](http://pkg.julialang.org/?pkg=SMTPClient&ver=0.4)

A [CURL](curl.haxx.se) based SMTP client with fairly low level API. It is useful for sending emails from within Julia code. Depends on [LibCURL.jl](https://github.com/JuliaWeb/LibCURL.jl/). 

##Installation

```julia
Pkg.add("SMTPClient")
```
The libCurl native library must be available. It is usually installed with the base system in most unix variants.

##Usage
```julia
using SMTPClient
SMTPClient.init()
o=SendOptions(blocking=true, isSSL=true, username="you@gmail.com", passwd="yourgmailpassword")
#Provide the message body as RFC5322 within an IO 
body=IOBuffer("Date: Fri, 18 Oct 2013 21:44:29 +0100\nFrom: You <you@gmail.com>\nTo: me@test.com\nSubject: Julia Test\n\nTest Message")
resp=send("smtp://smtp.gmail.com:587", ["<me@test.com>"], "<you@gmail.com>", body, o)
SMTPClient.cleanup()
```

##Function Reference

`send(url, to-addresses, from-address, message-body, options)`
    
send an email. 
   * `url` should be of the form `smtp://server:port`. 
   * `to-address` is a one dimensional array of Strings. 
   * `from-address` is a String. All addresses must be enclosed in angle brackets.
   * `message-body` must be a RFC5322 formatted message body provided via an `IO`. 
   * `options` is an object of type `SendOptions`. It contains authentication information, as well as the option of whether the server requires TLS. 



`SendOptions(; blocking=true, isSSL=false,  username="", passwd="" )`

Options are passed via the `SendOptions` constructor that takes keyword arguments. The defaults are shown above. 
If the username is blank, the password is not sent even if present. If `blocking` is set to fall, the `send` function
is executed via a `RemoteCall` to the current node. 

`SMTPClient.init()` and `SMTPClient.cleanup()`

These are global functions that need to be used only once per session. Data created during a single call to `send`
is cleaned up autmatically before the function returns. Also, note that no keepalive is implemented. New connections
to the SMTP server are created for each message. 


<!---
[![Build Status](https://travis-ci.org/aviks/SMTPClient.jl.png)](https://travis-ci.org/aviks/SMTPClient.jl)
-->

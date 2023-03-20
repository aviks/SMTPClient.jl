# SMTPClient

[![Build Status](https://github.com/aviks/SMTPClient.jl/workflows/CI/badge.svg?event=push&branch=master)](https://github.com/aviks/SMTPClient.jl/actions?query=workflow%3ACI)
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

## Raw usage

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

### Example with HTML formatting

```julia
body = "Subject: A simple test\r\n"*
    "Mime-Version: 1.0;\r\n"*
    "Content-Type: text/html;\r\n"*
    "Content-Transfer-Encoding: 7bit;\r\n"*
    "\r\n"*
    """<html>
    <body>
    <h2>An important link to look at!</h2>
    Here's an <a href="https://github.com/aviks/SMTPClient.jl">important link</a>
    </body>
    </html>\r\n"""
```

### Function to construct the IOBuffer body and for adding attachments

A new function `get_body()` is available to facilitate constructing the IOBuffer for the body of the message and for adding attachments.

The function takes four required arguments: the `to` and `from` email addresses, a `subject` string, and a `msg` string. The `to` argument is a vector of strings, containing one or more email addresses. The `msg` string can be a regular string with the contents of the message or a string in MIME format, following the [RFC5322](https://datatracker.ietf.org/doc/html/rfc5322) specifications, and constructed as a plain text, html text or markdown text.

There are also the optional keyword arguments `cc`, `replyto` and `attachments`. The argument `cc` should be a vector of strings, containing one or more email addresses, while `replyto` is a string expected to contain a single argument, just like `from`. The `attachments` argument should be a list of filenames to be attached to the message.

The attachments are encoded using `Base64.base64encode` and included in the IOBuffer variable returned by the function. The function `get_body()` takes care of identifying which type of attachments are to be included (from the filename extensions) and to properly add them according to the MIME specifications.

In case an attachment is to be added, the `msg` argument must be formatted according to the MIME specifications. In order to help with that, another function, `get_mime_msg(message)`, is provided, which takes the provided message and returns the message with the proper MIME specifications. By default, it assumes plain text with UTF-8 encoding, but plain text with different encodings or HTML text or Markdown text can also be given (see [src/user.jl#L36](src/user.jl#L35) for more details on the implementation).

As for blind carbon copy (Bcc), it is implicitly handled by `send()`. Every recipient in `send()` which is not included in `body` is treated as a Bcc.

Here are a few examples:

#### Message with several types of recipients

```julia
using SMTPClient

opt = SendOptions(
  isSSL = true,
  username = "you@gmail.com",
  passwd = "yourgmailpassword"
)

url = "smtps://smtp.gmail.com:465"

subject = "SMPTClient.jl"
message = "Don't forget to check out SMTPClient.jl"

to = ["<foo@test.com>"]
cc = ["<bar@test.com>"]
bcc = ["<baz@test.com>"]
from = "You <you@test.com>"
replyto = "<you@gmail.com>"

body = get_body(to, from, subject, message; cc, replyto)

rcpt = vcat(to, cc, bcc)
resp = send(url, rcpt, from, body, opt)
```

#### Message with attachment

```julia
subject = "Julia logo"
message = "Check out this cool logo!"
attachments = ["julia_logo_color.png"]

mime_msg = get_mime_msg(message)

body = get_body(to, from, subject, mime_msg; attachments)
```

#### HTML message

Note that, by using `get_mime_msg()` with an `HTML{String}` message, the tags `<html>` and `<body>` should not be added.

```julia
subject = "A simple HTML test"
message = 
    html"""<h2>An important link to look at!</h2>
    Here's an <a href="https://github.com/aviks/SMTPClient.jl">important link</a>
    """

mime_msg = get_mime_msg(message)

body = get_body(to, from, subject, mime_msg)
resp = send(server, rcpts, sender, body, opts)
```

#### Markdown message

```julia
using Markdown
subject = "The Julia Programming Language"
message = 
    Markdown.parse(
        """# The Julia Programming Language

        ## Julia in a Nutshell

        1. **Fast** - Julia was designed from the beginning for [high performance](https://docs.julialang.org/en/v1/manual/types/).
        1. **Dynamic** - Julia is [dynamically typed](https://docs.julialang.org/en/v1/manual/types/).
        1. **Reproducible** - recreate the same [Julia environment](https://julialang.github.io/Pkg.jl/v1/environments/) every time.
        1. **Composable** - Julia uses [multiple dispatch](https://docs.julialang.org/en/v1/manual/methods/) as a paradigm.
        1. **General** - One can build entire [Applications and Microservices](https://www.youtube.com/watch?v=uLhXgt_gKJc) in Julia.
        1. **Open source** - Available under the [MIT license](https://github.com/JuliaLang/julia/blob/master/LICENSE.md), with the [source code](https://github.com/JuliaLang/julia) on GitHub.

        It has *over 5,000* [Julia packages](https://juliahub.com/ui/Packages) and a *variety* of advanced ecosystems. Check out more on [the Julia Programing Language website](https://julialang.org).
        """
    )

mime_msg = get_mime_msg(message)

body = get_body(to, from, subject, mime_msg; cc, replyto)
resp = send(server, rcpts, sender, body, opts)
```

#### Previewing the generated message

You can preview your message by displaying the generated `body`, which is an `IOBuffer`.

For instance, you can view the raw message with `println(String(take!(body)))`.

You can also save the message `body` to a `.eml` file for viewing it in a email viewer.

```julia
open("message.eml","w") do io
    println(io, String(take!(body)))
end
```

The last example on the previous section shows the following preview on Apple Mail:

![Message on the Julia Programming Language](img/message.png)

### Gmail Notes

Due to the security policy of Gmail,
you need to "allow less secure apps into your account":

- <https://myaccount.google.com/lesssecureapps>

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

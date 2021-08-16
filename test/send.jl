function test_content(f::Base.Callable, fname)
  try
    open(fname) do io
      f(read(io, String))
    end
  finally
    rm(fname, force = true)
  end
end


@testset "Send" begin
  logfile = tempname()
  server = "smtp://127.0.0.1:1025"
  addr = "<julian@julialang.org>"
  mock = joinpath(dirname(@__FILE__), "mock.py")

  cmd = `python3.7 $mock $logfile`
  smtpsink = run(pipeline(cmd, stderr=stdout), wait = false)
  sleep(.5)  # wait for fake smtp server ready

  try
    let  # send with body::IOBuffer
      body = IOBuffer("body::IOBuffer test")
      send(server, [addr], addr, body)
      test_content(logfile) do s
        @test occursin("body::IOBuffer test", s)
      end
    end

    let  # send with body::IOStream
      mktemp() do path, io
        write(io, "body::IOStream test")
        seekstart(io)

        send(server, [addr], addr, io)
        test_content(logfile) do s
          @test occursin("body::IOStream test", s)
        end
      end
    end

    let  # AUTH PLAIN
      opts = SendOptions(username = "foo@example.org", passwd = "bar")
      body = IOBuffer("AUTH PLAIN test")
      send(server, [addr], addr, body, opts)
      test_content(logfile) do s
        @test occursin("AUTH PLAIN test", s)
      end
    end

    let
      opts = SendOptions(username = "foo@example.org", passwd = "invalid")
      body = IOBuffer("invalid password")
      @test_throws Exception send(server, [addr], addr, body, opts)
    end

    let  # multiple RCPT TO
      body = IOBuffer("multiple rcpt")
      rcpts = ["<foo@example.org>", "<bar@example.org>", "<baz@example.org>"]
      send(server, rcpts, addr, body)

      test_content(logfile) do s
        @test occursin("multiple rcpt", s)
        @test occursin("X-RCPT: foo@example.org", s)
        @test occursin("X-RCPT: bar@example.org", s)
        @test occursin("X-RCPT: baz@example.org", s)
      end
    end

    let  # non-blocking send
      body = IOBuffer("non-blocking send")
      task = @async send(server, [addr], addr, body)
      wait(task)
      test_content(logfile) do s
        @test occursin("non-blocking send", s)
      end
    end

    let  # SendOptions.verbose no error
      opts = SendOptions(verbose = true, username = "foo@example.org", passwd = "bar")
      body = IOBuffer("SendOptions.verbose")
      send(server, [addr], addr, body, opts)
      test_content(logfile) do s
        @test occursin("SendOptions.verbose", s)
      end
    end

    let  # send using get_body
      mktemp() do path, io
        mime_message = get_message("body mime message", Val(:usascii))
        body = get_body([addr], addr, "test message", mime_message)

        write(io, body)
        seekstart(io)
  
        send(server, [addr], addr, io)
        test_content(logfile) do s
          @test occursin("From: $addr", s)
          @test occursin("To: $addr", s)
          @test occursin("Subject: test message", s)
          @test occursin("body mime message", s)
        end
      end
    end

    let  # send using get_body with UTF-8 encoded message
      mktemp() do path, io
        message = 
          "ABCDEFGHIJKLMNOPQRSTUVWXYZ /0123456789\r\n" *
          "abcdefghijklmnopqrstuvwxyz £©µÀÆÖÞßéöÿ\r\n" *
          "–—‘“”„†•…‰™œŠŸž€ ΑΒΓΔΩαβγδω АБВГДабвгд\r\n" *
          "∀∂∈ℝ∧∪≡∞ ↑↗↨↻⇣ ┐┼╔╘░►☺♀ ﬁ�⑀₂ἠḂӥẄɐː⍎אԱა\r\n"

        mime_message = get_message(message, Val(:utf8))
        body = get_body([addr], addr, "test message", mime_message)
  
        write(io, body)
        seekstart(io)
    
        send(server, [addr], addr, io)
        test_content(logfile) do s
          @test occursin("From: $addr", s)
          @test occursin("To: $addr", s)
          @test occursin("Subject: test message", s)
          @test occursin("ABCDEFGHIJKLMNOPQRSTUVWXYZ /0123456789", s)
          @test occursin("abcdefghijklmnopqrstuvwxyz £©µÀÆÖÞßéöÿ", s)
          @test occursin("–—‘“”„†•…‰™œŠŸž€ ΑΒΓΔΩαβγδω АБВГДабвгд", s)
          @test occursin("∀∂∈ℝ∧∪≡∞ ↑↗↨↻⇣ ┐┼╔╘░►☺♀ ﬁ�⑀₂ἠḂӥẄɐː⍎אԱა", s)
        end
      end
    end

    let  # send using get_body with extra fields
      mktemp() do path, io
        rcpt = [addr]
        subject = "test message with extra fields"
        mime_message = get_message("body mime message with extra fields", Val(:utf8))
        from = addr
        to = ["<foo@example.org>", "<bar@example.org>"]
        cc = ["<baz@example.org>", "<qux@example.org>"]
        replyto = addr
        body = get_body(to, from, subject, mime_message; cc = cc, replyto = replyto)
  
        write(io, body)
        seekstart(io)
    
        send(server, [addr], addr, io)
        test_content(logfile) do s
          @test occursin("From: $addr", s)
          @test occursin("Subject: $subject", s)
          @test occursin("Cc: <baz@example.org>, <qux@example.org>", s)
          @test occursin("Reply-To: $addr", s)
          @test occursin("To: <foo@example.org>, <bar@example.org>", s) 
          @test occursin("body mime message with extra fields", s)
        end
      end
    end

    let  # send with attachment
      mktemp() do path, io
        mime_message = get_message("body mime message with attachment", Val(:utf8))
        body = get_body([addr], addr, "test message with attachment", mime_message)
  
        write(io, body)
        seekstart(io)
    
        send(server, [addr], addr, io)
        test_content(logfile) do s
            @test occursin("To: $addr", s)
            @test occursin("Subject: test message with attachment", s)
            @test occursin("body mime message with attachment", s)
        end
      end
    end

  finally
    kill(smtpsink)
    rm(logfile, force = true)
  end
end  # @testset "Send"

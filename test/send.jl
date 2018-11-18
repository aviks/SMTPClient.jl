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

  finally
    kill(smtpsink)
    rm(logfile, force = true)
  end
end  # @testset "Send"

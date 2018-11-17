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
      opts = SendOptions(blocking = true)
      body = IOBuffer("body::IOBuffer test")
      send(server, [addr], addr, body, opts)
      test_content(logfile) do s
        @test occursin("body::IOBuffer test", s)
      end
    end

    let  # AUTH PLAIN
      opts = SendOptions(blocking = true,
                         username = "foo@example.org", passwd = "bar")
      body = IOBuffer("AUTH PLAIN test")
      send(server, [addr], addr, body, opts)
      test_content(logfile) do s
        @test occursin("AUTH PLAIN test", s)
      end
    end

    let
      opts = SendOptions(blocking = true,
                         username = "foo@example.org", passwd = "invalid")
      body = IOBuffer("invalid password")
      @test_throws Exception send(server, [addr], addr, body, opts)
    end

    let  # multiple RCPT TO
      opts = SendOptions(blocking = true)
      body = IOBuffer("multiple rcpt")
      rcpts = ["<foo@example.org>", "<bar@example.org>", "<baz@example.org>"]
      send(server, rcpts, addr, body, opts)

      test_content(logfile) do s
        @test occursin("multiple rcpt", s)
        @test occursin("X-RCPT: foo@example.org", s)
        @test occursin("X-RCPT: bar@example.org", s)
        @test occursin("X-RCPT: baz@example.org", s)
      end
    end

  finally
    kill(smtpsink)
    rm(logfile, force = true)
  end
end  # @testset "Send"

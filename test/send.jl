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
  server = "smtp://0.0.0.0:1025"
  addr = "<julian@julialang.org>"
  mock = joinpath(dirname(@__FILE__), "mock.py")

  cmd = `python3 $mock $logfile`
  smtpsink = run(cmd, wait = false)
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

    let
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

  finally
    kill(smtpsink)
    rm(logfile, force = true)
  end
end  # @testset "Send"

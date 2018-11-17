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
  server = "smtp://localhost:1025"
  addr = "<julian@julialang.org>"

  cmd = `smtp-sink -v -D $logfile localhost:1025 10`
  smtpsink = run(cmd, wait = false)
  sleep(.5)  # wait for smtp-sink ready

  try
    let  # send with body::IOBuffer
      opts = SendOptions(blocking = true)
      body = IOBuffer("body::IOBuffer test")
      resp = send(server, [addr], addr, body, opts)
      test_content(logfile) do s
        @test occursin("body::IOBuffer test", s)
      end
    end

  finally
    kill(smtpsink)
    rm(logfile, force = true)
  end
end  # @testset "Send"

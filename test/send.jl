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
      message = "body mime message"
      subject = "test message"

      mime_message = get_mime_msg(message, Val(:usascii))
      body = get_body([addr], addr, subject, mime_message)
  
      send(server, [addr], addr, body)

      test_content(logfile) do s
        @test occursin("From: $addr", s)
        @test occursin("To: $addr", s)
        @test occursin("Subject: $subject", s)
        @test occursin(message, s)
      end
    end

    let  # send using get_body with UTF-8 encoded message
      message = 
        "ABCDEFGHIJKLMNOPQRSTUVWXYZ /0123456789\r\n" *
        "abcdefghijklmnopqrstuvwxyz £©µÀÆÖÞßéöÿ\r\n" *
        "–—‘“”„†•…‰™œŠŸž€ ΑΒΓΔΩαβγδω АБВГДабвгд\r\n" *
        "∀∂∈ℝ∧∪≡∞ ↑↗↨↻⇣ ┐┼╔╘░►☺♀ ﬁ�⑀₂ἠḂӥẄɐː⍎אԱა\r\n"
      subject = "test message in UTF-8"

      mime_message = get_mime_msg(message, Val(:utf8))
      body = get_body([addr], addr, subject, mime_message)
    
      send(server, [addr], addr, body)

      test_content(logfile) do s
        @test occursin("From: $addr", s)
        @test occursin("To: $addr", s)
        @test occursin("Subject: $subject", s)
        @test occursin("ABCDEFGHIJKLMNOPQRSTUVWXYZ /0123456789", s)
        @test occursin("abcdefghijklmnopqrstuvwxyz £©µÀÆÖÞßéöÿ", s)
        @test occursin("–—‘“”„†•…‰™œŠŸž€ ΑΒΓΔΩαβγδω АБВГДабвгд", s)
        @test occursin("∀∂∈ℝ∧∪≡∞ ↑↗↨↻⇣ ┐┼╔╘░►☺♀ ﬁ�⑀₂ἠḂӥẄɐː⍎אԱა", s)
      end
    end

    let  # send using get_body with HTML string encoded message
      message = HTML(
        """<h2>An important link to look at!</h2>
        Here's an <a href="https://github.com/aviks/SMTPClient.jl">important link</a>\r\n"""
      )

      subject = "test message in HTML"
  
      mime_message = get_mime_msg(message)
      body = get_body([addr], addr, subject, mime_message)
      
      send(server, [addr], addr, body)
  
      test_content(logfile) do s
        @test occursin("From: $addr", s)
        @test occursin("To: $addr", s)
        @test occursin("Subject: $subject", s)
        @test occursin("Content-Type: text/html;", s)
        @test occursin("Content-Transfer-Encoding: 7bit;", s)
        @test occursin("<html>", s)
        @test occursin("<body>", s)
        @test occursin("<h2>An important link to look at!</h2>", s)
        @test occursin(
            "<a href=\"https://github.com/aviks/SMTPClient.jl\">important link</a>",
            s
        )
        @test occursin("</body>", s)
        @test occursin("</html>", s)
      end
    end

    let  # send using get_body with HTML string encoded message
      message = md"""# An important link to look at!
      
      Here's an [important link](https://github.com/aviks/SMTPClient.jl)"""
  
      subject = "test message in Markdown"
    
      mime_message = get_mime_msg(message)
      body = get_body([addr], addr, subject, mime_message)
        
      send(server, [addr], addr, body)
    
      test_content(logfile) do s
        @test occursin("From: $addr", s)
        @test occursin("To: $addr", s)
        @test occursin("Subject: $subject", s)
        @test occursin("Content-Type: text/html;", s)
        @test occursin("Content-Transfer-Encoding: 7bit;", s)
        @test occursin("<html>", s)
        @test occursin("<body>", s)
        @test occursin("<h1>An important link to look at&#33;</h1>", s)
        @test occursin(
            "<a href=\"https://github.com/aviks/SMTPClient.jl\">important link</a>",
            s
        )
        @test occursin("</body>", s)
        @test occursin("</html>", s)
      end
    end

    let  # send using get_body with extra fields
        message = "body mime message with extra fields"
        subject = "test message with extra fields"

        mime_message = get_mime_msg(message)
        from = addr
        to = ["<foo@example.org>", "<bar@example.org>"]
        cc = ["<baz@example.org>", "<qux@example.org>"]
        bcc = ["<quux@example.org>"]
        replyto = addr
        body = get_body(to, from, subject, mime_message;
            cc = cc, replyto = replyto)
        rcpts = vcat(to, cc, bcc)
    
        send(server, rcpts, addr, body)

        test_content(logfile) do s
          @test occursin("From: $addr", s)
          @test occursin("Subject: $subject", s)
          @test occursin("Cc: <baz@example.org>, <qux@example.org>", s)
          @test occursin("Reply-To: $addr", s)
          @test occursin("To: <foo@example.org>, <bar@example.org>", s)
          @test occursin(message, s)
          @test occursin("X-RCPT: foo@example.org", s)
          @test occursin("X-RCPT: bar@example.org", s)
          @test occursin("X-RCPT: baz@example.org", s)
          @test occursin("X-RCPT: qux@example.org", s)
          @test occursin("X-RCPT: quux@example.org", s)
      end
    end

    let  # send with attachment
      message = "body mime message with attachment"
      subject = "test message with attachment"
      svg_str = """<?xml version="1.0" encoding="UTF-8"?>
        <svg xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink" width="320pt" height="200pt" viewBox="0 0 320 200" version="1.1">
        <g id="surface61">
        <path style=" stroke:none;fill-rule:nonzero;fill:rgb(0%,0%,0%);fill-opacity:1;" d="M 67.871094 164.3125 C 67.871094 171.847656 67.023438 177.933594 65.328125 182.566406 C 63.632812 187.203125 61.222656 190.800781 58.09375 193.363281 C 54.96875 195.925781 51.21875 197.640625 46.847656 198.507812 C 42.476562 199.371094 37.613281 199.804688 32.265625 199.804688 C 25.027344 199.804688 19.488281 198.675781 15.648438 196.414062 C 11.804688 194.152344 9.882812 191.441406 9.882812 188.273438 C 9.882812 185.636719 10.953125 183.414062 13.101562 181.605469 C 15.25 179.796875 18.132812 178.894531 21.75 178.894531 C 24.464844 178.894531 26.632812 179.628906 28.25 181.097656 C 29.871094 182.566406 31.210938 184.019531 32.265625 185.449219 C 33.46875 187.03125 34.488281 188.085938 35.316406 188.613281 C 36.144531 189.140625 36.898438 189.40625 37.578125 189.40625 C 39.007812 189.40625 40.101562 188.558594 40.855469 186.863281 C 41.609375 185.167969 41.984375 181.871094 41.984375 176.972656 L 41.984375 84.050781 L 67.871094 76.929688 L 67.871094 164.3125 M 104.738281 79.414062 L 104.738281 139.214844 C 104.738281 140.875 105.058594 142.4375 105.699219 143.90625 C 106.339844 145.375 107.226562 146.640625 108.355469 147.695312 C 109.488281 148.75 110.804688 149.597656 112.3125 150.238281 C 113.820312 150.878906 115.441406 151.199219 117.175781 151.199219 C 119.132812 151.199219 121.359375 150.101562 124.070312 148.203125 C 128.363281 145.195312 130.964844 143.128906 130.964844 140.683594 C 130.964844 140.097656 130.964844 79.414062 130.964844 79.414062 L 156.738281 79.414062 L 156.738281 164.3125 L 130.964844 164.3125 L 130.964844 156.398438 C 127.574219 159.261719 123.957031 161.558594 120.113281 163.292969 C 116.269531 165.027344 112.539062 165.894531 108.921875 165.894531 C 104.703125 165.894531 100.78125 165.195312 97.164062 163.800781 C 93.546875 162.40625 90.382812 160.503906 87.671875 158.09375 C 84.957031 155.683594 82.828125 152.855469 81.28125 149.613281 C 79.738281 146.375 78.964844 142.90625 78.964844 139.214844 L 78.964844 79.414062 L 104.738281 79.414062 M 192.882812 164.3125 L 167.222656 164.3125 L 167.222656 45.277344 L 192.882812 38.15625 L 192.882812 164.3125 M 203.601562 84.050781 L 229.375 76.929688 L 229.375 164.3125 L 203.601562 164.3125 L 203.601562 84.050781 M 283.226562 120.449219 C 280.738281 121.507812 278.230469 122.730469 275.707031 124.125 C 273.183594 125.519531 270.882812 127.046875 268.8125 128.703125 C 266.738281 130.359375 265.0625 132.132812 263.78125 134.015625 C 262.5 135.898438 261.859375 137.859375 261.859375 139.894531 C 261.859375 141.476562 262.066406 143.003906 262.480469 144.472656 C 262.894531 145.941406 263.480469 147.203125 264.234375 148.257812 C 264.988281 149.3125 265.816406 150.160156 266.722656 150.800781 C 267.625 151.441406 268.605469 151.761719 269.660156 151.761719 C 271.769531 151.761719 273.898438 151.121094 276.046875 149.839844 C 278.195312 148.558594 280.585938 146.941406 283.226562 144.980469 L 283.226562 120.449219 M 309.109375 164.3125 L 283.226562 164.3125 L 283.226562 157.527344 C 281.792969 158.734375 280.398438 159.847656 279.042969 160.863281 C 277.6875 161.878906 276.160156 162.765625 274.464844 163.519531 C 272.769531 164.273438 270.867188 164.855469 268.753906 165.273438 C 266.644531 165.6875 264.15625 165.894531 261.296875 165.894531 C 257.375 165.894531 253.851562 165.328125 250.726562 164.199219 C 247.597656 163.066406 244.941406 161.523438 242.757812 159.5625 C 240.570312 157.605469 238.894531 155.285156 237.726562 152.609375 C 236.558594 149.9375 235.972656 147.015625 235.972656 143.851562 C 235.972656 140.609375 236.59375 137.671875 237.839844 135.03125 C 239.082031 132.394531 240.777344 130.023438 242.925781 127.910156 C 245.074219 125.800781 247.578125 123.917969 250.441406 122.257812 C 253.304688 120.601562 256.378906 119.074219 259.65625 117.679688 C 262.933594 116.285156 266.34375 115.007812 269.886719 113.839844 C 273.425781 112.671875 276.933594 111.558594 280.398438 110.503906 L 283.226562 109.824219 L 283.226562 101.460938 C 283.226562 96.035156 282.1875 92.191406 280.117188 89.929688 C 278.042969 87.667969 275.273438 86.539062 271.808594 86.539062 C 267.738281 86.539062 264.910156 87.519531 263.328125 89.476562 C 261.746094 91.4375 260.953125 93.808594 260.953125 96.597656 C 260.953125 98.179688 260.785156 99.726562 260.445312 101.234375 C 260.109375 102.742188 259.523438 104.058594 258.695312 105.191406 C 257.867188 106.320312 256.679688 107.226562 255.132812 107.902344 C 253.589844 108.582031 251.648438 108.921875 249.3125 108.921875 C 245.695312 108.921875 242.757812 107.882812 240.496094 105.8125 C 238.234375 103.738281 237.105469 101.121094 237.105469 97.953125 C 237.105469 95.015625 238.101562 92.285156 240.097656 89.761719 C 242.097656 87.234375 244.789062 85.066406 248.183594 83.261719 C 251.574219 81.449219 255.492188 80.019531 259.9375 78.964844 C 264.382812 77.910156 269.09375 77.382812 274.066406 77.382812 C 280.171875 77.382812 285.429688 77.929688 289.839844 79.019531 C 294.246094 80.113281 297.882812 81.675781 300.746094 83.710938 C 303.609375 85.746094 305.71875 88.195312 307.074219 91.058594 C 308.433594 93.921875 309.109375 97.128906 309.109375 100.667969 L 309.109375 164.3125 "/>
        <path style=" stroke:none;fill-rule:nonzero;fill:rgb(79.6%,23.5%,20%);fill-opacity:1;" d="M 235.273438 55.089844 C 235.273438 64.757812 227.4375 72.589844 217.773438 72.589844 C 208.105469 72.589844 200.273438 64.757812 200.273438 55.089844 C 200.273438 45.425781 208.105469 37.589844 217.773438 37.589844 C 227.4375 37.589844 235.273438 45.425781 235.273438 55.089844 "/>
        <path style=" stroke:none;fill-rule:nonzero;fill:rgb(25.1%,38.8%,84.7%);fill-opacity:1;" d="M 72.953125 55.089844 C 72.953125 64.757812 65.117188 72.589844 55.453125 72.589844 C 45.789062 72.589844 37.953125 64.757812 37.953125 55.089844 C 37.953125 45.425781 45.789062 37.589844 55.453125 37.589844 C 65.117188 37.589844 72.953125 45.425781 72.953125 55.089844 "/>
        <path style=" stroke:none;fill-rule:nonzero;fill:rgb(58.4%,34.5%,69.8%);fill-opacity:1;" d="M 277.320312 55.089844 C 277.320312 64.757812 269.484375 72.589844 259.820312 72.589844 C 250.15625 72.589844 242.320312 64.757812 242.320312 55.089844 C 242.320312 45.425781 250.15625 37.589844 259.820312 37.589844 C 269.484375 37.589844 277.320312 45.425781 277.320312 55.089844 "/>
        <path style=" stroke:none;fill-rule:nonzero;fill:rgb(22%,59.6%,14.9%);fill-opacity:1;" d="M 256.300781 18.671875 C 256.300781 28.335938 248.464844 36.171875 238.800781 36.171875 C 229.132812 36.171875 221.300781 28.335938 221.300781 18.671875 C 221.300781 9.007812 229.132812 1.171875 238.800781 1.171875 C 248.464844 1.171875 256.300781 9.007812 256.300781 18.671875 "/>
        </g>
        </svg>
      """
      filename = joinpath(tempdir(), "julia_logo_color.svg")
      open(filename, "w") do f
        write(f, svg_str)
      end
      readme = open(f->read(f, String), joinpath("..", "README.md"))

      mime_message = get_mime_msg(message, Val(:utf8))
      attachments = [joinpath("..", "README.md"), filename]
      body = get_body([addr], addr, subject, mime_message, attachments = attachments)
    
      send(server, [addr], addr, body)

      test_content(logfile) do s
        m = match(r"Content-Type:\s*multipart\/mixed;\s*boundary=\"(.+)\"\n", s)
        @test m !== nothing
        boundary = m.captures[1]
        @test occursin("To: $addr", s)
        @test occursin("Subject: $subject", s)
        @test occursin(message, s)
        splt = split(s)
        ind = findall(v -> occursin("--$boundary", v), splt)
        @test length(ind) == 6
        @test String(base64decode(splt[ind[4]-1])) == readme
        @test String(base64decode(splt[ind[6]-1])) == svg_str
      end
      rm(filename)
    end

    let  # send with attachment and markdown message
        message = md"""# An important link to look at!
      
        Here's an [important link](https://github.com/aviks/SMTPClient.jl)
        
        And don't forget to check out the attached *cool* **julia** logo."""

        subject = "test message with attachment"
        svg_str = """<?xml version="1.0" encoding="UTF-8"?>
          <svg xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink" width="320pt" height="200pt" viewBox="0 0 320 200" version="1.1">
          <g id="surface61">
          <path style=" stroke:none;fill-rule:nonzero;fill:rgb(0%,0%,0%);fill-opacity:1;" d="M 67.871094 164.3125 C 67.871094 171.847656 67.023438 177.933594 65.328125 182.566406 C 63.632812 187.203125 61.222656 190.800781 58.09375 193.363281 C 54.96875 195.925781 51.21875 197.640625 46.847656 198.507812 C 42.476562 199.371094 37.613281 199.804688 32.265625 199.804688 C 25.027344 199.804688 19.488281 198.675781 15.648438 196.414062 C 11.804688 194.152344 9.882812 191.441406 9.882812 188.273438 C 9.882812 185.636719 10.953125 183.414062 13.101562 181.605469 C 15.25 179.796875 18.132812 178.894531 21.75 178.894531 C 24.464844 178.894531 26.632812 179.628906 28.25 181.097656 C 29.871094 182.566406 31.210938 184.019531 32.265625 185.449219 C 33.46875 187.03125 34.488281 188.085938 35.316406 188.613281 C 36.144531 189.140625 36.898438 189.40625 37.578125 189.40625 C 39.007812 189.40625 40.101562 188.558594 40.855469 186.863281 C 41.609375 185.167969 41.984375 181.871094 41.984375 176.972656 L 41.984375 84.050781 L 67.871094 76.929688 L 67.871094 164.3125 M 104.738281 79.414062 L 104.738281 139.214844 C 104.738281 140.875 105.058594 142.4375 105.699219 143.90625 C 106.339844 145.375 107.226562 146.640625 108.355469 147.695312 C 109.488281 148.75 110.804688 149.597656 112.3125 150.238281 C 113.820312 150.878906 115.441406 151.199219 117.175781 151.199219 C 119.132812 151.199219 121.359375 150.101562 124.070312 148.203125 C 128.363281 145.195312 130.964844 143.128906 130.964844 140.683594 C 130.964844 140.097656 130.964844 79.414062 130.964844 79.414062 L 156.738281 79.414062 L 156.738281 164.3125 L 130.964844 164.3125 L 130.964844 156.398438 C 127.574219 159.261719 123.957031 161.558594 120.113281 163.292969 C 116.269531 165.027344 112.539062 165.894531 108.921875 165.894531 C 104.703125 165.894531 100.78125 165.195312 97.164062 163.800781 C 93.546875 162.40625 90.382812 160.503906 87.671875 158.09375 C 84.957031 155.683594 82.828125 152.855469 81.28125 149.613281 C 79.738281 146.375 78.964844 142.90625 78.964844 139.214844 L 78.964844 79.414062 L 104.738281 79.414062 M 192.882812 164.3125 L 167.222656 164.3125 L 167.222656 45.277344 L 192.882812 38.15625 L 192.882812 164.3125 M 203.601562 84.050781 L 229.375 76.929688 L 229.375 164.3125 L 203.601562 164.3125 L 203.601562 84.050781 M 283.226562 120.449219 C 280.738281 121.507812 278.230469 122.730469 275.707031 124.125 C 273.183594 125.519531 270.882812 127.046875 268.8125 128.703125 C 266.738281 130.359375 265.0625 132.132812 263.78125 134.015625 C 262.5 135.898438 261.859375 137.859375 261.859375 139.894531 C 261.859375 141.476562 262.066406 143.003906 262.480469 144.472656 C 262.894531 145.941406 263.480469 147.203125 264.234375 148.257812 C 264.988281 149.3125 265.816406 150.160156 266.722656 150.800781 C 267.625 151.441406 268.605469 151.761719 269.660156 151.761719 C 271.769531 151.761719 273.898438 151.121094 276.046875 149.839844 C 278.195312 148.558594 280.585938 146.941406 283.226562 144.980469 L 283.226562 120.449219 M 309.109375 164.3125 L 283.226562 164.3125 L 283.226562 157.527344 C 281.792969 158.734375 280.398438 159.847656 279.042969 160.863281 C 277.6875 161.878906 276.160156 162.765625 274.464844 163.519531 C 272.769531 164.273438 270.867188 164.855469 268.753906 165.273438 C 266.644531 165.6875 264.15625 165.894531 261.296875 165.894531 C 257.375 165.894531 253.851562 165.328125 250.726562 164.199219 C 247.597656 163.066406 244.941406 161.523438 242.757812 159.5625 C 240.570312 157.605469 238.894531 155.285156 237.726562 152.609375 C 236.558594 149.9375 235.972656 147.015625 235.972656 143.851562 C 235.972656 140.609375 236.59375 137.671875 237.839844 135.03125 C 239.082031 132.394531 240.777344 130.023438 242.925781 127.910156 C 245.074219 125.800781 247.578125 123.917969 250.441406 122.257812 C 253.304688 120.601562 256.378906 119.074219 259.65625 117.679688 C 262.933594 116.285156 266.34375 115.007812 269.886719 113.839844 C 273.425781 112.671875 276.933594 111.558594 280.398438 110.503906 L 283.226562 109.824219 L 283.226562 101.460938 C 283.226562 96.035156 282.1875 92.191406 280.117188 89.929688 C 278.042969 87.667969 275.273438 86.539062 271.808594 86.539062 C 267.738281 86.539062 264.910156 87.519531 263.328125 89.476562 C 261.746094 91.4375 260.953125 93.808594 260.953125 96.597656 C 260.953125 98.179688 260.785156 99.726562 260.445312 101.234375 C 260.109375 102.742188 259.523438 104.058594 258.695312 105.191406 C 257.867188 106.320312 256.679688 107.226562 255.132812 107.902344 C 253.589844 108.582031 251.648438 108.921875 249.3125 108.921875 C 245.695312 108.921875 242.757812 107.882812 240.496094 105.8125 C 238.234375 103.738281 237.105469 101.121094 237.105469 97.953125 C 237.105469 95.015625 238.101562 92.285156 240.097656 89.761719 C 242.097656 87.234375 244.789062 85.066406 248.183594 83.261719 C 251.574219 81.449219 255.492188 80.019531 259.9375 78.964844 C 264.382812 77.910156 269.09375 77.382812 274.066406 77.382812 C 280.171875 77.382812 285.429688 77.929688 289.839844 79.019531 C 294.246094 80.113281 297.882812 81.675781 300.746094 83.710938 C 303.609375 85.746094 305.71875 88.195312 307.074219 91.058594 C 308.433594 93.921875 309.109375 97.128906 309.109375 100.667969 L 309.109375 164.3125 "/>
          <path style=" stroke:none;fill-rule:nonzero;fill:rgb(79.6%,23.5%,20%);fill-opacity:1;" d="M 235.273438 55.089844 C 235.273438 64.757812 227.4375 72.589844 217.773438 72.589844 C 208.105469 72.589844 200.273438 64.757812 200.273438 55.089844 C 200.273438 45.425781 208.105469 37.589844 217.773438 37.589844 C 227.4375 37.589844 235.273438 45.425781 235.273438 55.089844 "/>
          <path style=" stroke:none;fill-rule:nonzero;fill:rgb(25.1%,38.8%,84.7%);fill-opacity:1;" d="M 72.953125 55.089844 C 72.953125 64.757812 65.117188 72.589844 55.453125 72.589844 C 45.789062 72.589844 37.953125 64.757812 37.953125 55.089844 C 37.953125 45.425781 45.789062 37.589844 55.453125 37.589844 C 65.117188 37.589844 72.953125 45.425781 72.953125 55.089844 "/>
          <path style=" stroke:none;fill-rule:nonzero;fill:rgb(58.4%,34.5%,69.8%);fill-opacity:1;" d="M 277.320312 55.089844 C 277.320312 64.757812 269.484375 72.589844 259.820312 72.589844 C 250.15625 72.589844 242.320312 64.757812 242.320312 55.089844 C 242.320312 45.425781 250.15625 37.589844 259.820312 37.589844 C 269.484375 37.589844 277.320312 45.425781 277.320312 55.089844 "/>
          <path style=" stroke:none;fill-rule:nonzero;fill:rgb(22%,59.6%,14.9%);fill-opacity:1;" d="M 256.300781 18.671875 C 256.300781 28.335938 248.464844 36.171875 238.800781 36.171875 C 229.132812 36.171875 221.300781 28.335938 221.300781 18.671875 C 221.300781 9.007812 229.132812 1.171875 238.800781 1.171875 C 248.464844 1.171875 256.300781 9.007812 256.300781 18.671875 "/>
          </g>
          </svg>
        """
        filename = joinpath(tempdir(), "julia_logo_color.svg")
        open(filename, "w") do f
          write(f, svg_str)
        end
        readme = open(f->read(f, String), joinpath("..", "README.md"))
  
        mime_message = get_mime_msg(message)
        attachments = [joinpath("..", "README.md"), filename]
        body = get_body([addr], addr, subject, mime_message, attachments = attachments)
      
        send(server, [addr], addr, body)
  
        test_content(logfile) do s
          m = match(r"Content-Type:\s*multipart\/mixed;\s*boundary=\"(.+)\"\n", s)
          @test m !== nothing
          boundary = m.captures[1]
          @test occursin("To: $addr", s)
          @test occursin("Subject: $subject", s)
          @test occursin("Content-Type: text/html;", s)
          @test occursin("Content-Transfer-Encoding: 7bit;", s)
          @test occursin("<html>", s)
          @test occursin("<body>", s)
          @test occursin("<h1>An important link to look at&#33;</h1>", s)
          @test occursin(
              "<a href=\"https://github.com/aviks/SMTPClient.jl\">important link</a>",
              s
          )
          @test occursin("<em>cool</em>",s)
          @test occursin("<strong>julia</strong>",s)
          @test occursin("</body>", s)
          @test occursin("</html>", s)
          splt = split(s)
          ind = findall(v -> occursin("--$boundary", v), splt)
          @test length(ind) == 6
          @test String(base64decode(splt[ind[4]-1])) == readme
          @test String(base64decode(splt[ind[6]-1])) == svg_str
        end
        rm(filename)
      end

  finally
    kill(smtpsink)
    rm(logfile, force = true)
  end
end  # @testset "Send"

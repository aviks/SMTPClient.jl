function send(url::AbstractString, to::Vector, from::AbstractString, body::IO,
              options::SendOptions = SendOptions())
  if options.blocking
    rd::ReadData = ReadData()

    rd.typ = :io
    rd.src = body
    seekend(body)
    rd.sz = position(body)
    seekstart(body)

    _do_send(url, to, from, options, rd)
  else
    remotecall(send, myid(), url, to, from, body, set_opt_blocking(options))
  end
end


function _do_send(url::AbstractString, to::Vector, from::AbstractString,
                  options::SendOptions, rd::ReadData)
  ctxt = false
  slist::Ptr{Cvoid} = C_NULL
  try
    ctxt = setup_easy_handle(url, options)
    ctxt.rd = rd

    @ce_curl curl_easy_setopt ctxt.curl CURLOPT_READFUNCTION c_curl_read_cb
    @ce_curl curl_easy_setopt ctxt.curl CURLOPT_READDATA ctxt

    for tos in to
      slist = curl_slist_append(slist, tos)
    end
    @ce_curl curl_easy_setopt ctxt.curl CURLOPT_MAIL_RCPT slist
    @ce_curl curl_easy_setopt ctxt.curl CURLOPT_MAIL_FROM from

    @ce_curl curl_easy_perform ctxt.curl
    process_response(ctxt)
    return ctxt.resp
  finally
    if (slist != C_NULL)
      curl_slist_free_all(slist)
    end
    cleanup_easy_context(ctxt)
  end
end


function exec_as_multi(ctxt)
  curl = ctxt.curl
  curlm = curl_multi_init()

  if curlm == C_NULL
    error("Unable to initialize curl_multi_init()")
  end

  try
    if isa(ctxt.options.callback, Function)
      ctxt.options.callback(curl)
    end

    @ce_curlm curl_multi_add_handle curl

    n_active = Array{Int}(1)
    n_active[1] = 1

    no_to = 30 * 24 * 3600.0
    request_timeout = 0.001 + (ctxt.options.request_timeout == 0.0 ? no_to : ctxt.options.request_timeout)

    started_at = time()
    time_left = request_timeout

    # poll_fd is unreliable when multiple parallel fds are active, hence using curl_multi_perform
    cmc = curl_multi_perform(curlm, n_active);
    while (n_active[1] > 0) &&  (time_left > 0)
      nb1 = ctxt.bytes_recd
      cmc = curl_multi_perform(curlm, n_active);
      if(cmc != CURLM_OK) error("curl_multi_perform() failed: " * string(curl_multi_strerror(cmc))) end

      nb2 = ctxt.bytes_recd

      if (nb2 > nb1)
        yield() # Just yield to other tasks
      else
        sleep(0.005) # Just to prevent unnecessary CPU spinning
      end

      time_left = request_timeout - (time() - started_at)
    end
    # END OF curl_multi_perform

    if (n_active[1] == 0)
      msgs_in_queue = Array{Cint}(1)
      p_msg::Ptr{CURLMsg2} = curl_multi_info_read(curlm, msgs_in_queue)

      while (p_msg != C_NULL)
        # println("Messages left in Q : " * string(msgs_in_queue[1]))
        msg = unsafe_load(p_msg)

        if (msg.msg == CURLMSG_DONE)
          ec = convert(Int, msg.data)
          if (ec != CURLE_OK)
            # println("Result of transfer: " * string(msg.data))
            throw("Error executing request : " * string(curl_easy_strerror(ec)))
          else
            process_response(ctxt)
          end
        end

        p_msg = curl_multi_info_read(curlm, msgs_in_queue)
      end
    else
      error("request timed out")
    end

  finally
    curl_multi_remove_handle(curlm, curl)
    curl_multi_cleanup(curlm)
  end

  ctxt.resp
end

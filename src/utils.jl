macro ce_curl(f, handle, args...)
  local esc_args = [esc(arg) for arg in args]
  quote
    cc = $(esc(f))($(esc(handle)), $(esc_args...))

    if cc != CURLE_OK
      err = unsafe_string(curl_easy_strerror(cc))
      error(string($f) * "() failed: " * err)
    end
  end
end

macro ce_curlm(f, handle, args...)
  local esc_args = [esc(arg) for arg in args]
  quote
    cc = $(esc(f))($(esc(handle)), $(esc_args...))

    if cc != CURLM_OK
      err = unsafe_string(curl_multi_strerror(cc))
      error(string($f) * "() failed: " * err)
    end
  end
end

function set_opt_blocking(o::SendOptions)
  o2 = deepcopy(o)
  o2.blocking = true
  o2
end

function setup_easy_handle(url, options::SendOptions)
  ctxt = ConnContext(options)

  curl = curl_easy_init()
  curl == C_NULL && throw("curl_easy_init() failed")

  ctxt.curl = curl

  ctxt.url = url

  @ce_curl curl_easy_setopt curl CURLOPT_URL url
  @ce_curl curl_easy_setopt curl CURLOPT_WRITEFUNCTION c_curl_write_cb
  @ce_curl curl_easy_setopt curl CURLOPT_WRITEDATA ctxt
  @ce_curl curl_easy_setopt curl CURLOPT_UPLOAD 1

  if options.isSSL
    @ce_curl curl_easy_setopt curl CURLOPT_USE_SSL CURLUSESSL_ALL
  end

  if !isempty(options.username)
    @ce_curl curl_easy_setopt curl CURLOPT_USERNAME options.username
    @ce_curl curl_easy_setopt curl CURLOPT_PASSWORD options.passwd
  end

  ctxt
end

cleanup_easy_context(::Bool) = nothing

function cleanup_easy_context(ctxt::ConnContext)
  if (ctxt.curl != C_NULL)
    curl_easy_cleanup(ctxt.curl)
  end

  if ctxt.close_ostream
    close(ctxt.resp.body)
    ctxt.resp.body = nothing
    ctxt.close_ostream = false
  end
end

function process_response(ctxt)
  http_code = Array{Int}(undef, 1)
  @ce_curl curl_easy_getinfo ctxt.curl CURLINFO_RESPONSE_CODE http_code

  total_time = Array{Float64}(undef, 1)
  @ce_curl curl_easy_getinfo ctxt.curl CURLINFO_TOTAL_TIME total_time

  ctxt.resp.code = http_code[1]
  ctxt.resp.total_time = total_time[1]
end


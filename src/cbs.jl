###############################################################################
# Callbacks
###############################################################################

function curl_write_cb(buff::Ptr{Cchar}, s::Csize_t, n::Csize_t, p::Ptr{Cvoid})::Csize_t
  ctxt = unsafe_pointer_to_objref(p)
  nbytes = s * n
  write(ctxt.resp.body, unsafe_string(buff, nbytes))
  ctxt.bytes_recd = ctxt.bytes_recd + nbytes

  nbytes
end

function curl_read_cb(out::Ptr{Cchar}, s::Csize_t, n::Csize_t, p::Ptr{Cvoid})::Csize_t
  ctxt = unsafe_pointer_to_objref(p)
  bavail = s * n
  breq = ctxt.rd.sz - ctxt.rd.offset
  b2copy = bavail > breq ? breq : bavail

  if ctxt.rd.typ == :buffer
    ccall(:memcpy, Ptr{Cvoid}, (Ptr{Cvoid}, Ptr{Cvoid}, UInt),
          out, convert(Ptr{UInt8}, ctxt.rd.str) + ctxt.rd.offset, b2copy)
  elseif ctxt.rd.typ == :io
    b_read = read(ctxt.rd.src, b2copy)
    ccall(:memcpy, Ptr{Cvoid}, (Ptr{Cvoid}, Ptr{Cvoid}, UInt), out, b_read, b2copy)
  end
  ctxt.rd.offset = ctxt.rd.offset + b2copy

  b2copy
end

function curl_multi_timer_cb(curlm::Ptr{Cvoid}, timeout_ms::Clong, p::Ptr{Cvoid})::Cint
  muctxt = unsafe_pointer_to_objref(p)
  muctxt.timeout = timeout_ms / 1000.0

  @info "Requested timeout value : " * string(muctxt.timeout)

  0
end

null_cb(curl) = nothing

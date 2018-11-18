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

function writeptr(dst::Ptr{Cchar}, rd::ReadData, n::Csize_t)::Csize_t
  src = read(rd.src, n)
  n = length(src)
  ccall(:memcpy, Ptr{Cvoid}, (Ptr{Cvoid}, Ptr{Cvoid}, UInt), dst, src, n)
  n
end

function curl_read_cb(out::Ptr{Cchar}, s::Csize_t, n::Csize_t, p::Ptr{Cvoid})::Csize_t
  ctxt = unsafe_pointer_to_objref(p)
  writeptr(out, ctxt.rd, s * n)
end

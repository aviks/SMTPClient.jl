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

function encode_attachment(filename::String)
    io = IOBuffer()
    iob64_encode = Base64EncodePipe(io)
    open(filename, "r") do f
        write(iob64_encode, f)
    end
    close(iob64_encode)

    filename_ext = split(filename, '.')[end]

    if haskey(mime_types, filename_ext)
        content_type = mime_types[filename_ext]
    else
        content_type = "application/octet-stream"
    end

    if haskey(mime_types, filename_ext) && startswith(mime_types[filename_ext], "image")
        content_disposition = "inline"
    else
        content_disposition = "attachment"
    end

    # Some email clients, like Spark Mail, have problems when the attachment
    # encoded string is very long. This code breaks the payload into lines with
    # 75 characters, avoiding those problems.
    raw_attachment = String(take!(io))
    buf = IOBuffer()
    char_count = 0

    for c in raw_attachment
        write(buf, c)
        char_count += 1

        if char_count == 75
            write(buf, "\r\n")
            char_count = 0
        end
    end

    encoded_str =
        "Content-Disposition: $content_disposition;\r\n" *
        "    filename=\"$(basename(filename))\"\r\n" *
        "Content-Type: $content_type;\r\n" *
        "    name=\"$(basename(filename))\"\r\n" *
        "Content-ID: <$(basename(filename))>\r\n" *
        "Content-Transfer-Encoding: base64\r\n" *
        "\r\n" *
        "$(String(take!(buf)))\r\n"
    return encoded_str
end

# See https://www.w3.org/Protocols/rfc1341/7_1_Text.html about charset
function get_mime_msg(message::String, ::Val{:plain}, charset::String = "UTF-8")
    msg = 
        "Content-Type: text/plain; charset=\"$charset\"\r\n" *
        "Content-Transfer-Encoding: quoted-printable\r\n\r\n" *
        "$message\r\n"
    return msg
end

get_mime_msg(message::String, ::Val{:utf8}) =
    get_mime_msg(message, Val(:plain), "UTF-8")

get_mime_msg(message::String, ::Val{:usascii}) =
    get_mime_msg(message, Val(:plain), "US-ASCII")

get_mime_msg(message::String) = get_mime_msg(message, Val(:utf8))

function get_mime_msg(message::String, ::Val{:html})
    msg = 
        "Content-Type: text/html;\r\n" *
        "Content-Transfer-Encoding: 7bit;\r\n\r\n" *
        "\r\n" *
        "<html>\r\n<body>" *
        message *
        "</body>\r\n</html>"
    return msg
end

get_mime_msg(message::HTML{String}) = get_mime_msg(message.content, Val(:html))

get_mime_msg(message::Markdown.MD) = get_mime_msg(Markdown.html(message), Val(:html))

#Provide the message body as RFC5322 within an IO

function get_body(
        to::Vector{String},
        from::String,
        subject::String,
        msg::String;
        cc::Vector{String} = String[],
        replyto::String = "",
        attachments::Vector{String} = String[]
    )

    boundary = "Julia_SMTPClient-" * join(rand(collect(vcat('0':'9','A':'Z','a':'z')), 40))

    tz = mapreduce(
        x -> string(x, pad=2), *,
        divrem( div( ( now() - now(Dates.UTC) ).value, 60000 ), 60 )
    )
    date = join([Dates.format(now(), "e, d u yyyy HH:MM:SS", locale="english"), tz], " ")

    contents = 
        "From: $from\r\n" *
        "Date: $date\r\n" *
        "Subject: $subject\r\n" *
        ifelse(length(cc) > 0, "Cc: $(join(cc, ", "))\r\n", "") *
        ifelse(length(replyto) > 0, "Reply-To: $replyto\r\n", "") *
        "To: $(join(to, ", "))\r\n"

    if length(attachments) == 0
        contents *=
            "MIME-Version: 1.0\r\n" *
            "$msg\r\n\r\n"
    else
        contents *=
            "Content-Type: multipart/mixed; boundary=\"$boundary\"\r\n" *
            "MIME-Version: 1.0\r\n" *
            "\r\n" *
            "This is a message with multiple parts in MIME format.\r\n" *
            "--$boundary\r\n" * 
            msg *
            "\r\n--$boundary\r\n" * 
            join(encode_attachment.(attachments), "\r\n--$boundary\r\n") *
            "\r\n--$boundary--\r\n"
    end
    body = IOBuffer(contents)
    return body
end

# Copyright (c) 2014 Christian Koch <cfkoch@sdf.lonestar.org>
# All rights reserved.
# 
# Redistribution and use in source and binary forms, with or without
# modification, are permitted provided that the following conditions are
# met:
# 
#   1. Redistributions of source code must retain the above copyright
#   notice, this list of conditions and the following disclaimer.
# 
#   2. Redistributions in binary form must reproduce the above copyright
#   notice, this list of conditions and the following disclaimer in the
#   documentation and/or other materials provided with the distribution.
# 
# THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS
# IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO,
# THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR
# PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR
# CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL,
# EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO,
# PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR
# PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF
# LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING
# NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
# SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

#
# TODO
#
# - The adminkey should not be sent in plaintext over the wire. Try
# public-key crypto instead. Or Basic and/or Digest authentication?
# - Should we store the adminkey in the database? Or store it in some other
# database? This will allow the admin to change the key without bringing the
# server down.
# - Let the admin change the MIME-types map.
#

require 'rack'
require 'pstore'

class FileWrapper
  PARTSIZE = 8192

  def initialize(path)
    @path = path
    @f = File.open(@path, "rb")
  end

  def length
    return File::Stat.new(@path).size
  end

  def to_path
    return @path
  end

  def each
    s = ""
    while s
      s = @f.read(PARTSIZE)
      yield s if s
    end
  end

  def close
    @f.close
  end
end

class Receiptd
  REDEEMCODE_PARAM = "redeemcode".freeze
  ADMIN_HEADER = "X-Admin".freeze

  # `root` specifies the "slashdir" for serving static files. `db` indicates
  # a path to store the collection of redeemcodes for the files under the
  # `root`. `admin_key` is the key that is required in order to make changes
  # to the database.
  def initialize(root, db, admin_key, *options)
    @root = File.absolute_path(root)
    @admin_key = admin_key
    @db = PStore.new(db)
    @db.transaction { } # Force the file to exist if it doesn't already
  end

  def call(env)
    @req = Rack::Request.new(env)
    @res = Rack::Response.new

    case @req.request_method.upcase
    when "GET"; _get;
    when "POST"; _post;
    else
      complain(405)
    end

    return @res.finish
  end

  private

  # Transforms a HTTP requeset header into a Rack environment variable. For
  # example, "X-Foo-Bar" becomes "HTTP_X_FOO_BAR".
  def to_rack_header(str)
    return "HTTP_" + str.upcase.gsub("-", "_")
  end

  # Sets up the HTTP response to return useful information, mainly when
  # interacting with curl(1).
  def complain(status, message=nil)
    @res.status = status
    @res["Content-Type"] = "text/plain;charset=ascii"
    @res.write("#{status} #{Rack::Utils::HTTP_STATUS_CODES[status]}\n")
    @res.write(message + "\n") if message
  end

  # Returns a simple 200 OK response for successful requests that are NOT
  # for files under the root.
  def ok
    complain(200)
  end

  # For a given path under the root, return an array of the redeemcodes set
  # up for that path. This method might return nil, indicating there are no
  # redeemcodes for that file.
  def codes_for_file(path)
    return @db.transaction { @db[path] }
  end

  # Returns the static file.
  def _get
    if not (redeemcode = @req.GET[REDEEMCODE_PARAM])
      complain(401, sprintf("Expecting request parameter \"%s\"",
        REDEEMCODE_PARAM))
      return
    end

    path_info = @req.path_info
    real_file = File.join(@root, path_info)

    if not File.file?(real_file)
      complain(404)
      return
    end

    relevant_codes = codes_for_file(path_info)

    if !relevant_codes
      complain(400, sprintf("There are no redeemcodes for file \"%s\"",
        path_info))
      return
    end

    if !relevant_codes.include?(redeemcode)
      complain(401, sprintf(
        "\"%s\" is not a valid redeemcode for file \"%s\"",
        redeemcode, path_info))
      return
    end

    @res["Content-Type"] = Rack::Mime.mime_type(File.extname(path_info))
    @res["Connection"] = "keep-alive"
    @res["Content-Disposition"] = sprintf("attachment;filename=\"%s\"",
      File.basename(path_info))
    @res.status = 200

    f = FileWrapper.new(real_file)
    @res["Content-Length"] = f.length.to_s
    @res.body = f
  end

  # Updates the database of redeemcodes.
  def _post
    if not @req.env[to_rack_header(ADMIN_HEADER)]
      complain(401)
      return
    end

    path_info = @req.path_info
    new_code = @req.POST["redeemcode"]

    if not new_code or new_code.empty?
      complain(403, "Cannot have an empty redeemcode")
      return
    end

    @db.transaction do
      @db[path_info] ||= []
      if @db[path_info].include?(new_code)
        complain(409, sprintf(
          "Redeemcode \"%s\" already exists for file \"%s\"",
          new_code, path_info))
        return
      else
        @db[path_info].push(new_code)
        ok
      end
    end
  end
end

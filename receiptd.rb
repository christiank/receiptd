#
# TODO
#
# - The adminkey should not be sent in plaintext over the wire. Try
# public-key crypto instead. Or Basic and/or Digest authentication?
# - Should we store the adminkey in the database? Or store it in some other
# database? This will allow the admin to change the key without bringing the
# server down.
# - Investigate streaming responses.
# - Let the admin change the MIME-types map.
#

require 'rack'
require 'pstore'

class Receiptd
  MEGABYTE = 1024 * 1024
  REDEEMCODE_HEADER = "X-Redeemcode"
  ADMIN_HEADER = "X-Admin"

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

  def to_rack_header(str)
    return "HTTP_" + str.upcase.gsub("-", "_")
  end

  def complain(status, message=nil)
    @res.status = status
    @res["Content-Type"] = "text/plain;charset=ascii"
    @res.write("#{status} #{Rack::Utils::HTTP_STATUS_CODES[status]}\n")
    @res.write(message + "\n") if message
  end

  def ok
    complain(200)
  end

  def codes_for_file(path)
    return @db.transaction { @db[path] }
  end

  # Returns the static file.
  def _get
    if not (redeemcode = @req.env[to_rack_header(REDEEMCODE_HEADER)])
      complain(401, sprintf("Expecting request header \"%s\"",
        REDEEMCODE_HEADER))
      return
    end

    path_info = @req.path_info
    real_file = File.join(@root, path_info)

    if not File.file?(real_file)
      complain(404)
      return
    end

    if !codes_for_file(path_info).include?(redeemcode)
      complain(401, sprintf(
        "\"%s\" is not a valid redeemcode for file \"%s\"",
        redeemcode, path_info))
      return
    end

    mime = Rack::Mime.mime_type(File.basename(path_info))
    @res["Content-Type"] = mime

    f = File.open(real_file, "r")
    s = ""

    while s 
      s = f.read(MEGABYTE)
      @res.write(s) if s
    end

    f.close
    @res.status = 200
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

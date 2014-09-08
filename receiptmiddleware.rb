require 'pstore'
require 'rack'

# This middleware is intended to be put before an instance of Rack::File.
class ReceiptMiddleware
  REDEEMCODE_PARAM = "redeemcode".freeze
  REDEEMCODE_FORM_KEY = REDEEMCODE_PARAM
  ADMIN_HEADER = "X-Admin".freeze

  def initialize(app, db, adminkey)
    @app = app
    @adminkey = adminkey
    @db = PStore.new(db)
    @db.transaction {} # Force the DB to exist if it doesn't already
  end

  def call(env)
    @req = Rack::Request.new(env)
    @res = Rack::Response.new

    case @req.request_method.upcase
    when "GET", "HEAD"
      return @app.call(env) if _get
      # Otherwise an error occured and we return OUR response.
    when "POST"
      _post
    else
      complain(405)
      @res["Allow"] = "GET, HEAD, POST"
    end

    return @res.finish
  end

  private

  def to_rack_header(str)
    return "HTTP_" + str.upcase.gsub("-", "_")
  end

  def complain(status, message=nil)
    @res["Content-Type"] = "text/plain;charset=ascii"
    @res.status = status
    @res.write(sprintf("%d %s\n", status,
      Rack::Utils::HTTP_STATUS_CODES[status]))
    @res.write(message + "\n") if message
  end

  def ok
    complain(200)
  end

  # NOTE: Might return nil.
  def codes_for_path(path)
    return @db.transaction { @db[path] }
  end

  def _get
    path_info = @req.path_info

    if not (redeemcode = @req.GET[REDEEMCODE_PARAM])
      complain(400, sprintf("Missing request parameter %s",
        REDEEMCODE_PARAM.inspect))
      return false
    end

    valid_codes = codes_for_path(path_info)

    if not (valid_codes and valid_codes.include?(redeemcode))
      complain(400, sprintf("File %s has no redeemcode %s",
        path_info.inspect, redeemcode.inspect))
      return false
    end

    # XXX How to pass this bit along to Rack::File?
    # @res["Content-Disposition"] = sprintf("attachment;filename=\"%s\"",
    #   File.basename(path_info))

    return true
  end

  def _post
    if not (adminkey = @req.env[to_rack_header(ADMIN_HEADER)])
      return complain(401, sprintf("Missing admin header %s",
        ADMIN_HEADER.inspect))
    end

    if not (redeemcode = @req.POST[REDEEMCODE_FORM_KEY])
      return complain(400, sprintf("Missing form key %s",
        REDEEMCODE_PARAM.inspect))
    end

    path_info = @req.path_info
    codes_already = codes_for_path(path_info)

    if codes_already and codes_already.include?(redeemcode)
      return complain(409, sprintf("File %s already has a redeemcode %s",
        path_info.inspect, redeemcode.inspect))
    end

    @db.transaction {
      @db[path_info] ||= []
      @db[path_info].push(redeemcode)
    }

    return ok
  end
end

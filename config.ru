require './receiptd'
use Rack::CommonLogger
adminkey = "abcd1235"
run Receiptd.new("./testroot", "receiptd.pstore", adminkey)

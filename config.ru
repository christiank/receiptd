require './receiptd'
#use Rack::CommonLogger
adminkey = "abcd1234"
run Receiptd.new("./testroot", "receiptd.pstore", adminkey)

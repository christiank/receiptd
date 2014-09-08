require './receiptmiddleware'
use Rack::CommonLogger
#use Rack::ShowStatus
#use Rack::ShowExceptions
use ReceiptMiddleware, "receiptd.pstore", "abcd1234"
run Rack::File.new("./testroot")

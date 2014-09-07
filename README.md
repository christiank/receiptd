# receiptd

**receiptd** implements a file sharing service over HTTP which prevents
files from being accessed without a special code.

Put another way, it's a static file server with a tad of extra logic built
in to prevent the files from being downloaded by any and all unauthorized
clients.


## How it works -- high level

1. A customer buys a digital good from your online store.

2. In the background, an HTTP POST request is sent to receiptd. This lets
receiptd know (1) the file(s) your customer bought and (2) the special code
that this customer can use to download the file(s).

3. You somehow notify the customer of the special redeem code, e.g. via
email.

4. The customer sends to the receiptd server a specially crafted HTTP GET
request for the file(s). If the request does not contain a valid redeem code
then the receiptd responds with "401 Unauthorized."


## Low level description

This is a Ruby/Rack application. TODO: add more here. 

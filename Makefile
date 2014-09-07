.PHONY: default test basic-get basic-post show-db clean

db=receiptd.pstore
url=http://localhost:9292

text_file=/test.txt
nonexistent_file=/ffffff.txt

redeem_header0=-G -d "redeemcode=ffffffff"
redeem_header1=-G -d "redeemcode=a1b2c3d4e5f6"
redeem_header2=-G -d "redeemcode=6f5e4d3c2b1a"
admin_header=-H "X-Admin: abcd1234"

redeem_form1=-d redeemcode=a1b2c3d4e5f6
redeem_form2=-d redeemcode=6f5e4d3c2b1a

SEP=@echo ---

#####

default: test

test: clean basic-post basic-get 

basic-get:
	curl ${redeem_header0} ${url}${text_file}
	${SEP}
	curl ${redeem_header1} ${url}${text_file}
	${SEP}
	curl ${redeem_header2} ${url}${text_file}
	${SEP}
	curl ${url}/ 
	${SEP}
	curl ${redeem_header1} ${url}/ 
	${SEP}
	curl ${redeem_header1} ${url}${nonexistent_file}
	${SEP}

basic-post:
	curl -X POST ${admin_header} ${url}
	${SEP}
	curl -X POST ${admin_header} ${url}${text_file}
	${SEP}
	curl -X POST ${redeem_form1} ${admin_header} ${url}${text_file}
	${SEP}
	curl -X POST ${redeem_form2} ${admin_header} ${url}${text_file}
	${SEP}
	curl -X POST ${redeem_form2} ${admin_header} ${url}${text_file}
	${SEP}

show-db:
	@ruby -r pstore \
		-e 'db = PStore.new("${db}")' \
		-e 'db.transaction { db.roots.each { |r| puts("#{r.inspect} => #{db[r].inspect}") }}'

clean:
	rm -f ${db}
	${SEP}

PACKAGE     = quad
REBAR       = rebar3
HOME        = $(shell pwd)

.PHONY: test doc

all: compile

##
## Compilation targets
##

compile:
	$(REBAR) compile

##
## Test targets
##

check: test xref dialyzer lint

test: eunit ct
	${REBAR} cover -v

eunit:
	${REBAR} eunit

ct:
	${REBAR} ct --readable=false --verbose

cover: test
	open _build/test/cover/index.html

xref:
	${REBAR} xref skip_deps=true

dialyzer:
	${REBAR} dialyzer

lint:
	${REBAR} as lint lint

shell:
	${REBAR} shell --apps ${PACKAGE}

logs:
	tail -F .lager/*/log/*.log

clear:
	pkill -9 beam.smp ; rm -rf .lager test/.rebar3 *.xml
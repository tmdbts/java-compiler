lexer:
	@echo "Building lexer...\n"

	mkdir -p bin
	cd bin && flex ../src/gocompiler.l && $(CC) lex.yy.c -o lexer

	@echo "\nLexer built successfully."

test: lexer
	@echo "Running tests...\n"

	sh tests/test.sh -b bin/lexer -m 1 -l

clean:
	rm -rf bin

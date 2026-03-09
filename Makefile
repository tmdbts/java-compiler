lexer:
	@echo "Building lexer...\n"

	mkdir -p bin
	cd bin && flex ../src/java_compiler.l && $(CC) lex.yy.c -o lexer

	@echo "\nLexer built successfully."

test: lexer
	@echo "Running tests...\n"

	sh tests/test.sh -b bin/lexer -m 1 -l

zip:
	@echo "Creating zip archive...\n"

	zip -r bin/java_compiler.zip src/java_compiler.l

	@echo "Zip archive created successfully."

clean:
	rm -rf bin

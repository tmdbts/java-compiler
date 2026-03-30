parser:
	@echo "Building parser... \n"

	mkdir -p bin	
	cd bin && \
		yacc -dv ../src/java_compiler.y && \
		flex ../src/java_compiler.l && \
		$(CC) y.tab.c lex.yy.c ../src/ast.c -I../src -Wall -Wno-unused-function -o jucompiler

	@echo "\nParser built successfully."

lexer:
	@echo "Building lexer...\n"

	mkdir -p bin
	cd bin && \
		flex ../src/java_compiler.l && \
 		$(CC) lex.yy.c -o jucompiler

	@echo "\nLexer built successfully."

test1: lexer
	@echo "Running tests...\n"

	sh tests/test.sh -b bin/lexer -m 1 -l

zip:
	@echo "Creating zip archive...\n"

	zip -r bin/jucompiler.zip src/java_compiler.l src/java_compiler.y \
		src/ast.c src/ast.h

	@echo "Zip archive created successfully."

clean:
	rm -rf bin

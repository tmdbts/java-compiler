build:
	@echo "Building parser... \n"

	mkdir -p bin	
	cd bin && \
		yacc -dv ../src/java_compiler.y && \
		flex ../src/java_compiler.l && \
		$(CC) y.tab.c lex.yy.c ../src/ast.c ../src/semantics.c -I../src -Wall -Wno-unused-function -o jucompiler

	@echo "\nParser built successfully."

test: build
	@echo "Running all tests...\n"

	cd tests && bash test.sh ../bin/jucompiler

test1: build
	@echo "Running meta1 tests...\n"

	cd tests && bash test.sh ../bin/jucompiler --only meta1

test2: build
	@echo "Running meta2 tests...\n"

	cd tests && bash test.sh ../bin/jucompiler --only meta2

test3: build
	@echo "Running meta3 tests...\n"

	cd tests && bash test.sh ../bin/jucompiler --only meta3

zip:
	@echo "Creating zip archive...\n"

	zip -r bin/jucompiler.zip src/java_compiler.l src/java_compiler.y \
		src/ast.c src/ast.h src/semantics.c src/semantics.h

	@echo "Zip archive created successfully."

clean:
	rm -rf bin

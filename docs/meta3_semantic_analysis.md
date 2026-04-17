# Meta3 Semantic Analysis

This document explains the Meta3 implementation in this project. It is written
as a code guide: where the semantic-analysis flow starts, what data structures
are used, how symbol tables are built, how expressions are typed, and how the
expected Meta3 output is produced.

## Scope

Meta3 adds semantic analysis on top of the existing Meta1 lexer and Meta2
parser/AST. The implementation keeps the current AST shape and parser flow, then
adds the minimum extra information needed by semantic analysis:

- Source positions on AST nodes for semantic error locations.
- Type annotations on expression nodes for the annotated AST.
- Class and method symbol tables.
- Semantic checks for declarations, statements, expressions, method calls, and
  literal bounds.
- CLI modes for `-s`, `-e3`, and no-option semantic checking.

The public semantic interface is intentionally small and lives in
`src/semantics.h`:

```c
int check_program(struct node *program);
void show_symbol_table(void);
void print_annotated_tree(struct node *node, int depth);
```

All semantic helper types and functions are private to `src/semantics.c`.

## File Overview

`src/ast.h` and `src/ast.c`

The AST node structure now stores semantic metadata:

```c
struct node {
    enum category category;
    char *token;
    int line;
    int column;
    char *annotation;
    struct node_list *children;
};
```

The existing `new_node(...)` constructor is still used. It initializes
`line`, `column`, and `annotation` with safe default values. Parser actions then
fill source positions where needed. `set_annotation(...)` manages the annotation
string used by Meta3 printing.

Important helpers:

- `get_child(node, index)` gives indexed access to AST children.
- `child_count(node)` is used for method-call argument counts and parameter
  counts.
- `set_annotation(node, text)` updates an AST node annotation.
- `print_tree(...)` remains the Meta2 tree printer and does not print semantic
  annotations.

`src/java_compiler.y`

The parser keeps the same AST structure used by Meta2, but attaches source
locations to nodes that may produce semantic errors. The grammar uses Bison/Yacc
locations so identifiers, literals, operators, `return`, `if`, `while`,
`Call`, `ParseArgs`, and `Length` nodes can report errors at the correct line
and column.

`src/java_compiler.l`

The driver chooses which phase to run:

- `-l` and `-e1` run lexical analysis only.
- `-t` and `-e2` run syntax analysis and print the Meta2 AST if there are no
  errors.
- `-s` runs semantic analysis, then prints semantic errors, symbol tables, a
  blank line, and the annotated AST.
- `-e3` runs semantic analysis and prints semantic errors only.
- No option behaves like `-e3`.

If lexical or syntax errors exist, semantic analysis is skipped.

`src/semantics.c`

This file contains the full Meta3 semantic implementation. It owns the internal
semantic state, builds symbol tables, checks method bodies, annotates expression
nodes, and prints semantic output.

## Semantic State

`src/semantics.c` uses file-local state because the compiler processes one input
file per run. Nothing outside this file needs direct access to the tables.

Main internal types:

- `enum semantic_type` represents `int`, `double`, `boolean`, `String[]`,
  `void`, and `undef`.
- `enum symbol_kind` distinguishes fields, methods, parameters, locals, and the
  synthetic method `return` entry.
- `struct class_symbol` stores fields and method signatures for the class table.
- `struct method_info` stores one method's signature, body node, flags, and
  method-local symbol table.
- `struct table_entry` stores entries inside one method table.
- `struct semantic_error` stores semantic errors before printing.

Important flags in `struct method_info`:

- `can_resolve_calls` is false for duplicate or reserved-name methods. These
  methods remain in the method list but are ignored by call resolution.
- `show_table` is false for duplicate or reserved-name methods. Their method
  tables are not printed.
- `in_scope` belongs to method-table entries. Parameters are visible from the
  start of the method. Local variables become visible only when their `VarDecl`
  is reached during body traversal.

## Overall Flow

The public entry point is `check_program(struct node *program)`.

Its flow is:

1. Reset semantic global state.
2. Clear old AST annotations.
3. Build class and method symbol tables with declaration information.
4. Traverse each valid method body in source order.
5. Print semantic errors in the order they were discovered.
6. Return the number of semantic errors.

The implementation intentionally uses two semantic phases.

## Phase 1: Declaration And Signature Collection

`build_symbol_tables(...)` walks the direct children of `Program` after the
class identifier.

Fields are handled by `collect_field(...)`:

- `_` is rejected as a reserved symbol.
- Duplicate field names are rejected.
- Valid fields are inserted into the class symbol table in source order.

Methods are handled by `collect_method(...)`:

- The method return type, name, parameters, body, and signature are stored in a
  `struct method_info`.
- A synthetic `return` entry is added first to the method table.
- Parameters are added next and marked as parameters.
- The method signature is built as text like `(int,double)`.
- Duplicate methods are detected by same name and same parameter types.
- Duplicate methods are not inserted into the class table and are not used for
  call resolution.
- Duplicate methods still keep enough information to report parameter problems
  found inside their header.

This phase also enforces duplicate parameter names because parameters are
entered into the method table before body checking starts.

## Phase 2: Method Body Checking

`check_method(...)` walks one method body in source order.

Local variable declarations are special:

- A local `VarDecl` is inserted only when that declaration is reached.
- The new local is marked `in_scope` immediately after insertion.
- Earlier uses of a later local still report `Cannot find symbol`.
- Local declarations are kept in the final printed method symbol table.

Statements are checked by `check_statement(...)`:

- `Block` recursively checks its children.
- `If` and `While` require boolean conditions.
- `Return` checks compatibility with the current method return type.
- `Return` without an expression is valid only in `void` methods.
- `Print` accepts `int`, `double`, `boolean`, and string literals.
- Expression statements such as assignment and method calls are checked through
  `check_expression(...)`.

## Name Lookup

Identifiers are resolved by `resolve_identifier(...)`.

Lookup order:

1. Current method variables currently in scope, including parameters and locals
   already reached.
2. Class fields.
3. Error if neither exists.

Fields and methods are allowed to share a name. Locals and parameters may shadow
fields. Duplicate names inside one method scope are rejected.

The reserved identifier `_` is rejected anywhere it is used as a symbol.

## Method Resolution

Method calls are checked by `check_call(...)`.

The call checker first type-checks all arguments, then resolves the method:

1. Exact name, arity, and parameter-type match wins.
2. Otherwise, one unique compatible overload may be selected.
3. `int` can widen to expected `double`.
4. No other implicit conversions are allowed.
5. If more than one compatible overload exists, the call is ambiguous.
6. If no candidate exists, the call reports `Cannot find symbol`.

Failed call diagnostics include the attempted signature, for example
`Cannot find symbol f(int,undef)`. Ambiguous diagnostics also include the
attempted signature.

When a call resolves successfully:

- The `Call` node is annotated with the method return type.
- The callee `Identifier` node is annotated with the resolved formal signature.

When a call fails:

- The `Call` node is annotated as `undef`.
- The callee `Identifier` node is annotated as `undef`.

## Expression Checking

`check_expression(...)` dispatches by AST category and delegates most real work
to smaller helpers:

- `check_assignment(...)`
- `check_call(...)`
- `check_parse_args(...)`
- `check_length(...)`
- `check_boolean_binary(...)`
- `check_equality(...)`
- `check_relational(...)`
- `check_arithmetic(...)`
- `check_shift(...)`
- `check_xor(...)`
- `check_unary_numeric(...)`
- `check_not(...)`

Literal and base expression rules:

- `Natural` annotates as `int`.
- `Decimal` annotates as `double`.
- `BoolLit` annotates as `boolean`.
- Unknown identifiers annotate as `undef`.
- Out-of-bounds integer and decimal literals report an error but keep their
  nominal type annotation.

Assignment:

- The left side is resolved as an identifier.
- The right side is type-checked as an expression.
- Exact type compatibility is allowed.
- `int` to expected `double` is allowed.
- `String[]` assignment is rejected.
- The assignment node keeps the left-hand type when the left side resolves,
  even after an incompatibility error.

Numeric and unary operators:

- Unary `+` and `-` accept numeric operands.
- Arithmetic `+`, `-`, `*`, `/`, `%` accepts numeric operands.
- Arithmetic result is `double` if either operand is `double`, otherwise `int`.

Boolean and comparison operators:

- `&&` and `||` require boolean operands and produce `boolean`.
- `<`, `>`, `<=`, `>=` require numeric operands and produce `boolean`.
- `==` and `!=` accept numeric/numeric or boolean/boolean and produce
  `boolean`.
- `!` requires a boolean operand.

Extra supported operators:

- `^` accepts `int/int` and returns `int`, or `boolean/boolean` and returns
  `boolean`.
- `<<` and `>>` accept `int/int` and return `int`.

String-array operations:

- `.length` requires a `String[]` base and returns `int`.
- `Integer.parseInt(args[index])` requires `String[]` and `int`, and returns
  `int`.
- `String[]` is otherwise only valid when passed to a `String[]` parameter.

Some invalid expressions keep their nominal result type after reporting an
error. This is deliberate recovery behavior required by the current Meta3
expected outputs:

- Invalid `.length` still annotates as `int`.
- Invalid `Integer.parseInt(...)` still annotates as `int`.
- Invalid comparison, equality, and boolean operators still annotate as
  `boolean`.

This recovery lets later checks continue and keeps annotated AST output stable.

## Semantic Errors

Semantic errors are collected with `add_error(...)` and printed by
`check_program(...)`.

Error positions come from AST node `line` and `column` values, not from lexer
globals at semantic time. This matters because semantic checks happen after
parsing, when the lexer position no longer points at the original token.

Errors are printed in semantic-pass order:

- Declaration and header errors first.
- Method body traversal errors after that, in source order.

This ordering matches the current tests and avoids a separate global sort.

## Symbol Table Printing

`show_symbol_table(...)` prints:

1. The class symbol table.
2. One method symbol table per printable method.

Class table entries include fields and non-duplicate methods in source order.

Each method table prints entries in this order:

1. Synthetic `return`.
2. Parameters.
3. Local variables, in the order their declarations are reached.

The output format is tab-separated to match the assignment tests.

## Annotated AST Printing

`print_annotated_tree(...)` is separate from `print_tree(...)`.

Meta2 output remains unchanged because `print_tree(...)` ignores semantic
annotations. Meta3 `-s` output uses `print_annotated_tree(...)`, which prints the
same tree structure plus ` - <annotation>` when a node has a semantic
annotation.

Only expression nodes should receive annotations. `StrLit` used in
`System.out.print("...")` remains unannotated in this project's current
convention.

## CLI And Test Commands

Build and run all tests:

```sh
make test
```

Run only Meta3:

```sh
make test3
```

Run the semantic table and annotated AST output for one file:

```sh
./bin/jucompiler -s < tests/meta3/Factorial.java
```

Run semantic-errors-only mode:

```sh
./bin/jucompiler -e3 < tests/meta3/CallError.java
```

No option behaves like `-e3`:

```sh
./bin/jucompiler < tests/meta3/CallError.java
```

Current expected regression baseline:

- `make test3`: `Accepted: 37 / 37`
- `make test2`: `Accepted: 37 / 37`
- `make test1`: `Accepted: 32 / 35`

The Meta1 failures are known lexer-output mismatches and are separate from this
milestone.

## Reading The Code

Good entry points when debugging:

- Start at `check_program(...)` to understand the full semantic flow.
- Read `build_symbol_tables(...)` and `collect_method(...)` for declaration
  collection.
- Read `check_method(...)` to understand local-variable visibility.
- Read `check_statement(...)` for statement-level rules.
- Read `check_expression(...)` for the expression dispatcher.
- Read the smaller `check_*` expression helpers for specific operator rules.
- Read `resolve_method_call(...)` and `check_call(...)` for overload behavior.

The important design idea is that Meta3 does not redesign the compiler. It uses
the parser's existing AST, adds positions and annotations to the existing nodes,
then performs a two-phase semantic pass over that tree.

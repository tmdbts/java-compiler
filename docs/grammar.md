# Grammar Guide

This document explains the grammar in `src/java_compiler.y`, with a focus on
the main design decisions behind it.

It is not just a list of productions. The goal here is to explain why the
grammar was written this way, what problems each choice solves, and what effect
that has on the AST and later compiler phases.

## Main Goals

When developing this grammar, there were a few practical goals:

- make the language subset work cleanly with yacc/bison
- reduce parser conflicts
- build the AST directly during parsing
- keep the AST simple for the semantic phase
- recover from some syntax errors without destroying the whole parse
- attach source positions early so later phases can report good errors

Those goals explain most of the structure in `src/java_compiler.y`.

## High-Level Shape

The grammar recognizes a single class:

```java
class Name {
    ...
}
```

Inside the class body, the grammar accepts:

- field declarations
- method declarations
- extra semicolons

This is intentionally smaller than full Java. The project is implementing a
restricted language, so the grammar chooses clarity and stable AST output over
full language coverage.

## Key Decision 1: Build The AST Directly In The Grammar

The parser does not build a full parse tree first and then convert it later.
Instead, semantic actions immediately create AST nodes with helpers like:

- `new_node(...)`
- `add_child(...)`
- `add_children(...)`
- `adopt1(...)`
- `adopt2(...)`

Why this was a good decision:

- it avoids a second tree-conversion pass
- it keeps the final tree shape under direct control
- it lets each production decide exactly what should and should not appear in
  the AST
- it makes the AST closer to what semantic analysis actually needs

Consequence:

- many grammar rules are written not just to parse input, but also to normalize
  the final AST shape

Example:

```yacc
AddExpr
    : AddExpr PLUS MulExpr
        {
            $$ = adopt2(Add, $1, $3);
            SET_POS($$, @2);
        }
```

This rule does two jobs at once:

1. parse `a + b`
2. build the AST node `Add(left, right)`

## Key Decision 2: Use Temporary Lists While Parsing, Then Flatten Them Into AST Children

Some grammar categories naturally collect multiple siblings:

- class members
- method body items
- statements
- parameters
- arguments
- identifier lists

Instead of encoding those as nested AST nodes, the grammar uses temporary
`struct node_list *` values and then attaches them with `add_children(...)`.

Why this was a good decision:

- the final AST becomes flatter and easier to traverse
- the parser avoids creating meaningless list wrapper nodes
- later passes can use child order directly instead of unpacking list syntax

Example:

- `ClassBody`, `MethodBodyItems`, and `ArgList` are list-valued grammar symbols
- `Program`, `MethodBody`, and `Call` then attach the list elements as ordinary
  children

So the AST stores "real nodes only", not parser bookkeeping.

## Key Decision 3: Normalize Multi-Name Declarations Into One Node Per Symbol

The grammar accepts declarations like:

```java
int a, b, c;
```

But it does not keep them as one declaration node with three identifiers.
Instead, it expands them into separate `VarDecl` or `FieldDecl` nodes.

Why this was a good decision:

- semantic analysis becomes much simpler
- each declaration node introduces exactly one symbol
- duplicate checks and symbol-table insertion become straightforward
- the printed AST becomes more regular

This happens in both:

- `FieldDecl`
- `VarDecl`

The grammar walks the identifier list and creates one declaration node for each
identifier.

Consequence:

- the AST is more normalized than the surface syntax

Example:

```java
public static int a, b;
```

becomes conceptually:

```text
FieldDecl
..Int
..Identifier(a)
FieldDecl
..Int
..Identifier(b)
```

## Key Decision 4: Keep Method Structure Explicit

Methods are split into:

- `MethodDecl`
- `MethodHeader`
- `MethodBody`
- `MethodParams`
- `ParamDecl`

Why this was a good decision:

- the AST clearly separates signature information from body statements
- semantic analysis can retrieve return type, name, parameters, and body by
  position
- the tree shape is consistent across methods

This is especially helpful in `semantics.c`, where the code expects:

- child `0` of `MethodDecl` to be the header
- child `1` of `MethodDecl` to be the body
- child `0` of `MethodHeader` to be the return type
- child `1` of `MethodHeader` to be the method name
- child `2` of `MethodHeader` to be the parameter list

So this grammar was designed with semantic traversal in mind, not just parsing.

## Key Decision 5: Handle `void` And `String[]` As Special Cases

The grammar treats some types specially.

`void` is not inside the general `Type` nonterminal. It has its own branch in
`MethodHeader`.

`String[]` is also not part of the general `Type` rule. It is recognized only in
the parameter grammar through:

```yacc
STRING LSQ RSQ IDENTIFIER
```

Why this was done:

- the language subset is small, so special-casing these forms is simpler than
  generalizing the whole type grammar
- it matches the project requirements closely
- it avoids widening the rest of the grammar before that complexity is needed

Tradeoff:

- the type grammar is not fully uniform
- `String[]` is available where the assignment expects it, but not as a fully
  general reusable type production

This is a deliberate simplification, not an accident.

## Key Decision 6: Rewrite Expressions Into A Precedence Ladder

This is one of the most important grammar decisions.

The original expression syntax was ambiguous for bottom-up parsing. A single
`Expr` nonterminal would create many conflicts and make AST construction harder.

So expressions were rewritten as a chain of precedence levels:

- `AssignExpr`
- `OrExpr`
- `XorExpr`
- `AndExpr`
- `EqExpr`
- `RelExpr`
- `ShiftExpr`
- `AddExpr`
- `MulExpr`
- `UnaryExpr`
- `PrimaryExpr`

Why this was a good decision:

- it encodes precedence directly in the grammar
- it reduces shift/reduce conflicts
- it makes associativity explicit
- it produces an AST that already matches operator hierarchy
- semantic analysis can type-check expression nodes without reconstructing
  precedence

Example:

```java
a + b * c < d && e
```

is forced by the grammar into a tree shaped like:

```text
And
..Lt
....Add
......Identifier(a)
......Mul
........Identifier(b)
........Identifier(c)
....Identifier(d)
..Identifier(e)
```

That structure is not guessed later. It is produced directly by the grammar.

## Key Decision 7: Use Left Recursion For Most Binary Operators

Most binary expression levels are left-recursive:

```yacc
AddExpr
    : AddExpr PLUS MulExpr
    | AddExpr MINUS MulExpr
    | MulExpr
```

Why this was a good decision:

- it gives left associativity for operators like `+`, `-`, `*`, `/`, `%`,
  `&&`, `||`, `<<`, and `>>`
- left recursion is natural and efficient for LR parsers like yacc
- it matches the expected meaning of most binary operators in the language

Example:

```java
a - b - c
```

parses as:

```text
Sub
..Sub
....Identifier(a)
....Identifier(b)
..Identifier(c)
```

which means `(a - b) - c`.

## Key Decision 8: Make Assignment Right-Associative

Assignment is different from the other binary operators.

The grammar uses:

```yacc
AssignExpr
    : IDENTIFIER ASSIGN AssignExpr
    | OrExpr
```

and also declares:

```yacc
%right ASSIGN
```

Why this was a good decision:

- it makes chained assignment parse naturally
- it matches common language behavior
- it gives the intended AST for expressions like `a = b = 1`

Result:

```text
Assign
..Identifier(a)
..Assign
....Identifier(b)
....Natural(1)
```

So the right-hand side can itself be another assignment expression.

## Key Decision 9: Solve The Dangling-Else Problem Explicitly

The grammar uses:

```yacc
%nonassoc LOWER_THAN_ELSE
%nonassoc ELSE
```

and the `if`-without-`else` rule uses:

```yacc
IF LPAR Expr RPAR Statement %prec LOWER_THAN_ELSE
```

Why this was necessary:

- the classic `if/else` grammar is ambiguous
- without disambiguation, yacc will report a shift/reduce conflict
- the intended meaning is that an `else` belongs to the nearest unmatched `if`

Why this solution was chosen:

- it is the standard yacc solution
- it keeps the grammar readable
- it resolves the conflict without redesigning control-flow syntax

This is one of the clearest examples of grammar design being driven by parser
technology, not just language appearance.

## Key Decision 10: Normalize Control-Flow Nodes For A Stable AST

The grammar does extra work in `if` and `while` rules to keep the AST shape
consistent.

For `if`:

- child `0` is always the condition
- child `1` is always the then-branch
- child `2` is always the else-branch

If an `else` is missing, the parser creates an empty `Block`.

If a branch parses as `NULL`, the parser also replaces it with an explicit empty
`Block`.

For `while`:

- child `0` is always the condition
- child `1` is always the body

Why this was a good decision:

- later phases do not need special cases for missing branches
- AST traversal becomes simpler and more uniform
- tests become more stable because the tree shape is predictable

This is a normalization decision: the AST is made slightly more regular than the
surface syntax.

## Key Decision 11: Flatten Some Block Syntax Instead Of Preserving Every Brace Pair

The `Statement` rule for `{ ... }` behaves differently depending on how many
statements are inside:

- zero statements: return `NULL`
- one statement: return that statement directly
- two or more statements: create a `Block` node

Why this was done:

- it avoids cluttering the AST with unnecessary `Block` nodes
- many single-statement brace groups do not need an extra wrapper for later
  phases
- it keeps the printed AST more compact

Tradeoff:

- the AST does not preserve every original pair of braces
- a block in the source is not always a `Block` node in the AST

This is a deliberate AST simplification.

It also explains why the `if` and `while` rules sometimes create empty
`Block` nodes manually: once block syntax is partially flattened, control-flow
nodes need help to keep a stable shape.

## Key Decision 12: Represent Special Forms With Dedicated Nodes

Some constructs are not modeled as generic Java postfix expressions. They are
given their own explicit grammar rules and AST nodes:

- `MethodInvocation` becomes `Call`
- `Integer.parseInt(args[index])` becomes `ParseArgs`
- `identifier.length` becomes `Length`
- `System.out.print(...)` becomes `Print`

Why this was a good decision:

- the supported language subset is small and specific
- these forms have special semantic rules later
- dedicated AST nodes make semantic analysis much simpler

For example:

- `Length` is easy to check as a unary string-array operation
- `ParseArgs` is easy to check as "base must be `String[]`, index must be `int`"
- `Print` is easy to treat as a statement with one printable argument

Tradeoff:

- the grammar is less general than full Java
- some constructs are modeled in a project-specific way

But for this compiler, simplicity and directness are more valuable than
generality.

## Key Decision 13: Keep Syntax Error Recovery Local

The grammar includes a few targeted error productions:

- `FieldDecl : error SEMICOLON`
- `Statement : error SEMICOLON`
- `MethodInvocation : IDENTIFIER LPAR error RPAR`
- `ParseArgs : PARSEINT LPAR error RPAR`
- `PrimaryExpr : LPAR error RPAR`

Why this was a good decision:

- it lets the parser recover from common local syntax errors
- it helps continue parsing later parts of the file
- it allows multiple syntax errors to be reported in one run

Why these recoveries return `NULL`:

- the parser can skip bad fragments without inventing fake AST structure
- later AST code already knows how to ignore `NULL` in many places
- this keeps recovery simple and predictable

This is a practical engineering choice: recover enough to keep going, but do not
pretend a broken construct is valid.

## Key Decision 14: Attach Source Locations During Parsing

The grammar uses `%locations` and the `SET_POS(node, location)` macro to attach
line and column data directly to AST nodes.

Why this was a good decision:

- semantic analysis runs after parsing, so lexer globals are no longer reliable
- storing positions in the AST lets later phases report errors at the correct
  source location
- it avoids having to reconstruct source positions later

This is especially important for nodes that become semantic error locations,
such as:

- identifiers
- literals
- operators
- `return`
- `if`
- `while`
- `Call`
- `ParseArgs`
- `Length`

So the grammar is not only building structure. It is also building future error
context.

## Key Decision 15: Keep The Grammar Close To The Semantic Phase

A recurring design pattern in this file is that grammar decisions are made with
semantic analysis in mind.

Examples:

- declarations are normalized one symbol per node
- method headers have fixed child positions
- expression precedence is already encoded in the tree
- `if` nodes always have condition, then branch, and else branch
- `Call`, `ParseArgs`, and `Length` have dedicated node kinds

Why this matters:

- semantic analysis becomes much smaller and clearer
- symbol-table construction can rely on stable tree shapes
- type checking can dispatch by node category directly

In other words, the grammar was designed not just to accept valid input, but to
produce a tree that the rest of the compiler can work with easily.

## Important Tradeoffs And Limitations

These grammar decisions are good for this project, but they come with clear
tradeoffs:

- it is not a full Java grammar
- `String[]` is special-cased rather than fully integrated into `Type`
- the AST does not preserve every brace pair
- special constructs like `Integer.parseInt(...)` are handled as dedicated forms
  instead of through a general expression grammar
- some syntax errors recover by dropping bad subtrees entirely

These are not mistakes. They are simplifications chosen to make the compiler
manageable and the AST stable.

## A Good Way To Read The Grammar

If you want to understand the file in a useful order, read it like this:

1. top-level structure: `Program`, `ClassBody`, `ClassMember`
2. declaration rules: `MethodDecl`, `FieldDecl`, `VarDecl`, `MethodHeader`
3. statement rules: `Statement`, `StatementList`, `PrintArg`
4. special forms: `MethodInvocation`, `Assignment`, `ParseArgs`
5. expression ladder from `Expr` down to `PrimaryExpr`
6. error reporting and `yyerror(...)`

That order makes the design much easier to follow because it moves from large
program structure down to the precedence-heavy expression rules.

## Short Summary

The key grammar decisions were:

- build the AST directly in parser actions
- flatten sibling sequences through temporary lists
- normalize declarations one symbol per node
- split expressions into precedence levels
- use left recursion for most binary operators
- make assignment right-associative
- solve dangling `else` explicitly
- normalize control-flow nodes for stable AST shapes
- use dedicated rules for `Call`, `ParseArgs`, `Length`, and `Print`
- recover from some syntax errors locally
- attach source locations during parsing

Together, these choices make the grammar yacc-friendly, reduce conflicts, and
produce an AST that is simple to print, traverse, and analyze semantically.

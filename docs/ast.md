# AST Guide

This document explains how the AST is built in this project, what each helper in
`src/ast.c` does, and how semantic analysis interacts with the tree.

The short version is:

- The parser and `src/ast.c` build the AST structure.
- Semantic analysis does not reorganize the tree.
- Semantic analysis only adds metadata to existing nodes through
  `node->annotation`.

## The AST Node

The core AST type lives in `src/ast.h`:

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

Each field has a different role:

- `category`: what kind of node this is, such as `Program`, `Add`, `If`,
  `Identifier`, `Natural`, or `Call`.
- `token`: the lexical text for leaf nodes like `Identifier(x)` or
  `Natural(123)`. Most internal nodes have `token == NULL`.
- `line` and `column`: source position, mainly used for semantic errors.
- `annotation`: semantic metadata, such as `int`, `double`, `boolean`, `undef`,
  or a call signature like `(int,double)`.
- `children`: the ordered child list for this node.

## How The AST Gets Built

The grammar in `src/java_compiler.y` decides the tree shape, and the helpers in
`src/ast.c` provide the operations used to build that shape.

### `new_node(category, token)`

Creates one node, but does not attach it anywhere yet.

What it changes:

- Allocates a new AST node.
- Sets `category` and `token`.
- Initializes `line = 0`, `column = 0`, `annotation = NULL`, and
  `children = NULL`.

Typical use:

```c
struct node *id = new_node(Identifier, $1);
struct node *call = new_node(Call, NULL);
```

This is the starting point for almost every AST fragment.

### `add_child(parent, child)`

Appends `child` to the end of `parent->children`.

What it changes:

- Mutates the parent node by growing its child list.
- Preserves child order, which matters because semantic analysis depends on
  positional access through `get_child(node, index)`.

Example:

```c
add_child(call, id);
add_child(call, arg1);
add_child(call, arg2);
```

This produces:

```text
Call
..Identifier(foo)
..Identifier(x)
..Natural(1)
```

### `adopt1(category, a)`

Creates a new parent node and makes `a` its only child.

What it changes:

- Creates one new AST node.
- Reparents `a` under that new node.

Typical use:

- Unary minus: `-x`
- Unary plus: `+x`
- Logical not: `!x`
- Print: `System.out.print(expr)`
- Length: `args.length`

Example:

Source:

```java
-x
```

AST:

```text
Minus
..Identifier(x)
```

### `adopt2(category, a, b)`

Creates a new parent node and makes `a` and `b` its children.

What it changes:

- Creates one new AST node.
- Reparents `a` and `b` under that new node in left-to-right order.

Typical use:

- `a + b`
- `a * b`
- `a < b`
- `a && b`
- `a ^ b`

Example:

Source:

```java
a + b
```

AST:

```text
Add
..Identifier(a)
..Identifier(b)
```

### `new_list(node)`, `append_list(list, node)`, `join_lists(a, b)`

These do not create AST syntax nodes. They create and manipulate temporary
linked lists of nodes while the parser is still collecting siblings.

They are used for:

- class members
- parameter lists
- argument lists
- statement lists
- identifier lists

What they change:

- They build temporary `struct node_list` chains.
- They do not change the shape of the AST by themselves.

These are parser assembly helpers.

### `add_children(parent, list)`

Takes a temporary list and attaches each listed node to `parent`.

What it changes:

- Mutates `parent` by appending all nodes from the list as children.

This is how temporary parser lists become real AST child sequences.

### `copy_leaf_node(node)`

Creates a shallow copy of a leaf node.

What it changes:

- Allocates a new node with the same `category`, `token`, `line`, `column`, and
  `annotation`.
- Does not copy children.

In this project it is used mainly to duplicate type nodes in declarations so
multiple declarations do not share the same type node instance.

Example:

Source:

```java
int a, b;
```

The parser expands this into two declaration nodes, not one:

```text
VarDecl
..Int
..Identifier(a)
VarDecl
..Int
..Identifier(b)
```

The two `Int` nodes are separate nodes because `copy_leaf_node(...)` is used.

### `get_child(node, index)`

Does not change the AST. It is a read helper used everywhere semantic analysis
needs positional access.

Examples:

- in `Assign`, child `0` is the left identifier and child `1` is the right
  expression
- in `If`, child `0` is the condition, child `1` is the then branch, and child
  `2` is the else branch
- in `MethodHeader`, child `0` is the return type, child `1` is the method
  name, and child `2` is the parameter list

### `set_annotation(node, text)`

This is the only AST helper that semantic analysis uses to mutate existing nodes
after parsing.

What it changes:

- Frees the old `annotation`, if one exists.
- Stores a fresh copy of the new annotation text.

This changes metadata on a node, not the tree structure.

### `print_tree(node, depth)`, `child_count(node)`, `category_name(category)`

These do not change the AST.

- `print_tree(...)` prints the syntax tree without semantic annotations.
- `child_count(...)` counts children.
- `category_name(...)` maps enum values to printable names.

## Concrete AST Examples

### Example 1: Expression precedence

Source:

```java
a + b * c
```

AST:

```text
Add
..Identifier(a)
..Mul
....Identifier(b)
....Identifier(c)
```

Why:

- `b * c` is grouped first by the grammar.
- Then `a + (...)` becomes the parent.

### Example 2: Parentheses do not survive in the AST

Source:

```java
(a + b)
```

AST:

```text
Add
..Identifier(a)
..Identifier(b)
```

There is no special node for parentheses. The rule `LPAR Expr RPAR` just returns
the inner expression node.

### Example 3: Right-associative assignment

Source:

```java
a = b = 1
```

AST:

```text
Assign
..Identifier(a)
..Assign
....Identifier(b)
....Natural(1)
```

Why:

- `AssignExpr` is right-recursive in the grammar.
- So `b = 1` is built first and becomes the right child of `a = ...`.

### Example 4: Method call shape

Source:

```java
foo(x, 1, y)
```

AST:

```text
Call
..Identifier(foo)
..Identifier(x)
..Natural(1)
..Identifier(y)
```

The callee name is the first child. The arguments follow after it in order.

### Example 5: `if` shape

Source:

```java
if (cond) x = 1;
```

AST:

```text
If
..Identifier(cond)
..Assign
....Identifier(x)
....Natural(1)
..Block
```

Even without an explicit `else`, the AST still gets an empty `Block` as the
third child. This keeps the `If` shape consistent.

### Example 6: `while` with an empty body

Source:

```java
while (ok) {}
```

AST:

```text
While
..Identifier(ok)
..Block
```

The parser inserts an empty `Block` node because the statement result for `{}`
would otherwise be `NULL`.

### Example 7: Print with a string literal

Source:

```java
System.out.print("hello");
```

AST:

```text
Print
..StrLit("hello")
```

### Example 8: `args.length`

Source:

```java
args.length
```

AST:

```text
Length
..Identifier(args)
```

The `.length` part becomes the parent node. The base identifier becomes its only
child.

### Example 9: `Integer.parseInt(args[i])`

Source:

```java
Integer.parseInt(args[i])
```

AST:

```text
ParseArgs
..Identifier(args)
..Identifier(i)
```

The AST stores the array-like base and the index expression. It does not keep a
general-purpose array indexing node for this special form.

## Important Edge Cases

### Empty block statements can disappear

In the rule:

```java
{}
```

the parser returns `NULL` for the statement if the block has no statements.

That means a bare empty block in a method body does not appear as a standalone
AST node.

However, inside `if` and `while`, the parser may create an explicit empty
`Block` node so the control-flow node always has the expected number of
children.

### Single-statement blocks are flattened

Source:

```java
{
    x = 1;
}
```

AST:

```text
Assign
..Identifier(x)
..Natural(1)
```

This does not become a `Block` with one child. The parser returns the single
statement directly. A `Block` node is created only when there are two or more
statements.

### `return;` has no child

Source:

```java
return;
```

AST:

```text
Return
```

`add_child(...)` ignores `NULL`, so a `Return` without an expression becomes a
node with zero children.

### One declaration with many names becomes many AST nodes

Source:

```java
public static int a, b, c;
```

AST:

```text
FieldDecl
..Int
..Identifier(a)
FieldDecl
..Int
..Identifier(b)
FieldDecl
..Int
..Identifier(c)
```

This is an intentional normalization step. It makes later semantic passes
simpler because each declaration node only describes one symbol.

### `String[]` is special in this grammar

`String[]` does not come from the general `Type` rule. It is built explicitly in
the formal-parameter rules.

That means:

- you can see `StringArray` nodes in method parameters
- semantic analysis also uses `String[]` as a semantic type
- but the parser does not treat it exactly like `int`, `double`, and `boolean`
  in every grammar position

### Source positions are attached after node creation

`new_node(...)` initializes `line` and `column` to `0`.

Then the parser assigns the real source location through `SET_POS(...)`.

So the AST is built in two steps:

1. create the node
2. attach its source position

This matters because semantic errors later use the node's stored location, not
the lexer's current position.

## Does Semantic Analysis Change The AST?

Yes, but only in a limited way.

Semantic analysis in `src/semantics.c` does not:

- add new syntax nodes
- remove nodes
- move children around
- change a node's `category`

Semantic analysis does:

- clear old annotations with `clear_annotations(...)`
- resolve identifier and expression types
- write annotations onto existing nodes with `set_annotation(...)`

Examples of semantic changes:

- `Natural(1)` gets annotation `int`
- `Decimal(3.14)` gets annotation `double`
- `Identifier(x)` may get annotation `int`
- `Add` may get annotation `int` or `double`
- `Call` gets annotated with the method return type
- the callee `Identifier` inside a `Call` gets annotated with the resolved
  formal signature such as `(int,double)`

Example before semantic analysis:

```text
Assign
..Identifier(a)
..Add
....Identifier(b)
....Natural(1)
```

Example after semantic analysis:

```text
Assign - int
..Identifier(a) - int
..Add - int
....Identifier(b) - int
....Natural(1) - int
```

So the best way to say it is:

- parsing changes the AST structure
- semantic analysis changes the AST annotations

## Practical Reading Order

If you want to follow the code in the same order the compiler uses it, a good
reading path is:

1. `src/ast.h` for the node structure and categories
2. `src/ast.c` for the low-level tree-building helpers
3. `src/java_compiler.y` for the real tree shape chosen by the grammar
4. `src/semantics.c` for the annotation phase over that tree

That order makes it much easier to separate:

- who builds the AST
- who only reads it
- who enriches it with semantic meaning

#ifndef _AST_H
#define _AST_H

enum category {
    Program,
    FieldDecl,
    VarDecl,

    MethodDecl,
    MethodHeader,
    MethodParams,
    ParamDecl,
    MethodBody,

    Block,
    If,
    While,
    Return,
    Print,
    ParseArgs,
    Assign,
    Call,

    Or,
    And,
    Eq,
    Ne,
    Lt,
    Gt,
    Le,
    Ge,
    Add,
    Sub,
    Mul,
    Div,
    Mod,
    Lshift,
    Rshift,
    Xor,
    Not,
    Minus,
    Plus,
    Length,

    Bool,
    BoolLit,
    Double,
    Decimal,
    Identifier,
    Int,
    Natural,
    StrLit,
    StringArray,
    Void
};

struct node {
    enum category category;
    char *token;
    int line;
    int column;
    char *annotation;
    struct node_list *children;
};

struct node_list {
    struct node *node;
    struct node_list *next;
};

struct node *new_node(enum category category, char *token);

void add_child(struct node *parent, struct node *child);

struct node *adopt2(enum category c, struct node *a, struct node *b);

struct node *adopt1(enum category c, struct node *a);

struct node_list *new_list(struct node *node);

struct node_list *append_list(struct node_list *list, struct node *node);

struct node_list *join_lists(struct node_list *a, struct node_list *b);

struct node *copy_leaf_node(struct node *node);

struct node *get_child(struct node *node, int index);

void add_children(struct node *parent, struct node_list *list);

void set_annotation(struct node *node, const char *annotation);

void print_tree(struct node *node, int depth);

int child_count(struct node *node);

char *category_name(enum category category);

#endif

#ifndef _SEMANTICS_H
#define _SEMANTICS_H

#include "ast.h"

/* ---- Public types shared with code generator ---- */

enum semantic_type {
    TYPE_INT,
    TYPE_DOUBLE,
    TYPE_BOOLEAN,
    TYPE_STRING_ARRAY,
    TYPE_VOID,
    TYPE_UNDEF
};

enum symbol_kind {
    SYMBOL_FIELD,
    SYMBOL_METHOD,
    SYMBOL_PARAM,
    SYMBOL_LOCAL,
    SYMBOL_RETURN
};

struct table_entry {
    char *name;
    enum semantic_type type;
    enum symbol_kind kind;
    int in_scope;
    char *llvm_name;            /* set by codegen: "%x", "@x", etc. */
    struct table_entry *next;
};

struct method_info {
    struct node *body_node;
    char *name;
    enum semantic_type return_type;
    int param_count;
    enum semantic_type *param_types;
    char *signature;
    int show_table;
    int can_resolve_calls;
    struct table_entry *entries;
    struct table_entry *entries_tail;
    struct method_info *next;
};

struct class_symbol {
    char *name;
    enum symbol_kind kind;
    enum semantic_type type;
    int param_count;
    enum semantic_type *param_types;
    char *signature;
    char *llvm_name;            /* set by codegen: "@field" or "@method" */
    struct class_symbol *next;
};

/* ---- Existing API ---- */

int check_program(struct node *program);

void show_symbol_table(void);

void print_annotated_tree(struct node *node, int depth);

/* ---- Getters used by codegen ---- */

const char *get_class_name(void);
struct class_symbol *get_class_symbols(void);
struct method_info *get_methods(void);
const char *type_name_str(enum semantic_type type);

#endif

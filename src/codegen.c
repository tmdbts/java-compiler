#include "codegen.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

/* ---- Counters for unique LLVM names ---- */

static int reg_counter = 0;
static int label_counter = 0;

static void reset_counters(void) {
    reg_counter = 0;
    label_counter = 0;
}

/* Returns next register number (caller composes the "%N" string).
 * Marked __attribute__((unused)) until later phases consume it. */
__attribute__((unused))
static int next_reg(void) {
    return ++reg_counter;
}

__attribute__((unused))
static int next_label(void) {
    return ++label_counter;
}

/* ---- Type helpers ---- */

/* Maps a semantic type to its LLVM IR primitive type. */
static const char *llvm_type(enum semantic_type t) {
    switch (t) {
        case TYPE_INT:          return "i32";
        case TYPE_DOUBLE:       return "double";
        case TYPE_BOOLEAN:      return "i1";
        case TYPE_STRING_ARRAY: return "i8**";
        case TYPE_VOID:         return "void";
        default:                return "i32"; /* should not happen post-Meta3 */
    }
}

/* Default zero value for each LLVM type, used for "ret" in empty bodies. */
static const char *llvm_zero(enum semantic_type t) {
    switch (t) {
        case TYPE_INT:     return "0";
        case TYPE_DOUBLE:  return "0.0";
        case TYPE_BOOLEAN: return "0";
        default:           return "0";
    }
}

/* ---- Method header emission ---- */

/* Emits "define <ret> @<name>(<args>) {" for one method.
 * Special-cases main: must become "i32 @main(i32 %argc, i8** %argv)". */
static void emit_method_header(struct method_info *m) {
    int is_main = (strcmp(m->name, "main") == 0);

    if (is_main) {
        /* Juc main returns void but LLVM main must return i32. */
        printf("define i32 @main(i32 %%argc, i8** %%argv) {\n");
        return;
    }

    printf("define %s @%s(", llvm_type(m->return_type), m->name);

    /* Parameters: emit "<type> %arg_<name>" separated by commas. */
    struct table_entry *e;
    int first = 1;
    for (e = m->entries; e != NULL; e = e->next) {
        if (e->kind != SYMBOL_PARAM) continue;
        if (!first) printf(", ");
        printf("%s %%arg_%s", llvm_type(e->type), e->name);
        first = 0;
    }

    printf(") {\n");
}

/* Emits a default "ret" for a method with empty body. */
static void emit_default_return(struct method_info *m) {
    int is_main = (strcmp(m->name, "main") == 0);

    if (is_main) {
        printf("    ret i32 0\n");
        return;
    }

    if (m->return_type == TYPE_VOID) {
        printf("    ret void\n");
    } else {
        printf("    ret %s %s\n",
               llvm_type(m->return_type), llvm_zero(m->return_type));
    }
}

/* ---- Top-level entry point ---- */

void generate_code(struct node *program) {
    if (program == NULL) return;

    /* Header: external declarations we will need. */
    printf("; ModuleID = '%s'\n", get_class_name());
    printf("\n");
    printf("declare i32 @printf(i8*, ...)\n");
    printf("declare i32 @atoi(i8*)\n");
    printf("\n");

    /* One LLVM function per Juc method. */
    struct method_info *m;
    for (m = get_methods(); m != NULL; m = m->next) {
        reset_counters();
        emit_method_header(m);
        printf("entry:\n");
        emit_default_return(m);
        printf("}\n\n");
    }
}

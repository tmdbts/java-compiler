#ifndef _SEMANTICS_H
#define _SEMANTICS_H

#include "ast.h"

int check_program(struct node *program);

void show_symbol_table(void);

void print_annotated_tree(struct node *node, int depth);

#endif

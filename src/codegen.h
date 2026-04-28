#ifndef _CODEGEN_H
#define _CODEGEN_H

#include "ast.h"
#include "semantics.h"

/* Entry point: generate LLVM IR for the given program AST.
 * Assumes check_program() was already called and produced no errors. */
void generate_code(struct node *program);

#endif

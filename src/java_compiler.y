%{
#include <stdio.h>
#include "ast.h"

extern int yylex(void);
void yyerror(char *message);
extern char *yytext;

extern int token_line;
extern int token_column;
extern int line_number;
extern int column_number;
extern int was_last_strlit;
extern char string_buffer[];
extern int has_error;

#define SET_POS(node, location)               \
    do {                                      \
        (node)->line = (location).first_line; \
        (node)->column = (location).first_column; \
    } while (0)

struct node *root = NULL;
%}

%union {
	char *value;
    struct node *node;
    struct node_list *list;
}

%locations

%token<value> IDENTIFIER STRINGLIT DECIMAL BOOLLIT RESERVED NATURAL
%token ASSIGN PLUS MINUS STAR DIV MOD EQ NE LT LE GT GE NOT AND OR XOR
%token STRING RBRACE LBRACE COMMA SEMICOLON BOOL ARROW
%token RPAR LPAR RSQ LSQ RSHIFT LSHIFT PUBLIC RETURN STATIC VOID 
%token INT CLASS DOTLENGTH DOUBLE IF ELSE PRINT PARSEINT WHILE

%right ASSIGN
%right NOT 

%nonassoc LOWER_THAN_ELSE
%nonassoc ELSE

%type <node> Program MethodDecl Type
%type <node> MethodHeader MethodBody 
%type <node> Statement OptExpr PrintArg MethodInvocation
%type <node> Assignment ParseArgs Expr AssignExpr OrExpr
%type <node> XorExpr AndExpr EqExpr RelExpr ShiftExpr AddExpr MulExpr
%type <node> UnaryExpr PrimaryExpr

// %type <list> ArgList OptArgList IdentifierList ClassBody StatementList 
// %type <list> VarDecl MethodBodyItem MethodBodyItems FormalParamsTail FieldDecl

%type <list> ClassBody ClassMember FieldDecl VarDecl MethodBodyItem 
%type <list> MethodBodyItems IdentifierList StatementList ArgList OptArgList 
%type <list> OptFormalParams FormalParams FormalParamsTail

%%

Program
    : CLASS IDENTIFIER LBRACE ClassBody RBRACE 
        {
            struct node *class_id = new_node(Identifier, $2);
            root = new_node(Program, NULL);
            SET_POS(root, @1);
            SET_POS(class_id, @2);
            add_child(root, class_id);
            add_children(root, $4);

            $$ = root;
        }
    ;

ClassBody
    : /* empty */ { $$ = NULL; }
    | ClassBody ClassMember { $$ = join_lists($1, $2); }
    ;

ClassMember
    : MethodDecl { $$ = new_list($1); }
    | FieldDecl  { $$ = $1; }
    | SEMICOLON  { $$ = NULL; }
    ;

MethodDecl
    : PUBLIC STATIC MethodHeader MethodBody 
        {
            $$ = new_node(MethodDecl, NULL);
            SET_POS($$, @1);
            add_child($$, $3);
            add_child($$, $4);
        }
    ;

FieldDecl
    : PUBLIC STATIC Type IdentifierList SEMICOLON
        {
            $$ = NULL;
            struct node_list *current = $4;

            while (current != NULL) {
                struct node *decl = new_node(FieldDecl, NULL);
                SET_POS(decl, @1);
                add_child(decl, copy_leaf_node($3));
                add_child(decl, current->node);
                $$ = append_list($$, decl);
                current = current->next;
            }
        }
    | error SEMICOLON { $$ = NULL; }
    ;

Type
    : BOOL
        {
            $$ = new_node(Bool, NULL);
            SET_POS($$, @1);
        }
    | INT
        {
            $$ = new_node(Int, NULL);
            SET_POS($$, @1);
        }
    | DOUBLE
        {
            $$ = new_node(Double, NULL);
            SET_POS($$, @1);
        }
    ;

MethodHeader
    : Type IDENTIFIER LPAR OptFormalParams RPAR 
        {
            struct node *id = new_node(Identifier, $2);
            struct node *params = new_node(MethodParams, NULL);
            $$ = new_node(MethodHeader, NULL);
            SET_POS($$, @1);
            SET_POS(id, @2);
            SET_POS(params, @3);
            add_child($$, $1);
            add_child($$, id);
            add_children(params, $4);
            add_child($$, params);
        }
    | VOID IDENTIFIER LPAR OptFormalParams RPAR
        {
            struct node *type = new_node(Void, NULL);
            struct node *id = new_node(Identifier, $2);
            struct node *params = new_node(MethodParams, NULL);
            $$ = new_node(MethodHeader, NULL);
            SET_POS($$, @1);
            SET_POS(type, @1);
            SET_POS(id, @2);
            SET_POS(params, @3);
            add_child($$, type);
            add_child($$, id);
            add_children(params, $4);
            add_child($$, params);
        }
    ;

OptFormalParams
    : /* empty */  { $$ = NULL; }
    | FormalParams { $$ = $1; }
    ;

FormalParams
    : Type IDENTIFIER FormalParamsTail
        {
            struct node *id = new_node(Identifier, $2);
            struct node *param = new_node(ParamDecl, NULL);
            SET_POS(param, @1);
            SET_POS(id, @2);
            add_child(param, $1);
            add_child(param, id);

            $$ = new_list(param);
            $$ = join_lists($$, $3);
        }
    | STRING LSQ RSQ IDENTIFIER
        {
            struct node *type = new_node(StringArray, NULL);
            struct node *id = new_node(Identifier, $4);
            struct node *param = new_node(ParamDecl, NULL);
            SET_POS(param, @1);
            SET_POS(type, @1);
            SET_POS(id, @4);
            add_child(param, type);
            add_child(param, id);

            $$ = new_list(param);
        }
    ;

FormalParamsTail
    : /* empty */ { $$ = NULL; }
    | FormalParamsTail COMMA Type IDENTIFIER
        {
            struct node *id = new_node(Identifier, $4);
            struct node *param = new_node(ParamDecl, NULL);
            SET_POS(param, @3);
            SET_POS(id, @4);
            add_child(param, $3);
            add_child(param, id);

            $$ = append_list($1, param);
        }
    ;

MethodBody
    : LBRACE MethodBodyItems RBRACE 
        {
            $$ = new_node(MethodBody, NULL);
            SET_POS($$, @1);
            add_children($$, $2);
        }
    ;

MethodBodyItems
    : /* empty */                    { $$ = NULL; }
    | MethodBodyItems MethodBodyItem { $$ = join_lists($1, $2); }
    ;

MethodBodyItem
    : VarDecl   { $$ = $1; }
    | Statement { $$ = new_list($1); }
    ;

VarDecl
    : Type IdentifierList SEMICOLON 
        {
            $$ = NULL;
            struct node_list *current = $2;

            while (current != NULL) {
                struct node *decl = new_node(VarDecl, NULL);
                SET_POS(decl, @1);
                add_child(decl, copy_leaf_node($1));
                add_child(decl, current->node);

                $$ = append_list($$, decl);
                current = current->next;
            }
        }
    ;

IdentifierList
    : IDENTIFIER
        {
            struct node *id = new_node(Identifier, $1);
            SET_POS(id, @1);
            $$ = new_list(id);
        }
    | IdentifierList COMMA IDENTIFIER
        {
            struct node *id = new_node(Identifier, $3);
            SET_POS(id, @3);
            $$ = append_list($1, id);
        }
    ;

Statement
    : LBRACE StatementList RBRACE
        {
            if ($2 == NULL) {
                $$ = NULL;
            } else if ($2->next == NULL) {
                $$ = $2->node;
            } else {
                $$ = new_node(Block, NULL);
                SET_POS($$, @1);
                add_children($$, $2);
            }
        }
    | IF LPAR Expr RPAR Statement %prec LOWER_THAN_ELSE
        {
            struct node *empty_block = new_node(Block, NULL);
            $$ = new_node(If, NULL);
            SET_POS($$, @1);
            SET_POS(empty_block, @1);
            add_child($$, $3);
            if ($5 != NULL) {
                add_child($$, $5);
            } else {
                struct node *then_block = new_node(Block, NULL);
                SET_POS(then_block, @5);
                add_child($$, then_block);
            }
            add_child($$, empty_block);
        }
    | IF LPAR Expr RPAR Statement ELSE Statement
        {
            $$ = new_node(If, NULL);
            SET_POS($$, @1);
            add_child($$, $3);
            if ($5 != NULL) {
                add_child($$, $5);
            } else {
                struct node *then_block = new_node(Block, NULL);
                SET_POS(then_block, @5);
                add_child($$, then_block);
            }
            if ($7 != NULL) {
                add_child($$, $7);
            } else {
                struct node *else_block = new_node(Block, NULL);
                SET_POS(else_block, @7);
                add_child($$, else_block);
            }
        }
    | WHILE LPAR Expr RPAR Statement
        {
            $$ = new_node(While, NULL);
            SET_POS($$, @1);
            add_child($$, $3);
            if ($5 != NULL) {
                add_child($$, $5);
            } else {
                struct node *body = new_node(Block, NULL);
                SET_POS(body, @5);
                add_child($$, body);
            }
        }
    | RETURN OptExpr SEMICOLON 
        {
            $$ = new_node(Return, NULL);
            SET_POS($$, @1);
            add_child($$, $2);
        }
    | SEMICOLON                          { $$ = NULL; }
    | MethodInvocation SEMICOLON         { $$ = $1; }
    | Assignment SEMICOLON               { $$ = $1; }
    | ParseArgs SEMICOLON                { $$ = $1; }
    | PRINT LPAR PrintArg RPAR SEMICOLON
        {
            $$ = adopt1(Print, $3);
            SET_POS($$, @1);
        }
    | error SEMICOLON                    { $$ = NULL; }
    ;

StatementList
    : /* empty */             { $$ = NULL; }
    | StatementList Statement { $$ = append_list($1, $2); }
    ;

OptExpr
    : /* empty */ { $$ = NULL; }
    | Expr { $$ = $1; }
    ;

PrintArg
    : Expr { $$ = $1; }
    | STRINGLIT
        {
            $$ = new_node(StrLit, $1);
            SET_POS($$, @1);
        }
    ;

MethodInvocation
    : IDENTIFIER LPAR OptArgList RPAR 
        {
            struct node *id = new_node(Identifier, $1);
            $$ = new_node(Call, NULL);
            SET_POS($$, @1);
            SET_POS(id, @1);
            add_child($$, id);
            add_children($$, $3);
        }
    | IDENTIFIER LPAR error RPAR { $$ = NULL; }
    ;

OptArgList
    : /* empty */ { $$ = NULL; }
    | ArgList     { $$ = $1; }
    ;

ArgList
    : Expr               { $$ = new_list($1); }
    | ArgList COMMA Expr { $$ = append_list($1, $3); }
    ;

Assignment
    : IDENTIFIER ASSIGN Expr 
        {
            struct node *id = new_node(Identifier, $1);
            $$ = new_node(Assign, NULL);
            SET_POS($$, @2);
            SET_POS(id, @1);
            add_child($$, id);
            add_child($$, $3);
        }
    ;

ParseArgs
    : PARSEINT LPAR IDENTIFIER LSQ Expr RSQ RPAR 
        {
            struct node *id = new_node(Identifier, $3);
            $$ = new_node(ParseArgs, NULL);
            SET_POS($$, @1);
            SET_POS(id, @3);
            add_child($$, id);
            add_child($$, $5);
        }
    | PARSEINT LPAR error RPAR { $$ = NULL; }
    ;

Expr
    : AssignExpr { $$ = $1; }
    ;

AssignExpr
    : IDENTIFIER ASSIGN AssignExpr 
        {
            struct node *id = new_node(Identifier, $1);
            $$ = new_node(Assign, NULL);
            SET_POS($$, @2);
            SET_POS(id, @1);
            add_child($$, id);
            add_child($$, $3);
        }
    | OrExpr { $$ = $1; }
    ;

OrExpr
    : OrExpr OR XorExpr
        {
            $$ = adopt2(Or, $1, $3);
            SET_POS($$, @2);
        }
    | XorExpr            { $$ = $1; }
    ;

XorExpr
    : XorExpr XOR AndExpr
        {
            $$ = adopt2(Xor, $1, $3);
            SET_POS($$, @2);
        }
    | AndExpr             { $$ = $1; }
    ;

AndExpr
    : AndExpr AND EqExpr
        {
            $$ = adopt2(And, $1, $3);
            SET_POS($$, @2);
        }
    | EqExpr             { $$ = $1; }
    ;

EqExpr
    : EqExpr EQ RelExpr
        {
            $$ = adopt2(Eq, $1, $3);
            SET_POS($$, @2);
        }
    | EqExpr NE RelExpr
        {
            $$ = adopt2(Ne, $1, $3);
            SET_POS($$, @2);
        }
    | RelExpr           { $$ = $1; }
    ;

RelExpr
    : RelExpr LT ShiftExpr
        {
            $$ = adopt2(Lt, $1, $3);
            SET_POS($$, @2);
        }
    | RelExpr GT ShiftExpr
        {
            $$ = adopt2(Gt, $1, $3);
            SET_POS($$, @2);
        }
    | RelExpr LE ShiftExpr
        {
            $$ = adopt2(Le, $1, $3);
            SET_POS($$, @2);
        }
    | RelExpr GE ShiftExpr
        {
            $$ = adopt2(Ge, $1, $3);
            SET_POS($$, @2);
        }
    | ShiftExpr            { $$ = $1; }
    ;

ShiftExpr
    : ShiftExpr LSHIFT AddExpr
        {
            $$ = adopt2(Lshift, $1, $3);
            SET_POS($$, @2);
        }
    | ShiftExpr RSHIFT AddExpr
        {
            $$ = adopt2(Rshift, $1, $3);
            SET_POS($$, @2);
        }
    | AddExpr                  { $$ = $1; }
    ;

AddExpr
    : AddExpr PLUS MulExpr
        {
            $$ = adopt2(Add, $1, $3);
            SET_POS($$, @2);
        }
    | AddExpr MINUS MulExpr
        {
            $$ = adopt2(Sub, $1, $3);
            SET_POS($$, @2);
        }
    | MulExpr { $$ = $1; }
    ;

MulExpr
    : MulExpr STAR UnaryExpr
        {
            $$ = adopt2(Mul, $1, $3);
            SET_POS($$, @2);
        }
    | MulExpr DIV UnaryExpr
        {
            $$ = adopt2(Div, $1, $3);
            SET_POS($$, @2);
        }
    | MulExpr MOD UnaryExpr
        {
            $$ = adopt2(Mod, $1, $3);
            SET_POS($$, @2);
        }
    | UnaryExpr              { $$ = $1; }
    ;

UnaryExpr
    : MINUS UnaryExpr
        {
            $$ = adopt1(Minus, $2);
            SET_POS($$, @1);
        }
    | PLUS UnaryExpr
        {
            $$ = adopt1(Plus, $2);
            SET_POS($$, @1);
        }
    | NOT UnaryExpr
        {
            $$ = adopt1(Not, $2);
            SET_POS($$, @1);
        }
    | PrimaryExpr     { $$ = $1; }
    ;

PrimaryExpr
    : LPAR Expr RPAR       { $$ = $2; }
    | LPAR error RPAR      { $$ = NULL; }
    | MethodInvocation     { $$ = $1; }
    | ParseArgs            { $$ = $1; }
    | IDENTIFIER
        {
            $$ = new_node(Identifier, $1);
            SET_POS($$, @1);
        }
    | IDENTIFIER DOTLENGTH
        {
            struct node *id = new_node(Identifier, $1);
            $$ = adopt1(Length, id);
            SET_POS(id, @1);
            SET_POS($$, @2);
        }
    | NATURAL
        {
            $$ = new_node(Natural, $1);
            SET_POS($$, @1);
        }
    | DECIMAL
        {
            $$ = new_node(Decimal, $1);
            SET_POS($$, @1);
        }
    | BOOLLIT
        {
            $$ = new_node(BoolLit, $1);
            SET_POS($$, @1);
        }
    ;

%%

void yyerror(char *message) {
    has_error = 1;

    if (yytext[0] == '\0'){
        printf("Line %d, col %d: %s: \n", line_number, column_number, message);

        return;
    }

    if (was_last_strlit) {
        printf("Line %d, col %d: %s: \"%s\"\n", token_line, token_column, message, string_buffer);
        was_last_strlit = 0; // Reset the flag for the next error
        return; // Skip error reporting for unterminated string literals
    }

    printf("Line %d, col %d: %s: %s\n", token_line, token_column, message, yytext);
}

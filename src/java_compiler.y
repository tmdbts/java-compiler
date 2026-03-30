%{
#include <stdio.h>
#include "ast.h"

extern int yylex(void);
void yyerror(char *message);
extern char *yytext;

extern int line_number;
extern int column_number;

struct node *root = NULL;
%}

%union {
	char *value;
    struct node *node;
    struct node_list *list;
}

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
            root = new_node(Program, NULL);
            add_child(root, new_node(Identifier, $2));
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
                add_child(decl, copy_node($3));
                add_child(decl, current->node);
                $$ = append_list($$, decl);
                current = current->next;
            }
        }
    | error SEMICOLON { $$ = NULL; }
    ;

Type
    : BOOL   { $$ = new_node(Bool, NULL); }
    | INT    { $$ = new_node(Int, NULL); }
    | DOUBLE { $$ = new_node(Double, NULL); }
    ;

MethodHeader
    : Type IDENTIFIER LPAR OptFormalParams RPAR 
        {
            $$ = new_node(MethodHeader, NULL);
            add_child($$, $1);
            add_child($$, new_node(Identifier, $2));

            struct node *params = new_node(MethodParams, NULL);
            add_children(params, $4);
            add_child($$, params);
        }
    | VOID IDENTIFIER LPAR OptFormalParams RPAR
        {
            $$ = new_node(MethodHeader, NULL);
            add_child($$, new_node(Void, NULL));
            add_child($$, new_node(Identifier, $2));

            struct node *params = new_node(MethodParams, NULL);
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
            struct node *param = new_node(ParamDecl, NULL);
            add_child(param, $1);
            add_child(param, new_node(Identifier, $2));

            $$ = new_list(param);
            $$ = join_lists($$, $3);
        }
    | STRING LSQ RSQ IDENTIFIER
        {
            struct node *param = new_node(ParamDecl, NULL);
            add_child(param, new_node(StringArray, NULL));
            add_child(param, new_node(Identifier, $4));

            $$ = new_list(param);
        }
    ;

FormalParamsTail
    : /* empty */ { $$ = NULL; }
    | FormalParamsTail COMMA Type IDENTIFIER
        {
            struct node *param = new_node(ParamDecl, NULL);
            add_child(param, $3);
            add_child(param, new_node(Identifier, $4));

            $$ = append_list($1, param);
        }
    ;

MethodBody
    : LBRACE MethodBodyItems RBRACE 
        {
            $$ = new_node(MethodBody, NULL);
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
                add_child(decl, copy_node($1));
                add_child(decl, current->node);

                $$ = append_list($$, decl);
                current = current->next;
            }
        }
    ;

IdentifierList
    : IDENTIFIER { $$ = new_list(new_node(Identifier, $1)); }
    | IdentifierList COMMA IDENTIFIER
        {
            $$ = append_list($1, new_node(Identifier, $3));
        }
    ;

Statement
    : LBRACE StatementList RBRACE
        {
            if ($2 == NULL) {
              $$ = new_node(Block, NULL);
          } else if ($2->next == NULL) {
              $$ = $2->node;
          } else {
              $$ = new_node(Block, NULL);
              add_children($$, $2);
          }
        }
    | IF LPAR Expr RPAR Statement %prec LOWER_THAN_ELSE
        {
            $$ = new_node(If, NULL);
              add_child($$, $3);
              add_child($$, $5);
              add_child($$, new_node(Block, NULL));
        }
    | IF LPAR Expr RPAR Statement ELSE Statement
        {
            $$ = new_node(If, NULL);
            add_child($$, $3);
            add_child($$, $5);
            add_child($$, $7);
        }
    | WHILE LPAR Expr RPAR Statement
        {
            $$ = new_node(While, NULL);
            add_child($$, $3);
            add_child($$, $5);
        }
    | RETURN OptExpr SEMICOLON 
        {
            $$ = new_node(Return, NULL);
            add_child($$, $2);
        }
    | SEMICOLON                          { $$ = new_node(Block, NULL); }
    | MethodInvocation SEMICOLON         { $$ = $1; }
    | Assignment SEMICOLON               { $$ = $1; }
    | ParseArgs SEMICOLON                { $$ = $1; }
    | PRINT LPAR PrintArg RPAR SEMICOLON { $$ = adopt1(Print, $3); }
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
    | STRINGLIT { $$ = new_node(StrLit, $1); }
    ;

MethodInvocation
    : IDENTIFIER LPAR OptArgList RPAR 
        {
            $$ = new_node(Call, NULL);
            add_child($$, new_node(Identifier, $1));
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
            $$ = new_node(Assign, NULL);
            add_child($$, new_node(Identifier, $1));
            add_child($$, $3);
        }
    ;

ParseArgs
    : PARSEINT LPAR IDENTIFIER LSQ Expr RSQ RPAR 
        {
            $$ = new_node(ParseArgs, NULL);
            add_child($$, new_node(Identifier, $3));
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
            $$ = new_node(Assign, NULL);
            add_child($$, new_node(Identifier, $1));
            add_child($$, $3);
        }
    | OrExpr { $$ = $1; }
    ;

OrExpr
    : OrExpr OR XorExpr  { $$ = adopt2(Or, $1, $3); }
    | XorExpr            { $$ = $1; }
    ;

XorExpr
    : XorExpr XOR AndExpr { $$ = adopt2(Xor, $1, $3); }
    | AndExpr             { $$ = $1; }
    ;

AndExpr
    : AndExpr AND EqExpr { $$ = adopt2(And, $1, $3); }
    | EqExpr             { $$ = $1; }
    ;

EqExpr
    : EqExpr EQ RelExpr { $$ = adopt2(Eq, $1, $3); }
    | EqExpr NE RelExpr { $$ = adopt2(Ne, $1, $3); }
    | RelExpr           { $$ = $1; }
    ;

RelExpr
    : RelExpr LT ShiftExpr { $$ = adopt2(Lt, $1, $3); }
    | RelExpr GT ShiftExpr { $$ = adopt2(Gt, $1, $3); }
    | RelExpr LE ShiftExpr { $$ = adopt2(Le, $1, $3); }
    | RelExpr GE ShiftExpr { $$ = adopt2(Ge, $1, $3); }
    | ShiftExpr            { $$ = $1; }
    ;

ShiftExpr
    : ShiftExpr LSHIFT AddExpr { $$ = adopt2(Lshift, $1, $3); }
    | ShiftExpr RSHIFT AddExpr { $$ = adopt2(Rshift, $1, $3); }
    | AddExpr                  { $$ = $1; }
    ;

AddExpr
    : AddExpr PLUS MulExpr  { $$ = adopt2(Add, $1, $3); }
    | AddExpr MINUS MulExpr { $$ = adopt2(Sub, $1, $3); }
    | MulExpr { $$ = $1; }
    ;

MulExpr
    : MulExpr STAR UnaryExpr { $$ = adopt2(Mul, $1, $3); }
    | MulExpr DIV UnaryExpr  { $$ = adopt2(Div, $1, $3); }
    | MulExpr MOD UnaryExpr  { $$ = adopt2(Mod, $1, $3); }
    | UnaryExpr              { $$ = $1; }
    ;

UnaryExpr
    : MINUS UnaryExpr { $$ = adopt1(Minus, $2); }
    | PLUS UnaryExpr  { $$ = adopt1(Plus, $2); }
    | NOT UnaryExpr   { $$ = adopt1(Not, $2); }
    | PrimaryExpr     { $$ = $1; }
    ;

PrimaryExpr
    : LPAR Expr RPAR       { $$ = $2; }
    | LPAR error RPAR      { $$ = NULL; }
    | MethodInvocation     { $$ = $1; }
    | ParseArgs            { $$ = $1; }
    | IDENTIFIER           { $$ = new_node(Identifier, $1); }
    | IDENTIFIER DOTLENGTH { $$ = adopt1(Length, new_node(Identifier, $1)); }
    | NATURAL              { $$ = new_node(Natural, $1); }
    | DECIMAL              { $$ = new_node(Decimal, $1); }
    | BOOLLIT              { $$ = new_node(BoolLit, $1); }
    ;

%%

void yyerror(char *message) {
    printf("Line %d, col %d: %s: %s\n", line_number, column_number, message, yytext);
}

%{
#include <stdio.h>
extern int yylex(void);
void yyerror(char *);
extern char *yytext;
%}

%token<value> IDENTIFIER STRINGLIT NATURAL DECIMAL BOOLLIT RESERVED
%token ASSIGN PLUS MINUS STAR DIV MOD EQ NE LT LE GT GE NOT AND OR XOR
%token STRING RBRACE LBRACE LPAREN RPAREN COMMA SEMICOLON BOOL ARROW
%token RPAR LPAR RSQ LSQ RSHIFT LSHIFT PUBLIC RETURN STATIC VOID 
%token INT CLASS DOTLENGTH DOUBLE IF ELSE THEN PRINT PARSEINT WHILE

%left PLUS MINUS DIV MOD STAR
%left LOW

%union {
	char *value;
    int natural;
}


%%

Program:; 

%%

void yyerror(char *error) {
    printf("%s '%s'\n", error, yytext);
}


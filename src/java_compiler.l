%{
    #include "y.tab.h"
    #include "ast.h"
    #include "semantics.h"
    #include <stdio.h>
    #include <stdlib.h>
    #include <string.h>

    extern struct node *root;

    int yyparse(void);

    #define PASS_TOKEN() yylval.value = strdup(yytext);
    #define PASS_TOKEN_STRLIT() yylval.value = strdup(string_buffer);
    #define UPDATE_TOKEN_POSITION()                                           \
        do {                                                                  \
            token_line = line_number;                                         \
            token_column = column_number;                                     \
            yylloc.first_line = token_line;                                   \
            yylloc.first_column = token_column;                               \
            yylloc.last_line = token_line;                                    \
            yylloc.last_column = token_column;                                \
        } while (0)
    #define UPDATE_COLUMN() column_number += yyleng;

    int token_line = 1;
    int token_column = 1;
    int line_number = 1;
    int column_number = 1;
    int was_last_strlit = 0;

    int block_comment_line = 1;
    int block_comment_column = 1;

    int string_start_line = 1;
    int string_start_column = 1;

    int string_has_error = 0;
    int has_error = 0;
    int has_lexical_error = 0;

    int lex_flag = 0;

    char string_buffer[1024] = "\0";
%}

digit           [0-9]
dec_part        {digit}([0-9_]*{digit})?
exponent        [eE][+-]?{dec_part}
int_literal     0|[1-9]([0-9_]*[0-9])?
float_literal   ({dec_part}"."({dec_part})?({exponent})?)|("."{dec_part}({exponent})?)|({dec_part}{exponent})
character    [a-zA-Z]
open_block_comment   "/*"
close_block_comment  "*/"
reserved_keywords "++"|"--"|"null"|"this"|"new"|"abstract"|"assert"|"break"|"byte"|"case"|"char"|"catch"|"const"|"continue"|"default"|"do"|"enum"|"extends"|"final"|"finally"|"float"|"for"|"goto"|"implements"|"import"|"Integer"|"instanceof"|"interface"|"long"|"native"|"package"|"private"|"protected"|"short"|"strict"|"strictfp"|"super"|"switch"|"System"|"synchronized"|"throw"|"throws"|"transient"|"try"|"volatile"|"open"|"module"|"transitive"|"exports"|"opens"

%X BLOCK_COMMENT STRLIT

%%
\r\n|\r|\n   { line_number++; column_number = 1; }
[ \t\f]+     { UPDATE_COLUMN(); }

"//"[^\r\n]* { UPDATE_COLUMN(); }

{open_block_comment} {
block_comment_line = line_number;
block_comment_column = column_number;
was_last_strlit = 0;
UPDATE_COLUMN();
BEGIN(BLOCK_COMMENT);
}
<BLOCK_COMMENT>\r\n|\r|\n       { line_number++; column_number = 1; }
<BLOCK_COMMENT><<EOF>> {
has_lexical_error = 1;
printf("Line %d, col %d: unterminated comment\n",
block_comment_line, block_comment_column);
BEGIN(INITIAL);
}
<BLOCK_COMMENT>{close_block_comment} {
UPDATE_COLUMN();
BEGIN(INITIAL);
}
<BLOCK_COMMENT>. { UPDATE_COLUMN(); }

\" {
string_buffer[0] = '\0';
string_start_line = line_number;
string_start_column = column_number;
string_has_error = 0;
was_last_strlit = 0;
UPDATE_COLUMN();
BEGIN(STRLIT);
}

<STRLIT>\\[\"nrtf\\]    { strcat(string_buffer, yytext); UPDATE_COLUMN(); }

<STRLIT>\\\r\n|\\\r|\\\n {
has_lexical_error = 1;
printf("Line %d, col %d: invalid escape sequence (\\)\n", line_number, column_number);
string_has_error = 1;
printf("Line %d, col %d: unterminated string literal\n",
string_start_line, string_start_column);
string_buffer[0] = '\0';
line_number++;
column_number = 1;
BEGIN(INITIAL);
}
<STRLIT>\\ {
has_lexical_error = 1;
printf("Line %d, col %d: invalid escape sequence (%s)\n", line_number, column_number, yytext);
string_has_error = 1;
UPDATE_COLUMN();
}
<STRLIT>\\. {
has_lexical_error = 1;
printf("Line %d, col %d: invalid escape sequence (%s)\n", line_number, column_number, yytext);
string_has_error = 1;
UPDATE_COLUMN();
}
<STRLIT>\" {
if (!string_has_error && lex_flag) { printf("STRLIT(\"%s\")\n", string_buffer); }
token_line = string_start_line;
token_column = string_start_column;
yylloc.first_line = token_line;
yylloc.first_column = token_column;
yylloc.last_line = token_line;
yylloc.last_column = token_column;
if (!string_has_error && !lex_flag) { PASS_TOKEN_STRLIT(); }
was_last_strlit = 1;
UPDATE_COLUMN();
BEGIN(INITIAL);
if (!string_has_error) return STRINGLIT;
}
<STRLIT><<EOF>> {
has_lexical_error = 1;
printf("Line %d, col %d: unterminated string literal\n",
string_start_line, string_start_column);
string_buffer[0] = '\0';
BEGIN(INITIAL);
}
<STRLIT>\r\n|\r|\n {
has_lexical_error = 1;
printf("Line %d, col %d: unterminated string literal\n",
string_start_line, string_start_column);
string_buffer[0] = '\0';
line_number++;
column_number = 1;
BEGIN(INITIAL);
}

<STRLIT>.               { strncat(string_buffer, yytext, 1); UPDATE_COLUMN(); }

{float_literal} { if (lex_flag) printf("DECIMAL(%s)\n", yytext); 
                  was_last_strlit = 0;
                  UPDATE_TOKEN_POSITION();
                  UPDATE_COLUMN();
                  PASS_TOKEN();
                  return DECIMAL; }
{int_literal}   { if (lex_flag) printf("NATURAL(%s)\n", yytext); 
                  was_last_strlit = 0;
                  UPDATE_TOKEN_POSITION();
                  UPDATE_COLUMN(); 
                  PASS_TOKEN();
                  return NATURAL; }

"true"|"false"          { if(lex_flag) printf("BOOLLIT(%s)\n", yytext);  
                          was_last_strlit = 0;
                          UPDATE_TOKEN_POSITION();
                          UPDATE_COLUMN();
                          PASS_TOKEN();
                          return BOOLLIT; }
"&&"                   	{ if(lex_flag) printf("AND\n");
                          was_last_strlit = 0;
                          UPDATE_TOKEN_POSITION();
                          UPDATE_COLUMN();
                          return AND; }
"="                     { if(lex_flag) printf("ASSIGN\n");
                          was_last_strlit = 0;
                          UPDATE_TOKEN_POSITION();
                          UPDATE_COLUMN();
                          return ASSIGN; }
"*"                     { if(lex_flag) printf("STAR\n");
                          was_last_strlit = 0;
                          UPDATE_TOKEN_POSITION();
                          UPDATE_COLUMN();
                          return STAR; }
","                     { if(lex_flag) printf("COMMA\n");
                          was_last_strlit = 0;
                          UPDATE_TOKEN_POSITION();
                          UPDATE_COLUMN();
                          return COMMA; }
"/"                     { if(lex_flag) printf("DIV\n");
                          was_last_strlit = 0;
                          UPDATE_TOKEN_POSITION();
                          UPDATE_COLUMN();
                          return DIV; }
"=="                    { if(lex_flag) printf("EQ\n");
                          was_last_strlit = 0;
                          UPDATE_TOKEN_POSITION();
                          UPDATE_COLUMN();
                          return EQ; }
">="                    { if(lex_flag) printf("GE\n");
                          was_last_strlit = 0;
                          UPDATE_TOKEN_POSITION();
                          UPDATE_COLUMN();
                          return GE; }
">"                     { if(lex_flag) printf("GT\n");
                          was_last_strlit = 0;
                          UPDATE_TOKEN_POSITION();
                          UPDATE_COLUMN();
                          return GT; }
"{"                     { if(lex_flag) printf("LBRACE\n");
                          was_last_strlit = 0;
                          UPDATE_TOKEN_POSITION();
                          UPDATE_COLUMN();
                          return LBRACE; }
"<="                    { if(lex_flag) printf("LE\n");
                          was_last_strlit = 0;
                          UPDATE_TOKEN_POSITION();
                          UPDATE_COLUMN();
                          return LE; }
"("                     { if(lex_flag) printf("LPAR\n");
                          was_last_strlit = 0;
                          UPDATE_TOKEN_POSITION();
                          UPDATE_COLUMN();
                          return LPAR; }
"["                     { if(lex_flag) printf("LSQ\n");
                          was_last_strlit = 0;
                          UPDATE_TOKEN_POSITION();
                          UPDATE_COLUMN();
                          return LSQ; }
"<"                     { if(lex_flag) printf("LT\n");
                          was_last_strlit = 0;
                          UPDATE_TOKEN_POSITION();
                          UPDATE_COLUMN();
                          return LT; }
"-"                     { if(lex_flag) printf("MINUS\n");  
                          was_last_strlit = 0;
                          UPDATE_TOKEN_POSITION();
                          UPDATE_COLUMN();
                          return MINUS; }
"%"                     { if(lex_flag) printf("MOD\n");
                          was_last_strlit = 0;
                          UPDATE_TOKEN_POSITION();
                          UPDATE_COLUMN();
                          return MOD; }
"!="                    { if(lex_flag) printf("NE\n");
                          was_last_strlit = 0;
                          UPDATE_TOKEN_POSITION();
                          UPDATE_COLUMN();
                          return NE; }
"!"                     { if(lex_flag) printf("NOT\n");
                          was_last_strlit = 0;
                          UPDATE_TOKEN_POSITION();
                          UPDATE_COLUMN();
                          return NOT; }
"||"                    { if(lex_flag) printf("OR\n");
                          was_last_strlit = 0;
                          UPDATE_TOKEN_POSITION();
                          UPDATE_COLUMN();
                          return OR; }
"+"                     { if(lex_flag) printf("PLUS\n");
                          was_last_strlit = 0;
                          UPDATE_TOKEN_POSITION();
                          UPDATE_COLUMN();
                          return PLUS; }
"}"                     { if(lex_flag) printf("RBRACE\n");
                          was_last_strlit = 0;
                          UPDATE_TOKEN_POSITION();
                          UPDATE_COLUMN();
                          return RBRACE; }
")"                     { if(lex_flag) printf("RPAR\n");
                          was_last_strlit = 0;
                          UPDATE_TOKEN_POSITION();
                          UPDATE_COLUMN();
                          return RPAR; }
"]"                     { if(lex_flag) printf("RSQ\n");
                          was_last_strlit = 0;
                          UPDATE_TOKEN_POSITION();
                          UPDATE_COLUMN();
                          return RSQ; }
";"                     { if(lex_flag) printf("SEMICOLON\n");
                          was_last_strlit = 0;
                          UPDATE_TOKEN_POSITION();
                          UPDATE_COLUMN();
                          return SEMICOLON; }
"->"                    { if(lex_flag) printf("ARROW\n");
                          was_last_strlit = 0;
                          UPDATE_TOKEN_POSITION();
                          UPDATE_COLUMN();
                          return ARROW; }
"<<"                    { if(lex_flag) printf("LSHIFT\n");
                          was_last_strlit = 0;
                          UPDATE_TOKEN_POSITION();
                          UPDATE_COLUMN();
                          return LSHIFT; }
">>"                    { if(lex_flag) printf("RSHIFT\n");
                          was_last_strlit = 0;
                          UPDATE_TOKEN_POSITION();
                          UPDATE_COLUMN();
                          return RSHIFT; }
"^"                     { if(lex_flag) printf("XOR\n");  
                          was_last_strlit = 0;
                          UPDATE_TOKEN_POSITION();
                          UPDATE_COLUMN();
                          return XOR; }
"boolean"               { if(lex_flag) printf("BOOL\n");
                          was_last_strlit = 0;
                          UPDATE_TOKEN_POSITION();
                          UPDATE_COLUMN();
                          return BOOL; }
"class"                 { if(lex_flag) printf("CLASS\n");
                          was_last_strlit = 0;
                          UPDATE_TOKEN_POSITION();
                          UPDATE_COLUMN();
                          return CLASS; }
".length"               { if(lex_flag) printf("DOTLENGTH\n");
                          was_last_strlit = 0;
                          UPDATE_TOKEN_POSITION();
                          UPDATE_COLUMN();
                          return DOTLENGTH; }
"double"                { if(lex_flag) printf("DOUBLE\n");
                          was_last_strlit = 0;
                          UPDATE_TOKEN_POSITION();
                          UPDATE_COLUMN();
                          return DOUBLE; }
"else"                  { if(lex_flag) printf("ELSE\n");
                          was_last_strlit = 0;
                          UPDATE_TOKEN_POSITION();
                          UPDATE_COLUMN();
                          return ELSE; }
"if"                    { if(lex_flag) printf("IF\n"); 
                          was_last_strlit = 0;
                          UPDATE_TOKEN_POSITION();
                          UPDATE_COLUMN();
                          return IF; }
"int"                   { if(lex_flag) printf("INT\n");
                          was_last_strlit = 0;
                          UPDATE_TOKEN_POSITION();
                          UPDATE_COLUMN();
                          return INT; }
"System.out.print"     	{ if(lex_flag) printf("PRINT\n");
                          was_last_strlit = 0;
                          UPDATE_TOKEN_POSITION();
                          UPDATE_COLUMN();
                          return PRINT; }
"Integer.parseInt"      { if(lex_flag) printf("PARSEINT\n");
                          was_last_strlit = 0;
                          UPDATE_TOKEN_POSITION();
                          UPDATE_COLUMN();
                          return PARSEINT; }
"String"                { if(lex_flag) printf("STRING\n");  
                          was_last_strlit = 0;
                          UPDATE_TOKEN_POSITION();
                          UPDATE_COLUMN();
                          return STRING; }
"public"                { if(lex_flag) printf("PUBLIC\n");  
                          was_last_strlit = 0;
                          UPDATE_TOKEN_POSITION();
                          UPDATE_COLUMN();
                          return PUBLIC; }
"return"                { if(lex_flag) printf("RETURN\n");  
                          was_last_strlit = 0;
                          UPDATE_TOKEN_POSITION();
                          UPDATE_COLUMN();
                          return RETURN; }
"static"                { if(lex_flag) printf("STATIC\n");  
                          was_last_strlit = 0;
                          UPDATE_TOKEN_POSITION();
                          UPDATE_COLUMN();
                          return STATIC; }
"void"                  { if(lex_flag) printf("VOID\n");
                          was_last_strlit = 0;
                          UPDATE_TOKEN_POSITION();
                          UPDATE_COLUMN();
                          return VOID; }
"while"                 { if(lex_flag) printf("WHILE\n");  
                          was_last_strlit = 0;
                          UPDATE_TOKEN_POSITION();
                          UPDATE_COLUMN();
                          return WHILE; }

{reserved_keywords}     { if(lex_flag) { printf("RESERVED(%s)\n", yytext); }
                          was_last_strlit = 0;
                          UPDATE_TOKEN_POSITION();
                          UPDATE_COLUMN();
                          PASS_TOKEN();
                          return RESERVED; }

({character}|_|\$)({character}|_|\$|{digit})* {
if (lex_flag) { printf("IDENTIFIER(%s)\n", yytext); }
was_last_strlit = 0;
UPDATE_TOKEN_POSITION();
PASS_TOKEN();
UPDATE_COLUMN();
return IDENTIFIER;
}

. {
has_lexical_error = 1;
printf("Line %d, col %d: illegal character (%s)\n", line_number, column_number, yytext);
UPDATE_TOKEN_POSITION();
UPDATE_COLUMN();
}

%%

extern int yylex();
int main(int argc, char **argv) {
    if (argc >= 2 && (strcmp(argv[1], "-l") == 0 || strcmp(argv[1], "-e1") == 0)) {   
        lex_flag = 1;
        while (yylex()) {}

        return 0;
    }

    if (argc >= 2 && (strcmp(argv[1], "-t") == 0 || strcmp(argv[1], "-e2") == 0)) {
        yyparse();

        if (!has_error) print_tree(root, 0);

        return 0;
    }

    if (argc >= 2 && strcmp(argv[1], "-s") == 0) {
        yyparse();

        if (!has_error && !has_lexical_error) {
            check_program(root);
            show_symbol_table();
            printf("\n");
            print_annotated_tree(root, 0);
        }

        return 0;
    }

    if (argc >= 2 && strcmp(argv[1], "-e3") == 0) {
        yyparse();

        if (!has_error && !has_lexical_error) check_program(root);

        return 0;
    }

    yyparse();

    if (!has_error && !has_lexical_error) check_program(root);

    return 0;
}
int yywrap() {  /* called on EOF, return 1 to terminate */
    return 1;
}

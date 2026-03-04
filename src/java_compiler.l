%{
    int line_number = 1;
    int column_number = 1;

    char string_buffer[1024] = "\0";
%}
digit   [0-9]
character    [a-zA-Z]
open_comment   "/*"
close_comment  "*/"

%X COMMENT STRLIT

%%
{digit}+                { printf("NATURAL(%s)\n", yytext); }
{digit}*"."{digit}+     { printf("DECIMAL(%s)\n", yytext); }
{character}({character}|{digit})*   { printf("IDENTIFIER(%s)\n", yytext); }

"true"|"false"              { printf("BOOLLIT(%s)\n", yytext); }
"&&"                     { printf("AND\n"); }
"="                     { printf("ASSIGN\n"); }
"*"                     { printf("STAR\n"); }
","                     { printf("COMMA\n"); }
"/"                     { printf("DIV\n"); }
"=="                    { printf("EQ\n"); }
">="                    { printf("GE\n"); }
">"                     { printf("GT\n"); }
"{"                     { printf("LBRACE\n"); }
"<="                    { printf("LE\n"); }
"("                     { printf("LPAR\n"); }
"["                     { printf("LSQ\n"); }
"<"                     { printf("LT\n"); }
"-"                     { printf("MINUS\n"); }
"%"                     { printf("MOD\n"); }
"!="                    { printf("NE\n"); }
"!"                     { printf("NOT\n"); }
"||"                     { printf("OR\n"); }
"+"                     { printf("PLUS\n"); }
"}"                     { printf("RBRACE\n"); }
")"                     { printf("RPAR\n"); }
"]"                     { printf("RSQ\n"); }
";"                     { printf("SEMICOLON\n"); }
"->"                    { printf("ARROW\n"); }
"<<"                    { printf("LSHIFT\n"); }
">>"                    { printf("RSHIFT\n"); }
"^"                     { printf("XOR\n"); }
"boolean"                 { printf("BOOL\n"); }
"class"                   { printf("CLASS\n"); }
".length"                { printf("DOTLENGTH\n"); }
"double"                  { printf("DOUBLE\n"); }
"else"                    { printf("ELSE\n"); }
"if"                      { printf("IF\n"); }
"int"                     { printf("INT\n"); }
"System.out.println"     { printf("PRINT\n"); }
"Integer.parseInt"         { printf("PARSEINT\n"); }
"public"                  { printf("PUBLIC\n"); }
"return"                  { printf("RETURN\n"); }
"static"                  { printf("STATIC\n"); }
"string"                  { printf("STRING\n"); }
"void"                    { printf("VOID\n"); }
"while"                   { printf("WHILE\n"); }
"++"|"--"|"null"|"this"|"new" { printf("RESERVED(%s)\n", yytext); }

{open_comment}         { BEGIN(COMMENT); }
<COMMENT>\n            { line_number++; column_number = 1; }
<COMMENT>{close_comment} { BEGIN(INITIAL); }
<COMMENT>.             { /* ignore */ }

\"                      { BEGIN(STRLIT); }
<STRLIT>\\[\"nrtf\\]    { strcat(string_buffer, yytext); }
<STRLIT>\\              { printf("Line %d, column %d: invalid escape sequence (%s)\n", line_number, column_number, yytext); }
<STRLIT>\\.             { printf("Line %d, column %d: invalid escape sequence (%s)\n", line_number, column_number, yytext); }
<STRLIT>\"              { printf("STRLIT(\"%s\")\n", string_buffer); string_buffer[0] = '\0'; BEGIN(INITIAL); }
<STRLIT>.               { strncat(string_buffer, yytext, 1); }

[\r\n]+                { line_number++; column_number = 1; }
[ \t]+                 { column_number += yyleng; }
.                      { printf("Line %d, column %d: unrecognized character (%s)\n", line_number, column_number, yytext); }
%%
extern int yylex();
int main() {
    yylex();    /* run the lexical analysis automaton */
    return 0;
}
int yywrap() {  /* called on EOF, return 1 to terminate */
    return 1;
}

%{
    int line_number = 1;
    int column_number = 1;

    char string_buffer[1024] = "\0";
%}
digit   [0-9]
character    [a-zA-Z]
if      "if"
then    "then"
else    "else"
integer "integer"
double  "double"
o_parenthesis   "("
c_parenthesis   ")"
equal           "="
comma           ","
star            "*"
f_slash          "/"
adition          "+"
subtraction      "-"
open_comment   "/*"
close_comment  "*/"

%X COMMENT STRLIT

%%
{digit}+                { printf("NATURAL(%s)\n", yytext); }
{digit}*"."{digit}+     { printf("DECIMAL(%s)\n", yytext); }
{o_parenthesis}|{c_parenthesis} { printf("%s\n", yytext); }
{equal}|{comma}|{star}|{f_slash}|{adition}|{subtraction} { printf("%s\n", yytext); }
if                      { printf("IF\n"); }
else                    { printf("ELSE\n"); }
then                    { printf("THEN\n"); }
double                  { printf("DOUBLE\n"); }
integer                 { printf("INTEGER\n"); }
{character}({character}|{digit})*   { printf("IDENTIFIER(%s)\n", yytext); }

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

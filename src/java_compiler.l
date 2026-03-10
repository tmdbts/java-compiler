%{
    int line_number = 1;
    int column_number = 1;

    char string_buffer[1024] = "\0";
%}

digit               [0-9]
binary_digit        [01]
octal_digit         [0-7]
hex_digit           [0-9a-fA-F]
sign                [+-]
exponent            [eE]{sign}?{digit}+
int_literal         (0_?{octal_digit}+_{octal_digit}+)+|(0{octal_digit}+)|(0[xX]_?{hex_digit}+_{hex_digit}+)+|(0[xX]{hex_digit}+)|([1-9]({digit}+_{digit}+)*|[1-9]{digit}*)|"0"
float_literal       ({digit}+\.{digit}*{exponent}?)|({digit}+"."{digit}*)|(\.{digit}+{exponent}?)|({digit}+{exponent})
character    [a-zA-Z]
open_block_comment   "/*"
close_block_comment  "*/"
reserved_keywords "++"|"--"|"null"|"this"|"new"|"abstract"|"assert"|"break"|"byte"|"case"|"char"|"catch"|"const"|"continue"|"default"|"do"|"enum"|"extends"|"final"|"finally"|"float"|"for"|"goto"|"implements"|"import"|"Integer"|"instanceof"|"interface"|"long"|"native"|"package"|"private"|"protected"|"short"|"static"|"strict"|"strictfp"|"super"|"switch"|"System"|"synchronized"|"throw"|"throws"|"transient"|"try"|"volatile"|"while"|"open"|"module"|"requires"|"transitive"|"exports"|"opens"|"uses"|"provides"|"_"

%X BLOCK_COMMENT STRLIT

%%
[\r\n]+                { line_number++; column_number = 1; }
[ \t\f]+                 { column_number += yyleng; }

"//"([^\n\r]|.)*                   { line_number++; column_number = 1; }

{open_block_comment}           { BEGIN(BLOCK_COMMENT); }
<BLOCK_COMMENT>\n                    { line_number++; column_number = 1; }
<BLOCK_COMMENT><<EOF>>            { printf("Line %d, column %d: unterminated block comment\n", line_number, column_number); BEGIN(INITIAL); }
<BLOCK_COMMENT>{close_block_comment} { BEGIN(INITIAL); }
<BLOCK_COMMENT>.             { /* ignore */ }

\"                      { BEGIN(STRLIT); }
<STRLIT>\\[\"nrtf\\]    { strcat(string_buffer, yytext); }
<STRLIT>\\              { printf("Line %d, column %d: invalid escape sequence (%s)\n", line_number, column_number, yytext); }
<STRLIT>\\.             { printf("Line %d, column %d: invalid escape sequence (%s)\n", line_number, column_number, yytext); }
<STRLIT>\"              { printf("STRLIT(\"%s\")\n", string_buffer); string_buffer[0] = '\0'; BEGIN(INITIAL); }
<STRLIT><<EOF>>            { printf("Line %d, column %d: unterminated string literal\n", line_number, column_number); string_buffer[0] = '\0'; BEGIN(INITIAL); }
<STRLIT>\n              { printf("Line %d, column %d: unterminated string literal\n", line_number, column_number); string_buffer[0] = '\0'; line_number++; column_number=1; BEGIN(INITIAL); }
<STRLIT>.               { strncat(string_buffer, yytext, 1); }

{int_literal}                { printf("NATURAL(%s)\n", yytext); }
{float_literal}     { printf("DECIMAL(%s)\n", yytext); }

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
"System.out.print"     { printf("PRINT\n"); }
"Integer.parseInt"         { printf("PARSEINT\n"); }
"String"                    { printf("STRING\n"); }
"public"                  { printf("PUBLIC\n"); }
"return"                  { printf("RETURN\n"); }
"static"                  { printf("STATIC\n"); }
"void"                    { printf("VOID\n"); }
"while"                   { printf("WHILE\n"); }

{reserved_keywords}      { printf("RESERVED(%s)\n", yytext); }

({character}|_|\$)({character}|_|\$|{digit})*   { printf("IDENTIFIER(%s)\n", yytext); }

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

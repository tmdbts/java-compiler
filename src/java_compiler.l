%{
    int line_number = 1;
    int column_number = 1;

	int block_comment_line = 1;
	int block_comment_column = 1;

	int string_start_line = 1;
	int string_start_column = 1;

	int string_has_error = 0;

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
reserved_keywords "++"|"--"|"null"|"this"|"new"|"abstract"|"assert"|"break"|"byte"|"case"|"char"|"catch"|"const"|"continue"|"default"|"do"|"enum"|"extends"|"final"|"finally"|"float"|"for"|"goto"|"implements"|"import"|"Integer"|"instanceof"|"interface"|"long"|"native"|"package"|"private"|"protected"|"short"|"static"|"strict"|"strictfp"|"super"|"switch"|"System"|"synchronized"|"throw"|"throws"|"transient"|"try"|"volatile"|"while"|"open"|"module"|"transitive"|"exports"|"opens"

%X BLOCK_COMMENT STRLIT

%%
\r\n|\r|\n       { line_number++; column_number = 1; }
[ \t\f]+                { column_number += yyleng; }

"//"[^\r\n]* { column_number += yyleng; }

{open_block_comment} {
block_comment_line = line_number;
block_comment_column = column_number;
column_number += yyleng;
BEGIN(BLOCK_COMMENT);
}
<BLOCK_COMMENT>\r\n|\r|\n       { line_number++; column_number = 1; }
<BLOCK_COMMENT><<EOF>> {
printf("Line %d, col %d: unterminated comment\n",
block_comment_line, block_comment_column);
BEGIN(INITIAL);
}
<BLOCK_COMMENT>{close_block_comment} {
column_number += yyleng;
BEGIN(INITIAL);
}
<BLOCK_COMMENT>. { column_number += yyleng; }

\" {
string_buffer[0] = '\0';
string_start_line = line_number;
string_start_column = column_number;
string_has_error = 0;
column_number += yyleng;
BEGIN(STRLIT);
}

<STRLIT>\\[\"nrtf\\]    { strcat(string_buffer, yytext); column_number += yyleng; }

<STRLIT>\\\r\n|\\\r|\\\n {
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
printf("Line %d, col %d: invalid escape sequence (%s)\n", line_number, column_number, yytext);
string_has_error = 1;
column_number += yyleng;
}
<STRLIT>\\. {
printf("Line %d, col %d: invalid escape sequence (%s)\n", line_number, column_number, yytext);
string_has_error = 1;
column_number += yyleng;
}
<STRLIT>\" {
if (!string_has_error && lex_flag) { printf("STRLIT(\"%s\")\n", string_buffer); }
string_buffer[0] = '\0';
column_number += yyleng;
BEGIN(INITIAL);
}
<STRLIT><<EOF>> {
printf("Line %d, col %d: unterminated string literal\n",
string_start_line, string_start_column);
string_buffer[0] = '\0';
BEGIN(INITIAL);
}
<STRLIT>\r\n|\r|\n {
printf("Line %d, col %d: unterminated string literal\n",
string_start_line, string_start_column);
string_buffer[0] = '\0';
line_number++;
column_number = 1;
BEGIN(INITIAL);
}

<STRLIT>.               { strncat(string_buffer, yytext, 1); column_number += yyleng; }

{float_literal} { if (lex_flag) printf("DECIMAL(%s)\n", yytext); 
                  column_number += yyleng; }
{int_literal}   { if (lex_flag) printf("NATURAL(%s)\n", yytext); 
                  column_number += yyleng; }

"true"|"false"          { if(lex_flag) printf("BOOLLIT(%s)\n", yytext);  column_number += yyleng; }
"&&"                   	{ if(lex_flag) printf("AND\n");  column_number += yyleng; }
"="                     { if(lex_flag) printf("ASSIGN\n");  column_number += yyleng; }
"*"                     { if(lex_flag) printf("STAR\n");  column_number += yyleng; }
","                     { if(lex_flag) printf("COMMA\n");  column_number += yyleng; }
"/"                     { if(lex_flag) printf("DIV\n");  column_number += yyleng; }
"=="                    { if(lex_flag) printf("EQ\n");  column_number += yyleng; }
">="                    { if(lex_flag) printf("GE\n");  column_number += yyleng; }
">"                     { if(lex_flag) printf("GT\n");  column_number += yyleng; }
"{"                     { if(lex_flag) printf("LBRACE\n");  column_number += yyleng; }
"<="                    { if(lex_flag) printf("LE\n");  column_number += yyleng; }
"("                     { if(lex_flag) printf("LPAR\n");  column_number += yyleng; }
"["                     { if(lex_flag) printf("LSQ\n");  column_number += yyleng; }
"<"                     { if(lex_flag) printf("LT\n");  column_number += yyleng; }
"-"                     { if(lex_flag) printf("MINUS\n");  column_number += yyleng; }
"%"                     { if(lex_flag) printf("MOD\n");  column_number += yyleng; }
"!="                    { if(lex_flag) printf("NE\n");  column_number += yyleng; }
"!"                     { if(lex_flag) printf("NOT\n");  column_number += yyleng; }
"||"                    { if(lex_flag) printf("OR\n");  column_number += yyleng; }
"+"                     { if(lex_flag) printf("PLUS\n");  column_number += yyleng; }
"}"                     { if(lex_flag) printf("RBRACE\n"); column_number += yyleng; }
")"                     { if(lex_flag) printf("RPAR\n");  column_number += yyleng; }
"]"                     { if(lex_flag) printf("RSQ\n");  column_number += yyleng; }
";"                     { if(lex_flag) printf("SEMICOLON\n");  column_number += yyleng; }
"->"                    { if(lex_flag) printf("ARROW\n");  column_number += yyleng; }
"<<"                    { if(lex_flag) printf("LSHIFT\n");  column_number += yyleng; }
">>"                    { if(lex_flag) printf("RSHIFT\n");  column_number += yyleng; }
"^"                     { if(lex_flag) printf("XOR\n");  column_number += yyleng; }
"boolean"               { if(lex_flag) printf("BOOL\n");  column_number += yyleng; }
"class"                 { if(lex_flag) printf("CLASS\n");  column_number += yyleng; }
".length"               { if(lex_flag) printf("DOTLENGTH\n");  column_number += yyleng; }
"double"                { if(lex_flag) printf("DOUBLE\n");  column_number += yyleng; }
"else"                  { if(lex_flag) printf("ELSE\n");  column_number += yyleng; }
"if"                    { if(lex_flag) printf("IF\n");  column_number += yyleng; }
"int"                   { if(lex_flag) printf("INT\n");  column_number += yyleng; }
"System.out.print"     	{ if(lex_flag) printf("PRINT\n");  column_number += yyleng; }
"Integer.parseInt"      { if(lex_flag) printf("PARSEINT\n");  column_number += yyleng; }
"String"                { if(lex_flag) printf("STRING\n");  column_number += yyleng; }
"public"                { if(lex_flag) printf("PUBLIC\n");  column_number += yyleng; }
"return"                { if(lex_flag) printf("RETURN\n");  column_number += yyleng; }
"static"                { if(lex_flag) printf("STATIC\n");  column_number += yyleng; }
"void"                  { if(lex_flag) printf("VOID\n");  column_number += yyleng; }
"while"                 { if(lex_flag) printf("WHILE\n");  column_number += yyleng; }

{reserved_keywords}     { if(lex_flag) { printf("RESERVED(%s)\n", yytext); } column_number += yyleng; }

({character}|_|\$)({character}|_|\$|{digit})* {
if (lex_flag) { printf("IDENTIFIER(%s)\n", yytext); }
column_number += yyleng;
}

. {
printf("Line %d, col %d: illegal character (%s)\n", line_number, column_number, yytext);
column_number += yyleng;
}

%%

extern int yylex();
int main(int argc, char **argv) {
    if(argc >= 2 && strcmp(argv[1], "-l") == 0) {   
        lex_flag = 1;
        yylex();    

        return 0;
    }

    yylex();

    return 0;
}
int yywrap() {  /* called on EOF, return 1 to terminate */
    return 1;
}

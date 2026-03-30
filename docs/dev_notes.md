## Expressions implementation
The original EBNF expression grammar is ambiguous and unsuitable for direct 
bottom-up parsing with yacc. Although yacc precedence declarations can resolve 
part of that ambiguity, a single Expr nonterminal still leads to many parser 
conflicts and complicates AST construction. We therefore rewrote expressions 
into multiple nonterminals, one per precedence level, encoding precedence and 
associativity directly in the grammar. This reduces shift/reduce conflicts, 
simplifies semantic actions, and produces an AST structure closer to the 
operator hierarchy required in later semantic analysis.

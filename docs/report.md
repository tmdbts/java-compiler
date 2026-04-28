# Relatório – Compilador para a linguagem Juc

---

## 1. Gramática re-escrita

A gramática EBNF fornecida é ambígua e inadequada para análise ascendente com
yacc. Embora as declarações de precedência resolvam parte da ambiguidade, um
único não-terminal `Expr` produz vários conflitos *shift/reduce* e complica a
construção da AST. As expressões foram reescritas num conjunto de
não-terminais, um por nível de precedência (`AssignExpr`, `OrExpr`, `XorExpr`,
`AndExpr`, `EqExpr`, `RelExpr`, `ShiftExpr`, `AddExpr`, `MulExpr`, `UnaryExpr`,
`PrimaryExpr`), codificando precedência e associatividade diretamente na
gramática.

Do ponto de vista teórico, esta transformação aproxima a gramática de uma forma
mais adequada a análise LR: em vez de deixar precedência e associatividade
implícitas numa regra genérica para expressões, essas propriedades passam a
estar codificadas na própria estrutura sintática. Assim, reduz-se o número de
situações em que o analisador ascendente tem simultaneamente uma redução
plausível e um novo símbolo a deslocar, origem clássica de conflitos
*shift/reduce* em gramáticas ambíguas de expressões.

A maioria dos operadores binários usa recursão à esquerda
(`AddExpr → AddExpr PLUS MulExpr | …`), produzindo associatividade à esquerda
natural num analisador LR. A atribuição é a exceção:
`AssignExpr → IDENTIFIER ASSIGN AssignExpr | OrExpr`, com `%right ASSIGN`, dá
associatividade à direita e suporta expressões como `a = b = 1`. O *dangling
else* é resolvido com `%nonassoc LOWER_THAN_ELSE` aplicado à regra de `if` sem
`else`.

Declarações com múltiplos identificadores (`int a, b, c;`) são normalizadas em
vários nós `FieldDecl`/`VarDecl`, um por símbolo, o que simplifica
posteriormente a tabela de símbolos. Os tipos `void` e `String[]` são tratados
como casos especiais: `void` só ocorre em `MethodHeader` e `String[]` apenas
nas regras de parâmetros formais. Construções específicas da linguagem —
`Integer.parseInt(...)`, `.length`, `System.out.print(...)` e invocações —
têm regras e categorias dedicadas (`ParseArgs`, `Length`, `Print`, `Call`),
evitando uma gramática genérica de pós-fixos e simplificando a análise
semântica.

A AST é construída diretamente nas ações semânticas das produções, sem passo
de conversão posterior, usando os auxiliares `new_node`, `adopt1`, `adopt2` e
`add_children`. Sequências de irmãos — membros de classe, statements,
parâmetros e argumentos — são acumuladas em listas temporárias `node_list` e
só depois anexadas ao nó pai, mantendo a árvore plana e sem nós invólucro
supérfluos. Os nós `if` e `while` são normalizados com aridade fixa: o `if`
tem sempre três filhos (condição, ramo *then*, ramo *else*), sendo inserido
um `Block` vazio quando o `else` está ausente.

Para recuperação de erros foram introduzidas regras locais em `FieldDecl`,
`Statement`, `MethodInvocation`, `ParseArgs` e `PrimaryExpr` (parêntesis),
permitindo prosseguir a análise após erros pontuais sem comprometer o resto
do ficheiro. As posições no código fonte são associadas aos nós através da
diretiva `%locations` e do macro `SET_POS`, ficando disponíveis para
mensagens de erro semânticas precisas em fases posteriores.

---

## 2. Algoritmos e estruturas de dados

A AST é definida em `ast.h` por dois tipos: `struct node` (categoria, *token*
lexical, linha, coluna, anotação semântica e lista de filhos) e
`struct node_list` (lista ligada simples). A categoria é uma enumeração que
cobre todas as construções relevantes — declarações, *statements*,
operadores e terminais. O campo `annotation` é a única estrutura mutada após
a fase sintática: é aí que o analisador semântico escreve o tipo inferido
(`int`, `double`, `boolean`, `String[]`, `undef`) ou a assinatura formal do
método invocado.

Os auxiliares de construção (`new_node`, `add_child`, `adopt1`, `adopt2`,
`new_list`, `append_list`, `join_lists`, `add_children`, `copy_leaf_node`)
atuam exclusivamente durante a construção da árvore. `copy_leaf_node` é
usado para duplicar nós de tipo em declarações expandidas, evitando partilha
de instâncias. `get_child` fornece acesso posicional, padrão usado em todo o
analisador semântico (e.g., filho 0 do `MethodHeader` é o tipo de retorno).

A tabela de símbolos é organizada em dois níveis. A tabela da classe é uma
lista ligada de `struct class_symbol` com nome, tipo, número e tipos dos
parâmetros formais e assinatura textual. Cada método tem uma tabela própria,
representada por `struct method_info` (também encadeada), contendo
`table_entry` para `return`, parâmetros e variáveis locais. O campo
`in_scope` distingue locais já declaradas das ainda não declaradas no ponto
atual.

A análise semântica corre em duas passagens. `build_symbol_tables` percorre
os filhos de `Program` e popula a tabela da classe, detetando duplicados e o
uso reservado de `_`. Depois, `check_method` percorre cada corpo: as
declarações locais são adicionadas pela ordem em que aparecem
(`collect_local_declaration`); os *statements* são verificados por
`check_statement`; e as expressões por `check_expression`, com despacho por
categoria. A resolução de identificadores procura primeiro na tabela do
método e só depois nos campos da classe.

Em termos teóricos, esta separação distingue análise de nomes de verificação de
usos e tipos. A primeira passagem recolhe o conjunto de símbolos globais e as
assinaturas dos métodos, permitindo que chamadas sejam resolvidas
independentemente da ordem em que os corpos surgem no programa. A segunda
passagem verifica cada corpo já com esse contexto disponível. As variáveis
locais constituem um caso diferente: o seu âmbito é sequencial dentro do corpo
do método, pelo que só se tornam visíveis a partir do ponto da respetiva
declaração. O algoritmo implementa assim duas regras semânticas distintas:
visibilidade global ao nível da classe para métodos e campos, e visibilidade
dependente do ponto do programa para variáveis locais.

A resolução de invocações (`resolve_method_call`) segue a regra do enunciado:
privilegia a correspondência exata; na sua ausência, aceita uma única
correspondência compatível por promoção `int → double`; caso contrário, emite
`Cannot find symbol` ou `Reference to method ... is ambiguous`. Em qualquer
falha, os nós `Call` e `Identifier` envolvidos são anotados com `undef`,
permitindo prosseguir e reportar erros adicionais. As mensagens são
acumuladas num vetor dinâmico (`semantic_errors`), redimensionado por
`ensure_error_capacity`, e impressas em bloco antes das tabelas e da AST
anotada, garantindo a ordem de saída exigida.

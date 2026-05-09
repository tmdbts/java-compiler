# Relatório – Compilador para a linguagem Juc

---

## 1. Análise lexical

A análise lexical é direta para a maioria dos tokens: o lexer aceita os
símbolos da linguagem e rejeita os restantes. As partes menos triviais são
comentários de bloco e literais de string, porque ambos podem ocupar vários
caracteres e não devem ser tratados pelas regras normais enquanto estão a ser
lidos.

As strings são tratadas de forma semelhante com o estado exclusivo `STRLIT`.
Quando o lexer encontra `"`, começa a acumular o conteúdo da string num buffer
até encontrar a aspa final. Durante esse processo valida apenas as sequências
de escape permitidas (`\"`, `\n`, `\r`, `\t`, `\f` e `\\`). Qualquer outro
escape é reportado como inválido, e uma quebra de linha ou fim de ficheiro
antes da aspa final é reportado como string não terminada. Assim, o parser só
recebe um token `STRINGLIT` quando a string está completa e válida.

---

## 2. Gramática re-escrita

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
associatividade à direita e suporta expressões como `a = b = 1`.

O conflito do *dangling else* aparece quando existe um `if` dentro de outro
`if`, por exemplo `if (a) if (b) s1; else s2;`. Quando o parser encontra o
`else`, há duas interpretações possíveis: fechar o `if (b)` como um `if` sem
`else`, ou associar esse `else` ao `if (b)`. A regra pretendida, igual à de
Java, é que o `else` pertença sempre ao `if` mais próximo que ainda não tem
`else`.

Para indicar isto ao yacc, foi criado um nível de precedência artificial
`LOWER_THAN_ELSE`, mais baixo do que a precedência do token `ELSE`. A produção
do `if` sem `else` usa `%prec LOWER_THAN_ELSE`. Assim, quando há dúvida entre
reduzir o `if` sem `else` ou ler o `ELSE`, o parser escolhe ler o `ELSE`. Na
prática, isto faz com que o `else` fique ligado ao `if` interior no caso de
nested `if/else`.

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

Na AST, isto aparece de forma direta: o ramo *then* de um `If` pode ser outro
nó `If`, já com o seu próprio `else`. Quando não existe `else` no código, o
parser cria um `Block` vazio como terceiro filho, para que todos os nós `If`
tenham sempre a mesma forma: condição, ramo *then* e ramo *else*.

Para recuperação de erros foram introduzidas regras locais em `FieldDecl`,
`Statement`, `MethodInvocation`, `ParseArgs` e `PrimaryExpr` (parêntesis),
permitindo prosseguir a análise após erros pontuais sem comprometer o resto
do ficheiro. As posições no código fonte são associadas aos nós através da
diretiva `%locations` e do macro `SET_POS`, ficando disponíveis para
mensagens de erro semânticas precisas em fases posteriores.

---

## 3. Algoritmos e estruturas de dados

A AST é definida em `ast.h` por dois tipos: `struct node` (categoria, *token*
lexical, linha, coluna, anotação semântica e lista de filhos) e
`struct node_list` (lista ligada simples). A categoria é uma enumeração que
cobre todas as construções relevantes — declarações, *statements*,
operadores e terminais. O campo `annotation` é a única estrutura mutada após
a fase sintática: é aí que o analisador semântico escreve o tipo inferido
(`int`, `double`, `boolean`, `String[]`, `void`, `undef`), a assinatura formal
do método invocado ou a anotação `String` usada em literais impressos.

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
`table_entry` para `return`, parâmetros e variáveis locais. As variáveis locais
são inseridas apenas quando a sua declaração é encontrada, preservando a regra
de visibilidade sequencial dentro do corpo do método.

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

### Verificação de tipos

A verificação de tipos é feita de forma recursiva sobre a AST. Cada expressão
devolve um tipo semântico (`int`, `double`, `boolean`, `String[]`, `void` ou
`undef`) e, quando aplicável, esse tipo é escrito no campo `annotation` do nó.
O tipo `undef` é usado quando uma expressão não pode ser resolvida, permitindo
continuar a análise e reportar mais erros no mesmo programa.

| Construção | Regra |
| --- | --- |
| Atribuição | O tipo do lado direito tem de ser compatível com o identificador do lado esquerdo. É permitida promoção `int → double`; `String[]` não pode ser atribuído. |
| `return` | O tipo devolvido tem de ser compatível com o tipo de retorno do método; `return;` só é válido em métodos `void`. |
| Aritmética | Operadores aritméticos exigem operandos numéricos; o resultado é `double` se algum operando for `double`, caso contrário é `int`. |
| Booleanos e comparações | Operadores booleanos exigem `boolean`; comparações relacionais exigem valores numéricos; ambos produzem `boolean`. |
| Igualdade | `==` e `!=` aceitam dois valores numéricos ou dois valores `boolean`, produzindo `boolean`. |
| `String[]` | `.length` só é válido sobre `String[]`; `Integer.parseInt` exige um `String[]` e um índice `int`. |
| Invocações | Primeiro procura uma assinatura exata; se não existir, aceita uma única assinatura compatível por promoção `int → double`; várias compatíveis tornam a chamada ambígua. |

Algumas expressões mantêm um tipo nominal mesmo depois de reportarem erro,
como `.length`, `Integer.parseInt`, comparações e operadores booleanos. Esta é
uma decisão de recuperação: depois de emitir o erro local, o compilador mantém
um tipo previsível para evitar erros em cascata e conseguir continuar a
verificação do resto da AST.

A resolução de invocações (`resolve_method_call`) é um caso especial desta
verificação, porque depende não só do nome do método, mas também dos tipos dos
argumentos. Em qualquer falha, os nós `Call` e `Identifier` envolvidos são
anotados com `undef`, permitindo prosseguir e reportar erros adicionais. As
mensagens são acumuladas num vetor dinâmico (`semantic_errors`),
redimensionado por `ensure_error_capacity`, e impressas em bloco antes das
tabelas e da AST anotada, garantindo a ordem de saída exigida.

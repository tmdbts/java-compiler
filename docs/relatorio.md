# Relatório – Compilador para Juc

**Autores:** [completar com nome e número de cada elemento]

---

## 1. Gramática reescrita

A gramática EBNF do enunciado é ambígua e contém repetições (`{...}`) e construções opcionais (`[...]`) que não podem ser entregues diretamente ao yacc. A reescrita teve como objetivo produzir uma versão LALR(1) sem conflitos, mantendo a semântica do Java SE 9.

**Expressões.** A regra única `Expr` foi substituída por uma cascata de não-terminais, um por nível de precedência, que codifica diretamente a precedência e associatividade dos operadores: `AssignExpr → OrExpr → XorExpr → AndExpr → EqExpr → RelExpr → ShiftExpr → AddExpr → MulExpr → UnaryExpr → PrimaryExpr`. Cada camada usa recursão à esquerda (associatividade à esquerda), exceto `AssignExpr` e `UnaryExpr`, que são recursivas à direita para permitir, respetivamente, `a = b = c` e cadeias de operadores unários como `--x` ou `!!x`. Esta reescrita reduz drasticamente o número de conflitos shift/reduce e produz uma AST cuja forma já reflete a hierarquia de precedências, simplificando análises posteriores.

**Dangling-else.** Resolvido com as duas precedências fictícias `%nonassoc LOWER_THAN_ELSE` e `%nonassoc ELSE`, marcando a regra `if` sem `else` com `%prec LOWER_THAN_ELSE`. Com isto, o yacc prefere shift sobre reduce quando vê `ELSE`, ligando-o ao `if` mais próximo — o comportamento padrão do Java.

**Repetições EBNF.** As construções `{...}` foram traduzidas para recursão à esquerda explícita em listas auxiliares: `ClassBody`, `StatementList`, `MethodBodyItems`, `IdentifierList`, `FormalParamsTail`. As construções `[...]` foram desdobradas em pares de regras alternativas (`OptExpr`, `OptArgList`, `OptFormalParams`).

**Recuperação de erros.** Adicionámos regras `error` em pontos onde a sincronização é segura: `FieldDecl: error SEMICOLON`, `Statement: error SEMICOLON`, `ParseArgs: PARSEINT LPAR error RPAR`, `MethodInvocation: IDENTIFIER LPAR error RPAR`, `PrimaryExpr: LPAR error RPAR`. Estes pontos foram escolhidos porque os respetivos delimitadores (`;`, `)`) garantem retoma sem falsos positivos em cascata.

**Decisões nas ações semânticas.** Várias normalizações são feitas durante a construção da AST para simplificar a Meta 3:

- Declarações múltiplas (`int a, b, c;`) geram um nó `VarDecl`/`FieldDecl` por identificador, com cópia dos nós de tipo via `copy_leaf_node`.
- Parêntesis em expressões são absorvidos: `PrimaryExpr: LPAR Expr RPAR { $$ = $2; }`.
- Blocos de um único statement não geram nó `Block`; só são criados blocos com 2+ statements, ou blocos vazios obrigatórios para preservar a aridade dos nós `If`/`While`.
- O literal `String[]` é construído explicitamente nas regras de parâmetros formais, e não através do não-terminal `Type`, por só ser válido em parâmetros.

---

## 2. AST e tabelas de símbolos

**AST.** Adotámos um único struct genérico `node` com `category` (enum), `token`, `line`, `column`, `annotation` e lista ligada de filhos. Esta uniformidade simplifica a travessia recursiva sem necessidade de structs especializados por categoria. As ações do parser usam construtores reutilizáveis (`new_node`, `adopt1`, `adopt2`, `add_child`, `add_children`) e helpers de listas temporárias (`new_list`, `append_list`, `join_lists`) que servem para acumular siblings durante o parsing antes de os anexar ao nó pai. As posições de origem (`line`, `column`) são atribuídas via macros `SET_POS(@N)` nas ações do `.y`, dando à Meta 3 a capacidade de reportar erros com localização exata. A AST minimiza redundância seguindo o enunciado: blocos com um único statement são achatados, não-terminais de precedência colapsam via `$$ = $1`, e parêntesis são absorvidos.

**Tabelas de símbolos.** A estrutura é a dois níveis. Uma tabela global da classe (`class_symbols`) contém campos e métodos. Cada método tem uma tabela própria (`method_info.entries`) com a entrada sintética `return`, parâmetros e variáveis locais. Foram modeladas com structs distintos (`class_symbol` e `table_entry`) porque os formatos de impressão e os campos relevantes diferem (assinatura, contagem de parâmetros, tipos de parâmetros — só relevantes para métodos). Todas as listas são ligadas com ponteiros `tail` para append em O(1), preservando a ordem de inserção que coincide com a ordem de declaração no código-fonte e a ordem de impressão exigida pelo enunciado.

**Construção em duas passagens.** Primeiro percorremos os filhos diretos do `Program`, registando todos os campos e cabeçalhos de métodos. Só depois entramos nos corpos dos métodos. Esta separação permite que um método invoque outro declarado mais abaixo no ficheiro, sem necessidade de declarações antecipadas.

**Verificação de tipos.** A função recursiva `check_expression` faz dispatch pela `category` do nó e devolve um `enum semantic_type`. Cada operador delega a um helper específico (`check_arithmetic`, `check_relational`, `check_xor`, etc.) que verifica os operandos, anota o nó com o tipo resultante, e gera erros quando aplicável. Adotámos uma estratégia consistente de **recuperação por anotação nominal**: operadores com regras de domínio fixo (`Xor`, `parseInt`, `.length`, comparações, equality, lógicos, `Not`) anotam sempre com o seu tipo nominal mesmo quando os operandos são inválidos, evitando que erros cascateiem para os ancestrais e gerem mensagens secundárias confusas. Operadores aritméticos e shifts, em contraste, propagam `undef` quando os operandos não são compatíveis.

**Resolução de overload.** A função `resolve_method_call` procura primeiro um método com nome, aridade e tipos de parâmetros exatamente iguais. Se não houver match exato, procura métodos compatíveis com promoção `int → double`. Se houver exatamente um compatível, é selecionado; mais que um gera erro `Reference to method X is ambiguous`; nenhum gera `Cannot find symbol`.

---

## 3. Geração de código

**Nota:** A geração de código não foi concluída na entrega final. Esta secção documenta a arquitetura proposta e as principais decisões técnicas que tomaríamos.

**Estratégia geral.** A geração faria-se por travessia recursiva pós-ordem da AST anotada. Para expressões, uma função `gen_expr(node)` devolveria um par `(operando_LLVM, tipo_semantico)`: para literais, o operando é o próprio valor; para operações compostas, é o registo virtual onde a instrução depositou o resultado. Para statements, uma função `gen_statement(node)` emitiria código sem devolver valor. As tabelas de símbolos da Meta 3 seriam reaproveitadas (não reconstruídas), com um campo adicional `llvm_name` em cada entrada para guardar o operando correspondente (`%x` para alloca local, `@x` para variável global).

**`alloca`-everything.** Adotaríamos a convenção de manter todas as variáveis (incluindo parâmetros, copiados de `%arg_x` para `%x` no bloco `entry`) em endereços de memória via `alloca`, com `load` para leitura e `store` para escrita. Esta abordagem evita gerar nós `phi` à mão e produz IR sempre correto. O passe `mem2reg` do LLVM converte automaticamente este padrão em SSA otimizado quando se compila com otimização.

**Mapeamento de tipos.** Tabela direta: `int → i32`, `double → double`, `boolean → i1`, `String[] → i8**`. Cada operação aritmética escolheria a instrução apropriada (`add`/`fadd`, `sdiv`/`fdiv`, `srem`/`frem`). Comparações seriam emitidas com `icmp` ou `fcmp` consoante o tipo dos operandos.

**Promoções.** Quando uma operação mista força tipo `double` (algum operando é `double`), o operando `int` seria convertido com `sitofp i32 X to double` antes da operação. O mesmo princípio aplica-se a atribuições, argumentos de chamada e returns onde o contexto é `double` mas o valor é `int`.

**Estruturas de controlo.** Cada `if`/`while` produziria basic blocks rotulados terminados por instruções `br`. Para `if-else` típico: três blocos (`then`, `else`, `end`) com a condição a fazer `br i1 cond, label %then, label %else`. Para `while`: blocos `cond`, `body`, `end`, com a condição reavaliada no fim de cada iteração através de `br label %cond`. Os contadores de labels e registos seriam reiniciados no início de cada método.

**`System.out.print`.** Implementação à custa de `printf` da libc, com strings de formato declaradas como constantes globais no topo do ficheiro: `"%d\n"` para `int`, `"%.16e\n"` para `double`, `"%s\n"` para strings. Para `boolean`, geraríamos um `br i1` que ramifica para dois `printf` distintos com `"true\n"` e `"false\n"`.

**Pré-definidos e `main`.** `Integer.parseInt(args[i])` traduzir-se-ia em `getelementptr` + `load i8*` + `call i32 @atoi(i8*)`. `args.length` aproveitaria o `%argc` recebido pelo `main`. O `main` de Juc, mesmo sendo `void`, geraria `define i32 @main(i32 %argc, i8** %argv)` com `ret i32 0` final, conforme a convenção do sistema operativo.

---

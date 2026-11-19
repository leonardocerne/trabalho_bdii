# Trabalho de Banco de Dados II

Soluções das Partes 1 e 2 dos enunciados em Oracle SQL e PL/SQL, usando o esquema de exemplo Chinook. Ambiente validado no Oracle Database 21c Express Edition (XE), serviço `XEPDB1`.

## Como executar

Abra o SQL*Plus a partir da pasta que contém `Chinook_Oracle.sql` e a subpasta `trabalho`. Os comandos abaixo usam caminhos relativos a essa pasta.

### Em um esquema vazio

1. Em uma conexão administrativa no serviço do banco de dados, crie o dono do trabalho. Substitua a senha do exemplo antes de executar.

   ```sql
   CREATE USER bdii_aluno IDENTIFIED BY "SENHA_DO_DONO"
       DEFAULT TABLESPACE users QUOTA 50M ON users;
   GRANT CREATE SESSION, CREATE TABLE, CREATE PROCEDURE, CREATE TRIGGER, CREATE TYPE
       TO bdii_aluno;
   ```

2. Abra uma conexão no SQL*Plus como `BDII_ALUNO`. Ajuste o host, a porta e o serviço ao seu ambiente e informe a senha quando solicitada.

   ```sh
   sqlplus bdii_aluno@//localhost:1521/XEPDB1
   ```

3. No prompt do SQL*Plus, execute o instalador. Ele carrega o Chinook, instala as duas partes, executa os testes e grava o DDL gerado em `trabalho/ddl_chinook_gerado.sql`.

   ```sql
   @trabalho\instalar.sql
   ```

### Em um esquema que já contém o Chinook

Conecte como dono do esquema. A conta precisa dos mesmos privilégios do exemplo acima e de espaço no tablespace para criar as tabelas auxiliares. Execute os scripts nesta ordem.

```sql
@trabalho\parte1.sql
@trabalho\parte2.sql
@trabalho\testes.sql
```

No SQL Developer do VS Code, também é possível abrir cada um desses três arquivos e usar **Run Script** na conexão do dono. A Parte 1 reaproveita as tabelas e os registros de configuração existentes.

### Teste do usuário restrito da Parte 2

1. Na conexão administrativa do mesmo serviço, crie o usuário de teste com uma senha à sua escolha.

   ```sql
   CREATE USER bdii_operador IDENTIFIED BY "SENHA_DO_OPERADOR";
   GRANT CREATE SESSION TO bdii_operador;
   ```

2. Na conexão do dono, carregue os dados de demonstração e conceda acesso à procedure.

   ```sql
   @trabalho\fixtures_permissoes.sql
   GRANT EXECUTE ON bdii_incluir_faixa TO bdii_operador;
   ```

3. Em uma conexão separada como `BDII_OPERADOR`, rode o teste abaixo. Substitua `BDII_ALUNO` pelo nome do esquema que contém a procedure, se for diferente.

   ```sql
   @trabalho\teste_permissoes.sql BDII_ALUNO
   ```

   A mensagem `OK` confirma que o operador incluiu a faixa válida pela procedure, que a faixa curta foi rejeitada e que a inserção direta foi bloqueada. Para repetir a preparação, remova como dono a playlist de teste `-9100` e as faixas de teste `-9100` e `-9101`.

### Conferência do DDL da Parte 1

Para reproduzir a questão 4, execute `@trabalho\ddl_chinook_gerado.sql` em outro esquema vazio, com permissão para criar tabelas e quota no tablespace. O resultado esperado é **11 tabelas, 11 chaves primárias e 11 chaves estrangeiras**.

## Parte 1

| Questão | Solução |
| --- | --- |
| 1 | `USER_INDEXES` e `USER_IND_COLUMNS` mostram uma linha por coluna indexada, inclusive a ordem em índices compostos. |
| 2 | `BDII_REMOVER_INDICES` recebe o nome da tabela no esquema da sessão e remove todos os seus índices. Para retirar os índices de PK e UNIQUE, desabilita essas restrições e as FKs que dependem delas. O DDL faz commit implícito. O teste usa tabelas descartáveis. |
| 3 | As colunas de cada FK são pareadas com as colunas da chave referenciada pela posição. A consulta também identifica o esquema referenciado. |
| 4 | `BDII_GERAR_DDL` usa o catálogo para emitir colunas, tipos, nulabilidade e PKs e, em seguida, as FKs. A saída é um DDL estrutural para o Chinook, com suporte aos tipos do arquivo original. Os objetos auxiliares `BDII_*` ficam fora da exportação. |
| 5 | O fluxo de faturas começa em **ABERTA** e pode ir para **PAGA** ou **CANCELADA**, dois estados finais. Gravar novamente o mesmo estado é permitido. O catálogo de estados, inícios e transições e a procedure de validação podem atender outros fluxos com novos dados de configuração e um trigger na coluna correspondente. |

## Parte 2

- **Questões 1 e 2.** Na inclusão de um item de fatura ou na revisão de seu preço ou faixa, o preço de venda pode ter desconto em relação ao valor de catálogo vigente, mas não pode superá-lo. O trigger valida essas operações com uma consulta a `Track`. Alterações de preço de catálogo não reescrevem compras anteriores.
- **Questões 1 e 3.** Uma faixa precisa ter no mínimo 60 segundos no momento em que for cadastrada pela curadoria em uma playlist. A procedure consulta a duração em `Track` antes de inserir em `PlaylistTrack`. O usuário de curadoria recebe somente `CREATE SESSION` e `EXECUTE` na procedure. O teste verifica uma inclusão válida, a rejeição de uma faixa curta e o bloqueio de um `INSERT` direto.
- **Questão 4.** A solução em **PL/SQL** corrige os totais antigos e recalcula as faturas afetadas depois de cada comando sobre seus itens. Quando um item muda de fatura, recalcula a origem e o destino. O trigger bloqueia cada fatura com `SELECT FOR UPDATE` antes de consultar os itens e faz a atualização na mesma transação. Uma fatura sem itens tem total zero. O trigger sobre `Invoice` impede a gravação de um total divergente. Se um cálculo produzir fração de centavo que a coluna não consiga armazenar, a operação é rejeitada. Instale com as tabelas sem outras sessões de escrita.

Os dados usados nos testes de regras são revertidos ao final.

## Evidências de execução

As duas partes foram executadas e reexecutadas com `CHINOOK` como dono e `BDII_OPERADOR` como usuário restrito. As quatro procedures, os quatro triggers e o tipo da solução ficaram válidos.

- O teste removeu os três índices da tabela de demonstração, incluindo os de PK e UNIQUE, e confirmou que as chaves e a FK dependente ficaram desabilitadas.
- O DTE aceitou uma transição prevista e rejeitou um estado inicial inválido e a saída de um estado final.
- O trigger de preço rejeitou uma venda acima do catálogo. A validação de totais passou para os dados originais, inclusão de itens, atualização em lote, transferência, exclusão e tentativa de alterar o total diretamente.
- O usuário restrito executou a procedure, recebeu o erro esperado ao cadastrar uma faixa curta e teve a inserção direta bloqueada.
- O DDL gerado correspondeu ao arquivo salvo. Em um esquema descartável vazio, criou 11 tabelas, 11 chaves primárias e 11 chaves estrangeiras.

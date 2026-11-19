-- Questão 1: índices por tabela
SELECT i.table_name,
       i.index_name,
       i.uniqueness,
       c.column_position,
       c.column_name,
       c.descend
FROM user_indexes i
JOIN user_ind_columns c ON c.index_name = i.index_name
WHERE i.table_owner = USER
ORDER BY i.table_name, i.index_name, c.column_position;

-- Questão 2: remoção de índices
CREATE OR REPLACE PROCEDURE bdii_remover_indices(p_tabela IN VARCHAR2)
AUTHID CURRENT_USER AS
    v_tabela user_tables.table_name%TYPE;
BEGIN
    SELECT table_name INTO v_tabela
    FROM user_tables
    WHERE table_name = UPPER(TRIM(p_tabela));

    -- A remoção dos índices de PK e UNIQUE também desativa as FKs dependentes.
    FOR chave IN (
        SELECT constraint_name
        FROM user_constraints
        WHERE table_name = v_tabela
          AND constraint_type IN ('P', 'U')
          AND status = 'ENABLED'
          AND index_owner = USER
        ORDER BY constraint_name
    ) LOOP
        EXECUTE IMMEDIATE
            'ALTER TABLE ' || DBMS_ASSERT.ENQUOTE_NAME(v_tabela, FALSE) ||
            ' DISABLE CONSTRAINT ' || DBMS_ASSERT.ENQUOTE_NAME(chave.constraint_name, FALSE) ||
            ' CASCADE KEEP INDEX';
        DBMS_OUTPUT.PUT_LINE('Restricao desabilitada: ' || chave.constraint_name);
    END LOOP;

    FOR idx IN (
        SELECT index_name
        FROM user_indexes
        WHERE table_owner = USER AND table_name = v_tabela
        ORDER BY index_name
    ) LOOP
        EXECUTE IMMEDIATE 'DROP INDEX ' || DBMS_ASSERT.ENQUOTE_NAME(idx.index_name, FALSE);
        DBMS_OUTPUT.PUT_LINE('Indice removido: ' || idx.index_name);
    END LOOP;
EXCEPTION
    WHEN NO_DATA_FOUND THEN
        RAISE_APPLICATION_ERROR(-20001, 'Tabela inexistente no esquema do usuario.');
END;
/

-- Questão 3: chaves estrangeiras
SELECT fk.constraint_name,
       fk.table_name AS tabela_filha,
       fc.position,
       fc.column_name AS coluna_filha,
       pk.owner AS esquema_pai,
       pk.table_name AS tabela_pai,
       pc.column_name AS coluna_pai
FROM user_constraints fk
JOIN user_cons_columns fc ON fc.constraint_name = fk.constraint_name
JOIN all_constraints pk ON pk.owner = fk.r_owner
                       AND pk.constraint_name = fk.r_constraint_name
JOIN all_cons_columns pc ON pc.owner = pk.owner
                        AND pc.constraint_name = pk.constraint_name
                        AND pc.position = fc.position
WHERE fk.constraint_type = 'R'
ORDER BY fk.table_name, fk.constraint_name, fc.position;

-- Questão 4: geração do DDL
CREATE OR REPLACE PROCEDURE bdii_gerar_ddl AUTHID CURRENT_USER AS
    v_tipo VARCHAR2(100);
    v_separador VARCHAR2(2);

    FUNCTION ident(p_nome VARCHAR2) RETURN VARCHAR2 IS
    BEGIN
        RETURN DBMS_ASSERT.ENQUOTE_NAME(p_nome, FALSE);
    END;

    FUNCTION colunas(p_dono VARCHAR2, p_chave VARCHAR2) RETURN VARCHAR2 IS
        v_lista VARCHAR2(4000);
    BEGIN
        SELECT LISTAGG('"' || column_name || '"', ', ')
                   WITHIN GROUP (ORDER BY position)
          INTO v_lista
          FROM all_cons_columns
         WHERE owner = p_dono AND constraint_name = p_chave;
        RETURN v_lista;
    END;

BEGIN
    FOR tab IN (
        SELECT table_name
        FROM user_tables
        WHERE table_name NOT LIKE 'BDII\_%' ESCAPE '\'
        ORDER BY table_name
    ) LOOP
        DBMS_OUTPUT.PUT_LINE('CREATE TABLE ' || ident(tab.table_name) || ' (');
        v_separador := NULL;
        FOR col IN (
            SELECT column_name, data_type, data_precision, data_scale,
                   char_length, char_used, nullable
            FROM user_tab_columns
            WHERE table_name = tab.table_name
            ORDER BY column_id
        ) LOOP
            v_tipo := col.data_type;
            IF col.data_type IN ('VARCHAR2', 'CHAR') THEN
                v_tipo := v_tipo || '(' || col.char_length ||
                    CASE col.char_used WHEN 'C' THEN ' CHAR)' ELSE ' BYTE)' END;
            ELSIF col.data_type = 'NUMBER' AND col.data_precision IS NOT NULL THEN
                v_tipo := v_tipo || '(' || col.data_precision || ',' || col.data_scale || ')';
            ELSIF col.data_type = 'NUMBER' AND col.data_scale IS NOT NULL THEN
                v_tipo := v_tipo || '(*,' || col.data_scale || ')';
            ELSIF col.data_type NOT IN ('NUMBER', 'DATE') THEN
                RAISE_APPLICATION_ERROR(-20002, 'Tipo fora do escopo Chinook: ' || col.data_type);
            END IF;
            IF v_separador IS NOT NULL THEN
                DBMS_OUTPUT.PUT_LINE(',');
            END IF;

            DBMS_OUTPUT.PUT(
                '  ' || ident(col.column_name) || ' ' || v_tipo ||
                CASE col.nullable WHEN 'N' THEN ' NOT NULL' END
            );
            v_separador := ',';
        END LOOP;
        FOR pk IN (
            SELECT constraint_name
            FROM user_constraints
            WHERE table_name = tab.table_name
              AND constraint_type = 'P'
        ) LOOP
            DBMS_OUTPUT.PUT_LINE(',');
            DBMS_OUTPUT.PUT('  CONSTRAINT ' || ident(pk.constraint_name) || ' PRIMARY KEY (' ||
                colunas(USER, pk.constraint_name) || ')');
        END LOOP;
        DBMS_OUTPUT.NEW_LINE;
        DBMS_OUTPUT.PUT_LINE(');');
    END LOOP;

    -- As tabelas precisam existir antes de receber as FKs.
    FOR fk IN (
        SELECT c.table_name, c.constraint_name, c.delete_rule,
               p.owner, p.table_name AS tabela_pai, p.constraint_name AS chave_pai
        FROM user_constraints c
        JOIN all_constraints p ON p.owner = c.r_owner
                              AND p.constraint_name = c.r_constraint_name
        WHERE c.constraint_type = 'R'
          AND c.table_name NOT LIKE 'BDII\_%' ESCAPE '\'
        ORDER BY c.table_name, c.constraint_name
    ) LOOP
        DBMS_OUTPUT.PUT_LINE('ALTER TABLE ' || ident(fk.table_name) || ' ADD CONSTRAINT ' ||
            ident(fk.constraint_name) || ' FOREIGN KEY (' || colunas(USER, fk.constraint_name) ||
            ') REFERENCES ' || CASE WHEN fk.owner <> USER THEN ident(fk.owner) || '.' END ||
            ident(fk.tabela_pai) || ' (' || colunas(fk.owner, fk.chave_pai) || ')' ||
            CASE WHEN fk.delete_rule <> 'NO ACTION' THEN ' ON DELETE ' || fk.delete_rule END || ';');
    END LOOP;
END;
/

-- Questão 5: estados e transições de uma fatura
DECLARE
    PROCEDURE criar_tabela(p_nome VARCHAR2, p_ddl VARCHAR2) IS
        v_existe NUMBER;
    BEGIN
        SELECT COUNT(*) INTO v_existe FROM user_tables WHERE table_name = p_nome;
        IF v_existe = 0 THEN
            EXECUTE IMMEDIATE p_ddl;
        END IF;
    END;
BEGIN
    criar_tabela('BDII_DTE_ESTADO', q'[
        CREATE TABLE bdii_dte_estado (
            fluxo VARCHAR2(30) NOT NULL,
            estado VARCHAR2(30) NOT NULL,
            CONSTRAINT bdii_dte_estado_pk PRIMARY KEY (fluxo, estado)
        )
    ]');
    criar_tabela('BDII_DTE_INICIO', q'[
        CREATE TABLE bdii_dte_inicio (
            fluxo VARCHAR2(30) PRIMARY KEY,
            estado VARCHAR2(30) NOT NULL,
            CONSTRAINT bdii_dte_inicio_fk FOREIGN KEY (fluxo, estado)
                REFERENCES bdii_dte_estado (fluxo, estado)
        )
    ]');
    criar_tabela('BDII_DTE_TRANSICAO', q'[
        CREATE TABLE bdii_dte_transicao (
            fluxo VARCHAR2(30) NOT NULL,
            origem VARCHAR2(30) NOT NULL,
            destino VARCHAR2(30) NOT NULL,
            CONSTRAINT bdii_dte_transicao_pk PRIMARY KEY (fluxo, origem, destino),
            CONSTRAINT bdii_dte_origem_fk FOREIGN KEY (fluxo, origem)
                REFERENCES bdii_dte_estado (fluxo, estado),
            CONSTRAINT bdii_dte_destino_fk FOREIGN KEY (fluxo, destino)
                REFERENCES bdii_dte_estado (fluxo, estado)
        )
    ]');
    criar_tabela('BDII_STATUS_FATURA', q'[
        CREATE TABLE bdii_status_fatura (
            invoiceid NUMBER PRIMARY KEY REFERENCES invoice(invoiceid),
            estado VARCHAR2(30) NOT NULL
        )
    ]');
END;
/

CREATE OR REPLACE PROCEDURE bdii_validar_dte(
    p_fluxo IN VARCHAR2, p_anterior IN VARCHAR2, p_novo IN VARCHAR2,
    p_insercao IN BOOLEAN
) AUTHID DEFINER AS
    v_permitido NUMBER;
BEGIN
    IF p_insercao THEN
        SELECT COUNT(*) INTO v_permitido
        FROM bdii_dte_inicio
        WHERE fluxo = p_fluxo AND estado = p_novo;
    ELSIF p_anterior = p_novo THEN
        SELECT COUNT(*) INTO v_permitido
        FROM bdii_dte_estado
        WHERE fluxo = p_fluxo AND estado = p_novo;
    ELSE
        SELECT COUNT(*) INTO v_permitido
        FROM bdii_dte_transicao
        WHERE fluxo = p_fluxo
          AND origem = p_anterior
          AND destino = p_novo;
    END IF;
    IF v_permitido = 0 THEN
        RAISE_APPLICATION_ERROR(-20005, 'Estado inicial ou transicao invalida: ' ||
            p_fluxo || ' / ' || NVL(p_anterior, '(vazio)') || ' -> ' || NVL(p_novo, '(vazio)'));
    END IF;
END;
/

CREATE OR REPLACE TRIGGER bdii_status_fatura_trg
BEFORE INSERT OR UPDATE OF estado ON bdii_status_fatura
FOR EACH ROW
BEGIN
    bdii_validar_dte('FATURA', :OLD.estado, :NEW.estado, INSERTING);
END;
/

MERGE INTO bdii_dte_estado e
USING (
    SELECT 'FATURA' fluxo, 'ABERTA' estado FROM dual
    UNION ALL SELECT 'FATURA', 'PAGA' FROM dual
    UNION ALL SELECT 'FATURA', 'CANCELADA' FROM dual
) dados ON (e.fluxo = dados.fluxo AND e.estado = dados.estado)
WHEN NOT MATCHED THEN
    INSERT (fluxo, estado) VALUES (dados.fluxo, dados.estado);

MERGE INTO bdii_dte_inicio i
USING (SELECT 'FATURA' fluxo, 'ABERTA' estado FROM dual) dados
ON (i.fluxo = dados.fluxo)
WHEN NOT MATCHED THEN
    INSERT (fluxo, estado) VALUES (dados.fluxo, dados.estado);

MERGE INTO bdii_dte_transicao t
USING (
    SELECT 'FATURA' fluxo, 'ABERTA' origem, 'PAGA' destino FROM dual
    UNION ALL SELECT 'FATURA', 'ABERTA', 'CANCELADA' FROM dual
) dados ON (t.fluxo = dados.fluxo AND t.origem = dados.origem AND t.destino = dados.destino)
WHEN NOT MATCHED THEN
    INSERT (fluxo, origem, destino) VALUES (dados.fluxo, dados.origem, dados.destino);
COMMIT;

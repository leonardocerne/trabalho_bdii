SET SERVEROUTPUT ON SIZE UNLIMITED

DECLARE
    v_total NUMBER;
BEGIN
    SELECT COUNT(*) INTO v_total FROM user_objects
    WHERE object_name LIKE 'BDII\_%' ESCAPE '\' AND status <> 'VALID';
    IF v_total <> 0 THEN
        FOR e IN (SELECT name, line, text FROM user_errors ORDER BY name, sequence) LOOP
            DBMS_OUTPUT.PUT_LINE(e.name || ':' || e.line || ' ' || e.text);
        END LOOP;
        RAISE_APPLICATION_ERROR(-20900, 'Objetos invalidos.');
    END IF;
END;
/

CREATE TABLE bdii_teste_indice (
    id NUMBER CONSTRAINT bdii_teste_indice_pk PRIMARY KEY,
    codigo NUMBER CONSTRAINT bdii_teste_indice_uk UNIQUE,
    valor NUMBER
);
CREATE TABLE bdii_teste_indice_filho (
    id_pai NUMBER CONSTRAINT bdii_teste_indice_fk REFERENCES bdii_teste_indice(id)
);
CREATE INDEX bdii_teste_indice_ix ON bdii_teste_indice(valor);
EXEC bdii_remover_indices('bdii_teste_indice')
DECLARE
    v_total NUMBER;
BEGIN
    SELECT COUNT(*) INTO v_total FROM user_indexes WHERE table_name = 'BDII_TESTE_INDICE';
    IF v_total <> 0 THEN
        RAISE_APPLICATION_ERROR(-20901, 'Falha na remocao de indices.');
    END IF;
    SELECT COUNT(*) INTO v_total FROM user_constraints
    WHERE constraint_name IN ('BDII_TESTE_INDICE_PK', 'BDII_TESTE_INDICE_UK', 'BDII_TESTE_INDICE_FK')
      AND status = 'DISABLED';
    IF v_total <> 3 THEN
        RAISE_APPLICATION_ERROR(-20902, 'Esperava PK, UNIQUE e FK dependente desabilitadas.');
    END IF;
    DBMS_OUTPUT.PUT_LINE('OK: todos os indices removidos e restricoes dependentes desabilitadas.');
END;
/
DROP TABLE bdii_teste_indice_filho PURGE;
DROP TABLE bdii_teste_indice PURGE;

DECLARE
    v_id NUMBER;
BEGIN
    SELECT MIN(invoiceid) INTO v_id FROM invoice;
    BEGIN
        INSERT INTO bdii_status_fatura VALUES (v_id, 'PAGA');
        RAISE_APPLICATION_ERROR(-20903, 'Estado inicial invalido aceito.');
    EXCEPTION
        WHEN OTHERS THEN
            IF SQLCODE <> -20005 THEN
                RAISE;
            END IF;
    END;
    INSERT INTO bdii_status_fatura VALUES (v_id, 'ABERTA');
    UPDATE bdii_status_fatura SET estado = 'PAGA' WHERE invoiceid = v_id;
    BEGIN
        UPDATE bdii_status_fatura SET estado = 'CANCELADA' WHERE invoiceid = v_id;
        RAISE_APPLICATION_ERROR(-20904, 'Transicao de estado terminal aceita.');
    EXCEPTION
        WHEN OTHERS THEN
            IF SQLCODE <> -20005 THEN
                RAISE;
            END IF;
    END;
    ROLLBACK;
    DBMS_OUTPUT.PUT_LINE('OK: DTE aceita transicao prevista e rejeita estado inicial e transicao invalidos.');
END;
/

DECLARE
    v_cliente NUMBER;
    v_faixa NUMBER;
    v_preco NUMBER;
    v_total NUMBER;

    PROCEDURE conferir(p_id NUMBER, p_esperado NUMBER) IS
        v_atual NUMBER;
    BEGIN
        SELECT total INTO v_atual FROM invoice WHERE invoiceid = p_id;
        IF v_atual <> p_esperado THEN
            RAISE_APPLICATION_ERROR(-20905, 'Total divergente na fatura ' || p_id);
        END IF;
    END;
BEGIN
    SELECT COUNT(*) INTO v_total FROM invoice i
    WHERE i.total <> (SELECT NVL(SUM(l.quantity*l.unitprice),0) FROM invoiceline l
                      WHERE l.invoiceid = i.invoiceid);
    IF v_total <> 0 THEN
        RAISE_APPLICATION_ERROR(-20906, 'Carga inicial inconsistente.');
    END IF;
    SELECT MIN(customerid) INTO v_cliente FROM customer;
    SELECT trackid, unitprice INTO v_faixa, v_preco
    FROM track WHERE unitprice >= 0.50 ORDER BY trackid FETCH FIRST 1 ROW ONLY;

    INSERT INTO invoice (invoiceid, customerid, invoicedate, total) VALUES (-1, v_cliente, SYSDATE, 0);
    INSERT INTO invoice (invoiceid, customerid, invoicedate, total) VALUES (-2, v_cliente, SYSDATE, 0);
    BEGIN
        INSERT INTO invoiceline VALUES (-1, -1, v_faixa, v_preco + 1, 1);
        RAISE_APPLICATION_ERROR(-20907, 'Preco acima do catalogo aceito.');
    EXCEPTION
        WHEN OTHERS THEN
            IF SQLCODE <> -20101 THEN
                RAISE;
            END IF;
    END;
    INSERT INTO invoiceline VALUES (-1, -1, v_faixa, .50, 2);
    INSERT INTO invoiceline VALUES (-2, -1, v_faixa, .25, 1);
    conferir(-1, 1.25);
    UPDATE invoiceline SET quantity = quantity + 1 WHERE invoicelineid IN (-1, -2);
    conferir(-1, 2);
    UPDATE invoiceline SET invoiceid = -2, unitprice = .40 WHERE invoicelineid = -1;
    conferir(-1, .50);
    conferir(-2, 1.20);
    DELETE FROM invoiceline WHERE invoicelineid IN (-1, -2);
    conferir(-1, 0);
    conferir(-2, 0);
    BEGIN
        UPDATE invoice SET total = 1 WHERE invoiceid = -1;
        RAISE_APPLICATION_ERROR(-20908, 'Alteracao direta invalida aceita.');
    EXCEPTION
        WHEN OTHERS THEN
            IF SQLCODE <> -20105 THEN
                RAISE;
            END IF;
    END;
    BEGIN
        INSERT INTO invoice (invoiceid, customerid, invoicedate, total)
        VALUES (-3, v_cliente, SYSDATE, 1);
        RAISE_APPLICATION_ERROR(-20909, 'Fatura nova com total invalido aceita.');
    EXCEPTION
        WHEN OTHERS THEN
            IF SQLCODE <> -20105 THEN
                RAISE;
            END IF;
    END;
    ROLLBACK;
    DBMS_OUTPUT.PUT_LINE('OK: preco, carga inicial, inclusao, alteracao em lote, transferencia, exclusao e protecao de Total.');
END;
/

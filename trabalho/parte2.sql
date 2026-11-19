-- Questões 1 e 2: preço de venda limitado ao preço de catálogo
CREATE OR REPLACE TRIGGER bdii_preco_venda_trg
BEFORE INSERT OR UPDATE OF trackid, unitprice ON invoiceline
FOR EACH ROW
DECLARE
    v_preco track.unitprice%TYPE;
BEGIN
    SELECT unitprice INTO v_preco
    FROM track
    WHERE trackid = :NEW.trackid;

    IF :NEW.unitprice > v_preco THEN
        RAISE_APPLICATION_ERROR(-20101, 'O preco de venda supera o preco de catalogo.');
    END IF;
EXCEPTION
    WHEN NO_DATA_FOUND THEN
        RAISE_APPLICATION_ERROR(-20102, 'Faixa inexistente no catalogo.');
END;
/

-- Questões 1 e 3: duração mínima de 60 segundos na curadoria
CREATE OR REPLACE PROCEDURE bdii_incluir_faixa(
    p_playlist IN playlisttrack.playlistid%TYPE,
    p_faixa IN playlisttrack.trackid%TYPE
) AUTHID DEFINER AS
    v_duracao track.milliseconds%TYPE;
BEGIN
    SELECT milliseconds INTO v_duracao
    FROM track
    WHERE trackid = p_faixa;

    IF v_duracao < 60000 THEN
        RAISE_APPLICATION_ERROR(-20103, 'A faixa precisa ter pelo menos 60 segundos.');
    END IF;
    INSERT INTO playlisttrack (playlistid, trackid) VALUES (p_playlist, p_faixa);
EXCEPTION
    WHEN NO_DATA_FOUND THEN
        RAISE_APPLICATION_ERROR(-20104, 'Faixa inexistente no catalogo.');
END;
/

-- Questão 4: acertar os totais existentes antes de instalar os gatilhos
UPDATE invoice i
SET total = (
    SELECT NVL(SUM(l.unitprice * l.quantity), 0)
    FROM invoiceline l
    WHERE l.invoiceid = i.invoiceid
);

CREATE OR REPLACE TRIGGER bdii_validar_total_trg
BEFORE INSERT OR UPDATE OF total ON invoice
FOR EACH ROW
DECLARE
    v_esperado NUMBER;
BEGIN
    IF INSERTING THEN
        v_esperado := 0;
    ELSE
        SELECT NVL(SUM(unitprice * quantity), 0) INTO v_esperado
        FROM invoiceline
        WHERE invoiceid = :NEW.invoiceid;
    END IF;
    IF :NEW.total IS NULL OR :NEW.total <> v_esperado THEN
        RAISE_APPLICATION_ERROR(-20105, 'Total precisa ser igual a soma dos itens.');
    END IF;
END;
/

CREATE OR REPLACE TYPE bdii_fatura_ids AS TABLE OF NUMBER;
/

CREATE OR REPLACE TRIGGER bdii_recalcular_total_trg
FOR INSERT OR UPDATE OF invoiceid, unitprice, quantity OR DELETE ON invoiceline
COMPOUND TRIGGER
    v_faturas bdii_fatura_ids := bdii_fatura_ids();

    PROCEDURE registrar(p_fatura NUMBER) IS
    BEGIN
        v_faturas.EXTEND;
        v_faturas(v_faturas.LAST) := p_fatura;
    END;

    AFTER EACH ROW IS
    BEGIN
        IF DELETING OR UPDATING THEN
            registrar(:OLD.invoiceid);
        END IF;

        IF INSERTING OR UPDATING THEN
            registrar(:NEW.invoiceid);
        END IF;
    END AFTER EACH ROW;

    AFTER STATEMENT IS
        v_id invoice.invoiceid%TYPE;
        v_total NUMBER;
    BEGIN
        FOR f IN (
            SELECT DISTINCT column_value AS invoiceid
            FROM TABLE(v_faturas)
            ORDER BY invoiceid
        ) LOOP
            -- Bloqueia a fatura antes de somar os itens para ordenar recálculos concorrentes.
            SELECT invoiceid INTO v_id
            FROM invoice
            WHERE invoiceid = f.invoiceid
            FOR UPDATE;

            SELECT NVL(SUM(unitprice * quantity), 0) INTO v_total
            FROM invoiceline
            WHERE invoiceid = v_id;

            UPDATE invoice
            SET total = v_total
            WHERE invoiceid = v_id;
        END LOOP;
    END AFTER STATEMENT;
END;
/

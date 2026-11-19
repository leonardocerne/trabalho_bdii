-- Rodar como o usuario restrito, passando o nome do dono como argumento.
SET SERVEROUTPUT ON
DECLARE
    v_dono VARCHAR2(128) := DBMS_ASSERT.SIMPLE_SQL_NAME(UPPER('&1'));
BEGIN
    EXECUTE IMMEDIATE 'BEGIN ' || v_dono || '.bdii_incluir_faixa(-9100, -9100); END;';
    BEGIN
        EXECUTE IMMEDIATE 'BEGIN ' || v_dono || '.bdii_incluir_faixa(-9100, -9101); END;';
        RAISE_APPLICATION_ERROR(-20910, 'Procedure aceitou faixa curta.');
    EXCEPTION
        WHEN OTHERS THEN
            IF SQLCODE <> -20103 THEN
                RAISE;
            END IF;
    END;
    BEGIN
        EXECUTE IMMEDIATE 'INSERT INTO ' || v_dono || '.playlisttrack VALUES (-9100, -9101)';
        RAISE_APPLICATION_ERROR(-20911, 'Usuario restrito conseguiu inserir diretamente.');
    EXCEPTION
        WHEN OTHERS THEN
            IF SQLCODE NOT IN (-942, -1031) THEN
                RAISE;
            END IF;
    END;
    ROLLBACK;
    DBMS_OUTPUT.PUT_LINE('OK: EXECUTE autorizado, faixa curta rejeitada e INSERT direto bloqueado.');
END;
/

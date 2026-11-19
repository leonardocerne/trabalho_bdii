INSERT INTO playlist (playlistid, name) VALUES (-9100, 'Teste de curadoria BDII');
INSERT INTO track (trackid, name, mediatypeid, milliseconds, unitprice)
SELECT -9100, 'Faixa de 60 segundos', MIN(mediatypeid), 60000, 1 FROM mediatype;
INSERT INTO track (trackid, name, mediatypeid, milliseconds, unitprice)
SELECT -9101, 'Faixa de 30 segundos', MIN(mediatypeid), 30000, 1 FROM mediatype;
COMMIT;

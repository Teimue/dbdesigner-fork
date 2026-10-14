-- =============================================================================
-- Beispiel-Datenbank fuer SQLite 3 (ab 3.37 wegen STRICT, getestet mit 3.53)
-- Ein kleiner Webshop, der die wichtigen SQL-Konstrukte und Datentypen von
-- SQLite zeigt. Zum Reverse Engineering in DBDesigner Fork:
--   Database > Reverse Engineering, Treiber SQLite, Datei beispiel.sqlite
--
-- Erzeugen der Datenbank (sqlite3-Kommandozeile):
--   sqlite3 beispiel.sqlite < beispiel_sqlite.sql
-- =============================================================================

PRAGMA foreign_keys = ON;

BEGIN TRANSACTION;

-- -----------------------------------------------------------------------------
-- Alle Typnamen, die SQLite kennt, und ihre Affinitaet (INTEGER, TEXT, BLOB,
-- REAL, NUMERIC). SQLite speichert den deklarierten Typ nur als Text, die
-- Affinitaet ergibt sich aus Teilen des Namens.
-- -----------------------------------------------------------------------------
CREATE TABLE datentypen (
  id                INTEGER PRIMARY KEY,           -- Alias fuer ROWID
  -- INTEGER-Affinitaet
  t_int             INT,
  t_integer         INTEGER,
  t_tinyint         TINYINT,
  t_smallint        SMALLINT,
  t_mediumint       MEDIUMINT,
  t_bigint          BIGINT,
  t_unsigned_bigint UNSIGNED BIG INT,
  t_int2            INT2,
  t_int8            INT8,
  -- TEXT-Affinitaet
  t_character       CHARACTER(20),
  t_char            CHAR(10),
  t_varchar         VARCHAR(255),
  t_varying_char    VARYING CHARACTER(255),
  t_nchar           NCHAR(55),
  t_native_char     NATIVE CHARACTER(70),
  t_nvarchar        NVARCHAR(100),
  t_text            TEXT,
  t_clob            CLOB,
  -- BLOB-Affinitaet (auch: kein Typ angegeben)
  t_blob            BLOB,
  t_ohne_typ,
  -- REAL-Affinitaet
  t_real            REAL,
  t_double          DOUBLE,
  t_double_prec     DOUBLE PRECISION,
  t_float           FLOAT,
  -- NUMERIC-Affinitaet
  t_numeric         NUMERIC,
  t_decimal         DECIMAL(10,5),
  t_boolean         BOOLEAN,
  t_date            DATE,
  t_datetime        DATETIME,
  t_time            TIME,
  t_timestamp       TIMESTAMP
);

-- -----------------------------------------------------------------------------
-- Kategorie: Selbstbezug (Baum), UNIQUE mit Kollation, CHECK
-- -----------------------------------------------------------------------------
CREATE TABLE kategorie (
  kategorie_id   INTEGER PRIMARY KEY AUTOINCREMENT,
  eltern_id      INTEGER REFERENCES kategorie(kategorie_id)
                   ON DELETE SET NULL ON UPDATE CASCADE,
  name           VARCHAR(80) NOT NULL COLLATE NOCASE,
  sortierung     SMALLINT NOT NULL DEFAULT 0 CHECK (sortierung >= 0),
  aktiv          BOOLEAN NOT NULL DEFAULT 1 CHECK (aktiv IN (0, 1)),
  CONSTRAINT uq_kategorie_name UNIQUE (eltern_id, name)
);

-- -----------------------------------------------------------------------------
-- Artikel: generierte Spalten (VIRTUAL und STORED), Defaults mit Ausdruck,
-- benannte CHECK-Constraints, JSON in TEXT, ON CONFLICT-Klausel
-- -----------------------------------------------------------------------------
CREATE TABLE artikel (
  artikel_id     INTEGER PRIMARY KEY AUTOINCREMENT,
  artikelnr      CHAR(12) NOT NULL UNIQUE ON CONFLICT ABORT,
  kategorie_id   INTEGER NOT NULL,
  bezeichnung    VARCHAR(200) NOT NULL,
  beschreibung   TEXT,
  netto_preis    DECIMAL(10,2) NOT NULL DEFAULT 0.00,
  mwst_satz      NUMERIC(4,2) NOT NULL DEFAULT 19.00,
  brutto_preis   DECIMAL(10,2) GENERATED ALWAYS AS
                   (round(netto_preis * (1 + mwst_satz / 100.0), 2)) VIRTUAL,
  gewicht_kg     REAL,
  versandklasse  TEXT GENERATED ALWAYS AS
                   (CASE WHEN gewicht_kg IS NULL THEN 'unbekannt'
                         WHEN gewicht_kg <= 2 THEN 'Paeckchen'
                         ELSE 'Paket' END) STORED,
  eigenschaften  TEXT CHECK (eigenschaften IS NULL OR json_valid(eigenschaften)),
  bild           BLOB,
  angelegt_am    DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  geaendert_am   DATETIME DEFAULT (strftime('%Y-%m-%d %H:%M:%f', 'now')),
  CONSTRAINT ck_artikel_preis CHECK (netto_preis >= 0),
  CONSTRAINT ck_artikel_mwst  CHECK (mwst_satz IN (0, 7, 19)),
  CONSTRAINT fk_artikel_kategorie FOREIGN KEY (kategorie_id)
    REFERENCES kategorie (kategorie_id) ON DELETE RESTRICT ON UPDATE CASCADE
);

-- Normaler, eindeutiger, absteigender, partieller und Ausdrucks-Index
CREATE INDEX idx_artikel_kategorie ON artikel (kategorie_id);
CREATE INDEX idx_artikel_preis ON artikel (netto_preis DESC, bezeichnung ASC);
CREATE UNIQUE INDEX idx_artikel_bez_nocase ON artikel (bezeichnung COLLATE NOCASE, kategorie_id);
CREATE INDEX idx_artikel_schwer ON artikel (gewicht_kg) WHERE gewicht_kg > 30;
CREATE INDEX idx_artikel_lower ON artikel (lower(bezeichnung));

-- -----------------------------------------------------------------------------
-- Schlagwort und n:m-Zuordnung: WITHOUT ROWID, zusammengesetzter Primaerschluessel,
-- beide Fremdschluessel ON DELETE CASCADE
-- -----------------------------------------------------------------------------
CREATE TABLE schlagwort (
  schlagwort_id  INTEGER PRIMARY KEY,
  wort           TEXT NOT NULL UNIQUE COLLATE NOCASE
);

CREATE TABLE artikel_schlagwort (
  artikel_id     INTEGER NOT NULL REFERENCES artikel (artikel_id) ON DELETE CASCADE,
  schlagwort_id  INTEGER NOT NULL REFERENCES schlagwort (schlagwort_id) ON DELETE CASCADE,
  gewichtung     INTEGER NOT NULL DEFAULT 1,
  PRIMARY KEY (artikel_id, schlagwort_id)
) WITHOUT ROWID;

-- -----------------------------------------------------------------------------
-- Kunde: STRICT-Tabelle (nur INT, INTEGER, REAL, TEXT, BLOB, ANY erlaubt),
-- Selbstbezug (Werber), NOT NULL ON CONFLICT, CHECK mit LIKE/GLOB
-- -----------------------------------------------------------------------------
CREATE TABLE kunde (
  kunde_id       INTEGER PRIMARY KEY AUTOINCREMENT,
  kundennr       TEXT NOT NULL UNIQUE CHECK (kundennr GLOB 'K[0-9][0-9][0-9][0-9][0-9]'),
  anrede         TEXT CHECK (anrede IN ('Herr', 'Frau', 'Divers')),
  vorname        TEXT,
  nachname       TEXT NOT NULL ON CONFLICT FAIL,
  email          TEXT NOT NULL COLLATE NOCASE CHECK (email LIKE '%_@_%._%'),
  geburtsdatum   TEXT CHECK (geburtsdatum IS NULL OR date(geburtsdatum) = geburtsdatum),
  bonuspunkte    INT NOT NULL DEFAULT 0,
  rabatt         REAL NOT NULL DEFAULT 0.0 CHECK (rabatt BETWEEN 0 AND 0.5),
  zusatzdaten    ANY,
  avatar         BLOB,
  werber_id      INTEGER,
  CONSTRAINT uq_kunde_email UNIQUE (email),
  CONSTRAINT fk_kunde_werber FOREIGN KEY (werber_id)
    REFERENCES kunde (kunde_id) ON DELETE SET NULL
) STRICT;

-- -----------------------------------------------------------------------------
-- Adresse: 1:n zu Kunde, Default per Ausdruck, CHECK ueber mehrere Spalten
-- -----------------------------------------------------------------------------
CREATE TABLE adresse (
  adresse_id     INTEGER PRIMARY KEY,
  kunde_id       INTEGER NOT NULL,
  art            CHAR(1) NOT NULL DEFAULT 'L' CHECK (art IN ('L', 'R')),  -- Liefer-/Rechnungsadresse
  strasse        VARCHAR(100) NOT NULL,
  plz            VARCHAR(10) NOT NULL,
  ort            VARCHAR(80) NOT NULL,
  land           CHAR(2) NOT NULL DEFAULT 'DE' COLLATE NOCASE,
  gueltig_ab     DATE NOT NULL DEFAULT (date('now')),
  gueltig_bis    DATE,
  CHECK (gueltig_bis IS NULL OR gueltig_bis >= gueltig_ab),
  FOREIGN KEY (kunde_id) REFERENCES kunde (kunde_id) ON DELETE CASCADE ON UPDATE CASCADE
);
CREATE INDEX idx_adresse_kunde ON adresse (kunde_id, art);
CREATE INDEX idx_adresse_plz ON adresse (land, plz);

-- -----------------------------------------------------------------------------
-- Bestellung: Fremdschluessel DEFERRABLE INITIALLY DEFERRED, Status per CHECK
-- -----------------------------------------------------------------------------
CREATE TABLE bestellung (
  bestellung_id  INTEGER PRIMARY KEY AUTOINCREMENT,
  kunde_id       INTEGER NOT NULL,
  lieferadresse_id INTEGER,
  bestellt_am    DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  status         VARCHAR(12) NOT NULL DEFAULT 'neu'
                   CHECK (status IN ('neu', 'bezahlt', 'versandt', 'storniert')),
  summe_netto    DECIMAL(12,2) NOT NULL DEFAULT 0,
  bemerkung      CLOB,
  CONSTRAINT fk_bestellung_kunde FOREIGN KEY (kunde_id)
    REFERENCES kunde (kunde_id) ON DELETE RESTRICT
    DEFERRABLE INITIALLY DEFERRED,
  CONSTRAINT fk_bestellung_adresse FOREIGN KEY (lieferadresse_id)
    REFERENCES adresse (adresse_id) ON DELETE SET NULL
);
CREATE INDEX idx_bestellung_kunde ON bestellung (kunde_id, bestellt_am DESC);
CREATE INDEX idx_bestellung_offen ON bestellung (bestellt_am) WHERE status IN ('neu', 'bezahlt');

-- -----------------------------------------------------------------------------
-- Bestellposition: identifizierende Beziehung (PK enthaelt FK), Generated Column
-- -----------------------------------------------------------------------------
CREATE TABLE bestellposition (
  bestellung_id  INTEGER NOT NULL,
  pos_nr         SMALLINT NOT NULL CHECK (pos_nr > 0),
  artikel_id     INTEGER NOT NULL,
  menge          INTEGER NOT NULL DEFAULT 1 CHECK (menge > 0),
  einzelpreis    DECIMAL(10,2) NOT NULL,
  rabatt_prozent NUMERIC(5,2) NOT NULL DEFAULT 0,
  gesamtpreis    DECIMAL(12,2) AS (round(menge * einzelpreis * (1 - rabatt_prozent / 100.0), 2)),
  PRIMARY KEY (bestellung_id, pos_nr),
  FOREIGN KEY (bestellung_id) REFERENCES bestellung (bestellung_id) ON DELETE CASCADE,
  FOREIGN KEY (artikel_id) REFERENCES artikel (artikel_id) ON DELETE RESTRICT ON UPDATE CASCADE
);
CREATE INDEX idx_position_artikel ON bestellposition (artikel_id);

-- -----------------------------------------------------------------------------
-- Lieferung: zusammengesetzter Fremdschluessel auf Bestellposition
-- -----------------------------------------------------------------------------
CREATE TABLE lieferung (
  lieferung_id   INTEGER PRIMARY KEY,
  bestellung_id  INTEGER NOT NULL,
  pos_nr         SMALLINT NOT NULL,
  geliefert_am   DATETIME,
  sendungsnr     VARCHAR(40) UNIQUE,
  menge          INTEGER NOT NULL CHECK (menge > 0),
  FOREIGN KEY (bestellung_id, pos_nr)
    REFERENCES bestellposition (bestellung_id, pos_nr)
    ON DELETE CASCADE ON UPDATE NO ACTION
);
CREATE INDEX idx_lieferung_position ON lieferung (bestellung_id, pos_nr);

-- -----------------------------------------------------------------------------
-- Lagerbestand: 1:1 zu Artikel (PK = FK), Default-Ausdruck
-- -----------------------------------------------------------------------------
CREATE TABLE lagerbestand (
  artikel_id     INTEGER PRIMARY KEY REFERENCES artikel (artikel_id) ON DELETE CASCADE,
  bestand        INTEGER NOT NULL DEFAULT 0 CHECK (bestand >= 0),
  mindestbestand INTEGER NOT NULL DEFAULT 5,
  lagerort       VARCHAR(20) DEFAULT 'Hauptlager',
  letzte_inventur DATE
);

-- -----------------------------------------------------------------------------
-- Protokoll: wird nur von Triggern beschrieben, keine Beziehungen
-- -----------------------------------------------------------------------------
CREATE TABLE protokoll (
  protokoll_id   INTEGER PRIMARY KEY AUTOINCREMENT,
  tabelle        TEXT NOT NULL,
  aktion         TEXT NOT NULL CHECK (aktion IN ('INSERT', 'UPDATE', 'DELETE')),
  schluessel     INTEGER,
  alt            TEXT,
  neu            TEXT,
  zeitpunkt      DATETIME NOT NULL DEFAULT (datetime('now', 'localtime'))
);

-- =============================================================================
-- Views
-- =============================================================================
CREATE VIEW v_bestelluebersicht AS
  SELECT b.bestellung_id, k.kundennr, k.nachname, b.bestellt_am, b.status,
         count(p.pos_nr) AS positionen,
         round(coalesce(sum(p.gesamtpreis), 0), 2) AS summe
    FROM bestellung b
    JOIN kunde k ON k.kunde_id = b.kunde_id
    LEFT JOIN bestellposition p ON p.bestellung_id = b.bestellung_id
   GROUP BY b.bestellung_id;

-- Rekursive CTE und Fensterfunktion
CREATE VIEW v_kategoriepfad AS
  WITH RECURSIVE pfad (kategorie_id, name, pfad, tiefe) AS (
    SELECT kategorie_id, name, name, 0 FROM kategorie WHERE eltern_id IS NULL
    UNION ALL
    SELECT k.kategorie_id, k.name, p.pfad || ' > ' || k.name, p.tiefe + 1
      FROM kategorie k JOIN pfad p ON k.eltern_id = p.kategorie_id
  )
  SELECT kategorie_id, pfad, tiefe,
         row_number() OVER (PARTITION BY tiefe ORDER BY pfad) AS nr
    FROM pfad;

-- =============================================================================
-- Trigger
-- =============================================================================
CREATE TRIGGER trg_artikel_geaendert
AFTER UPDATE OF netto_preis, bezeichnung ON artikel
FOR EACH ROW WHEN old.netto_preis <> new.netto_preis OR old.bezeichnung <> new.bezeichnung
BEGIN
  UPDATE artikel SET geaendert_am = strftime('%Y-%m-%d %H:%M:%f', 'now')
   WHERE artikel_id = new.artikel_id;
  INSERT INTO protokoll (tabelle, aktion, schluessel, alt, neu)
  VALUES ('artikel', 'UPDATE', new.artikel_id,
          json_object('preis', old.netto_preis, 'bez', old.bezeichnung),
          json_object('preis', new.netto_preis, 'bez', new.bezeichnung));
END;

CREATE TRIGGER trg_position_summe
AFTER INSERT ON bestellposition
BEGIN
  UPDATE bestellung
     SET summe_netto = (SELECT sum(gesamtpreis) FROM bestellposition
                         WHERE bestellung_id = new.bestellung_id)
   WHERE bestellung_id = new.bestellung_id;
END;

CREATE TRIGGER trg_bestellung_storno
BEFORE UPDATE OF status ON bestellung
WHEN old.status = 'versandt' AND new.status = 'storniert'
BEGIN
  SELECT RAISE(ABORT, 'Versandte Bestellungen koennen nicht storniert werden');
END;

CREATE TRIGGER trg_kunde_geloescht
AFTER DELETE ON kunde
BEGIN
  INSERT INTO protokoll (tabelle, aktion, schluessel, alt)
  VALUES ('kunde', 'DELETE', old.kunde_id, old.kundennr || ' ' || old.nachname);
END;

-- INSTEAD OF-Trigger auf einer View
CREATE TRIGGER trg_v_bestelluebersicht_status
INSTEAD OF UPDATE OF status ON v_bestelluebersicht
BEGIN
  UPDATE bestellung SET status = new.status WHERE bestellung_id = old.bestellung_id;
END;

-- =============================================================================
-- Beispieldaten
-- =============================================================================
INSERT INTO kategorie (kategorie_id, eltern_id, name, sortierung) VALUES
  (1, NULL, 'Buecher', 1),
  (2, 1,    'Fachbuecher', 1),
  (3, 1,    'Romane', 2),
  (4, NULL, 'Elektronik', 2),
  (5, 4,    'Kabel', 1);

INSERT INTO artikel (artikelnr, kategorie_id, bezeichnung, netto_preis, mwst_satz,
                     gewicht_kg, eigenschaften, bild) VALUES
  ('B-0000000001', 2, 'SQL fuer Einsteiger', 24.90, 7, 0.6,
   '{"seiten": 320, "isbn": "978-3-00-000000-1"}', NULL),
  ('B-0000000002', 3, 'Der lange Weg', 12.00, 7, 0.4, NULL, NULL),
  ('E-0000000001', 5, 'USB-C Kabel 2 m', 8.40, 19, 0.1,
   '{"farbe": "schwarz", "laenge_m": 2}', x'89504E470D0A1A0A'),
  ('E-0000000002', 4, 'Monitor 27 Zoll', 249.00, 19, 6.8, NULL, NULL);

INSERT INTO schlagwort (schlagwort_id, wort) VALUES (1, 'Datenbank'), (2, 'Bestseller'), (3, 'Zubehoer');
INSERT INTO artikel_schlagwort (artikel_id, schlagwort_id, gewichtung) VALUES
  (1, 1, 3), (1, 2, 1), (2, 2, 2), (3, 3, 1);

INSERT INTO kunde (kundennr, anrede, vorname, nachname, email, geburtsdatum,
                   bonuspunkte, rabatt, zusatzdaten, werber_id) VALUES
  ('K00001', 'Frau', 'Anna', 'Muster', 'anna@example.com', '1985-03-14', 120, 0.05, 'Stammkundin', NULL),
  ('K00002', 'Herr', 'Bernd', 'Beispiel', 'bernd@example.com', NULL, 0, 0, 42, 1),
  ('K00003', 'Divers', 'Chris', 'Test', 'chris@example.org', '1999-12-31', 15, 0.1, x'00FF', 1);

INSERT INTO adresse (kunde_id, art, strasse, plz, ort, gueltig_ab) VALUES
  (1, 'L', 'Hauptstrasse 1', '10115', 'Berlin', '2020-01-01'),
  (1, 'R', 'Postfach 12 34', '10117', 'Berlin', '2020-01-01'),
  (2, 'L', 'Am Markt 5', '80331', 'Muenchen', '2023-06-01');

INSERT INTO bestellung (kunde_id, lieferadresse_id, status, bemerkung) VALUES
  (1, 1, 'bezahlt', 'Bitte beim Nachbarn abgeben'),
  (2, 3, 'neu', NULL);

INSERT INTO bestellposition (bestellung_id, pos_nr, artikel_id, menge, einzelpreis, rabatt_prozent) VALUES
  (1, 1, 1, 2, 24.90, 0),
  (1, 2, 3, 3, 8.40, 10),
  (2, 1, 4, 1, 249.00, 0);

INSERT INTO lieferung (bestellung_id, pos_nr, geliefert_am, sendungsnr, menge) VALUES
  (1, 1, '2026-10-01 14:30:00', 'DHL-000123', 2);

INSERT INTO lagerbestand (artikel_id, bestand, mindestbestand, letzte_inventur) VALUES
  (1, 40, 5, '2026-01-02'), (2, 3, 5, '2026-01-02'), (3, 500, 50, NULL), (4, 7, 2, NULL);

INSERT INTO datentypen (t_int, t_integer, t_tinyint, t_smallint, t_mediumint, t_bigint,
  t_unsigned_bigint, t_int2, t_int8, t_character, t_char, t_varchar, t_varying_char,
  t_nchar, t_native_char, t_nvarchar, t_text, t_clob, t_blob, t_ohne_typ, t_real,
  t_double, t_double_prec, t_float, t_numeric, t_decimal, t_boolean, t_date,
  t_datetime, t_time, t_timestamp)
VALUES (1, 2, 127, 32767, 8388607, 9223372036854775807, 9223372036854775807, 3, 4,
  'Zeichen', 'char', 'varchar', 'varying', 'nchar', 'native', 'nvarchar', 'Text',
  'Ein langer Text', x'DEADBEEF', 'beliebig', 3.14, 2.718281828, 1.4142135623,
  1.5e10, 123.456, 12345.67890, 1, '2026-10-14', '2026-10-14 12:00:00', '12:00:00',
  '2026-10-14T12:00:00Z');

COMMIT;

BEGIN;

ALTER TABLE jogos
    ADD COLUMN IF NOT EXISTS capa_url TEXT,
    ADD COLUMN IF NOT EXISTS status TEXT NOT NULL DEFAULT 'quero-jogar'
        CHECK (status IN ('quero-jogar', 'jogando', 'jogados')),
    ADD COLUMN IF NOT EXISTS nota NUMERIC
        CHECK (nota BETWEEN 0 AND 5 AND mod(nota * 2, 1) = 0),
    ADD COLUMN IF NOT EXISTS review VARCHAR(2000),
    ADD COLUMN IF NOT EXISTS cheapshark_id VARCHAR(12) UNIQUE;

COMMIT;

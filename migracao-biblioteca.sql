BEGIN;

ALTER TABLE jogos
    ADD COLUMN IF NOT EXISTS status TEXT NOT NULL DEFAULT 'quero-jogar'
        CHECK (status IN ('quero-jogar', 'jogando', 'jogados')),
    ADD COLUMN IF NOT EXISTS nota NUMERIC
        CHECK (nota BETWEEN 0 AND 5 AND mod(nota * 2, 1) = 0),
    ADD COLUMN IF NOT EXISTS review VARCHAR(2000);

-- Bancos de versões antigas exigiam valores em duas colunas hoje inativas.
SELECT format('ALTER TABLE jogos ALTER COLUMN %I DROP NOT NULL', column_name)
FROM information_schema.columns
WHERE table_schema = current_schema()
  AND table_name = 'jogos'
  AND column_name IN ('genero', 'plataforma')
  AND is_nullable = 'NO'
\gexec

COMMIT;

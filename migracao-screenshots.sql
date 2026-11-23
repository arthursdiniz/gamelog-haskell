BEGIN;

ALTER TABLE jogos
    ALTER COLUMN genero DROP NOT NULL,
    ALTER COLUMN plataforma DROP NOT NULL;

CREATE TABLE IF NOT EXISTS screenshots (
    id SERIAL PRIMARY KEY,
    jogo_id INTEGER NOT NULL REFERENCES jogos(id) ON DELETE CASCADE,
    caminho TEXT NOT NULL UNIQUE
);

CREATE INDEX IF NOT EXISTS screenshots_jogo_id_idx ON screenshots(jogo_id);

COMMIT;

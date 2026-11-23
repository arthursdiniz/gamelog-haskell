CREATE TABLE jogos (
    id SERIAL PRIMARY KEY,
    nome VARCHAR(100) NOT NULL,
    genero VARCHAR(50),
    plataforma VARCHAR(50),
    capa_url TEXT,
    status TEXT NOT NULL DEFAULT 'quero-jogar'
        CHECK (status IN ('quero-jogar', 'jogando', 'jogados')),
    nota NUMERIC CHECK (nota BETWEEN 0 AND 5 AND mod(nota * 2, 1) = 0),
    review VARCHAR(2000),
    cheapshark_id VARCHAR(12) UNIQUE
);

CREATE TABLE screenshots (
    id SERIAL PRIMARY KEY,
    jogo_id INTEGER NOT NULL REFERENCES jogos(id) ON DELETE CASCADE,
    caminho TEXT NOT NULL UNIQUE
);

CREATE INDEX screenshots_jogo_id_idx ON screenshots(jogo_id);

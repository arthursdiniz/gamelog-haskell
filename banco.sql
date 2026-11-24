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

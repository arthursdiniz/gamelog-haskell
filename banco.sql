CREATE TABLE jogos (
    id SERIAL PRIMARY KEY,
    nome VARCHAR(100) NOT NULL,
    genero VARCHAR(50) NOT NULL,
    plataforma VARCHAR(50) NOT NULL
);

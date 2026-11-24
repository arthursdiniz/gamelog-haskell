-- Desvincula o acervo antigo para que excluir um jogo preserve os registros legados.
ALTER TABLE IF EXISTS public.screenshots
    DROP CONSTRAINT IF EXISTS screenshots_jogo_id_fkey;

const caminhoAPI = "/api/jogos";
const categorias = {
    "quero-jogar": "Quero jogar",
    jogando: "Jogando",
    jogados: "Jogados"
};

async function requisitar(caminho, metodo = "GET", dados) {
    const opcoes = { method: metodo, cache: "no-store" };
    if (dados !== undefined) {
        opcoes.headers = { "Content-Type": "application/json" };
        opcoes.body = JSON.stringify(dados);
    }

    let resposta;
    try {
        resposta = await fetch(caminho, opcoes);
    } catch {
        throw new Error("Não foi possível acessar o servidor. Tente novamente.");
    }
    if (!resposta.ok) {
        const corpo = await resposta.json().catch(() => null);
        throw new Error(corpo?.erro || "Não foi possível concluir a operação.");
    }
    if (resposta.status !== 204) return resposta.json();
}

function mostrarMensagem(elemento, texto, erro = false) {
    elemento.textContent = texto;
    elemento.classList.toggle("erro", erro);
}

function preencherEstrelas(elemento, nota) {
    elemento.style.setProperty("--nota", (Number(nota) * 20) + "%");
}

function mostrarJogo(elemento, jogo, seletorTitulo) {
    elemento.dataset.status = jogo.status;
    elemento.querySelector(".categoria").textContent = categorias[jogo.status];
    elemento.querySelector(seletorTitulo).textContent = jogo.nome;

    const nota = elemento.querySelector(".nota");
    nota.textContent = "Sem nota";
    if (jogo.nota != null) {
        const estrelas = document.createElement("span");
        estrelas.className = "estrelas-nota";
        estrelas.textContent = "★★★★★";
        estrelas.setAttribute("aria-hidden", "true");
        preencherEstrelas(estrelas, jogo.nota);
        nota.replaceChildren(estrelas, jogo.nota.toLocaleString("pt-BR") + " / 5");
    }
}

function montarEstrelas(formulario) {
    const campoNota = formulario.elements.nota;
    const seletor = formulario.querySelector("#seletor-estrelas");
    const estrelas = document.createElement("span");
    estrelas.className = "estrelas-nota";
    estrelas.setAttribute("aria-hidden", "true");
    for (let i = 0; i < 5; i++) {
        const estrela = document.createElement("span");
        estrela.textContent = "★";
        estrelas.append(estrela);
    }

    const metades = document.createElement("div");
    metades.className = "metades";
    for (let metade = 1; metade <= 10; metade++) {
        const botao = document.createElement("button");
        const valor = String(metade / 2);
        botao.type = "button";
        botao.value = valor;
        botao.title = "Dar " + valor.replace(".", ",") + " estrelas";
        botao.setAttribute("aria-label", botao.title);
        botao.addEventListener("pointerenter", () => preencherEstrelas(estrelas, valor));
        botao.addEventListener("click", () => {
            campoNota.value = valor;
            atualizarEstrelas();
        });
        metades.append(botao);
    }

    function atualizarEstrelas() {
        preencherEstrelas(estrelas, campoNota.value);
        for (const botao of metades.children) {
            botao.setAttribute("aria-pressed", botao.value === campoNota.value);
        }
    }

    seletor.append(estrelas, metades);
    seletor.addEventListener("pointerleave", atualizarEstrelas);
    campoNota.addEventListener("change", atualizarEstrelas);
    atualizarEstrelas();
}

function montarFormulario(destino, jogo, enviar) {
    const modelo = document.querySelector("#modelo-formulario");
    const formulario = modelo.content.firstElementChild.cloneNode(true);
    const campos = formulario.elements;
    const botao = formulario.querySelector("button[type=submit]");
    const mensagem = formulario.querySelector(".mensagem");
    botao.textContent = jogo ? "Salvar alterações" : "Adicionar à biblioteca";

    if (jogo) {
        campos.nome.value = jogo.nome;
        campos.status.value = jogo.status;
        campos.nota.value = jogo.nota ?? "";
        campos.review.value = jogo.review ?? "";
    }
    montarEstrelas(formulario);
    destino.append(formulario);

    formulario.addEventListener("submit", async (evento) => {
        evento.preventDefault();
        if (botao.disabled) return;
        const dados = {
            nome: campos.nome.value.trim(),
            status: campos.status.value,
            nota: campos.nota.value === "" ? null : Number(campos.nota.value),
            review: campos.review.value.trim() || null
        };

        botao.disabled = true;
        mostrarMensagem(mensagem, jogo ? "Salvando…" : "Cadastrando…");
        try {
            await enviar(dados);
            if (!jogo) {
                formulario.reset();
                campos.nota.dispatchEvent(new Event("change"));
            }
            mostrarMensagem(mensagem, jogo ? "Alterações salvas." : "Jogo adicionado.");
        } catch (erro) {
            mostrarMensagem(mensagem, erro.message, true);
        } finally {
            botao.disabled = false;
        }
    });
}

function abrirBiblioteca() {
    const pagina = document.querySelector("#pagina-biblioteca");
    const lista = document.querySelector("#lista-jogos");
    const modelo = document.querySelector("#modelo-card");
    const filtroNome = document.querySelector("#filtro-nome");
    const botoes = document.querySelectorAll(".filtros-categorias button");
    const vazio = document.querySelector("#filtro-vazio");
    const total = document.querySelector(".total-biblioteca");
    const situacao = document.querySelector("#situacao-biblioteca");
    let categoria = "";
    let carregada = false;

    function filtrar() {
        if (!carregada) return;
        const termo = filtroNome.value.trim().toLocaleLowerCase("pt-BR");
        let encontrados = 0;
        for (const card of lista.children) {
            const nomeCombina = card.dataset.nome.includes(termo);
            const categoriaCombina = categoria === "" || card.dataset.status === categoria;
            card.hidden = !nomeCombina || !categoriaCombina;
            if (!card.hidden) encontrados++;
        }
        vazio.hidden = encontrados !== 0;
        vazio.textContent = lista.children.length === 0
            ? "Sua biblioteca está vazia."
            : "Nenhum jogo corresponde aos filtros.";
        document.querySelector("#total-jogos").textContent = encontrados.toLocaleString("pt-BR");
        document.querySelector("#rotulo-total").textContent = encontrados === 1 ? "jogo" : "jogos";
        total.hidden = false;
    }

    async function carregarJogos() {
        situacao.hidden = false;
        mostrarMensagem(situacao, "Carregando biblioteca…");
        try {
            const jogos = await requisitar(caminhoAPI);
            const cards = document.createDocumentFragment();
            for (const jogo of jogos) {
                const card = modelo.content.firstElementChild.cloneNode(true);
                card.dataset.nome = jogo.nome.toLocaleLowerCase("pt-BR");
                card.querySelector("a").href = "/jogos/" + jogo.id;
                mostrarJogo(card, jogo, "h3");
                cards.append(card);
            }
            lista.replaceChildren(cards);
            carregada = true;
            filtrar();
            situacao.hidden = true;
        } catch (erro) {
            mostrarMensagem(situacao, erro.message, true);
        }
    }

    for (const botao of botoes) {
        botao.addEventListener("click", () => {
            categoria = botao.value;
            for (const opcao of botoes) {
                opcao.setAttribute("aria-pressed", opcao.value === categoria);
            }
            filtrar();
        });
    }
    filtroNome.addEventListener("input", filtrar);

    montarFormulario(document.querySelector("#cadastro"), null, async (dados) => {
        await requisitar(caminhoAPI, "POST", dados);
        await carregarJogos();
    });
    pagina.hidden = false;
    carregarJogos();
    window.addEventListener("pageshow", (evento) => {
        if (evento.persisted) carregarJogos();
    });
}

async function abrirDetalhes(identificador) {
    const situacao = document.querySelector("#situacao-jogo");
    const conteudo = document.querySelector("#dados-jogo");
    const caminho = caminhoAPI + "/" + identificador;
    document.querySelector("#pagina-jogo").hidden = false;
    situacao.hidden = false;
    mostrarMensagem(situacao, "Carregando jogo…");

    function mostrarDetalhes(jogo) {
        document.title = jogo.nome + " | GameLog";
        mostrarJogo(conteudo.querySelector(".detalhe"), jogo, "h1");
        conteudo.querySelector(".review").textContent = jogo.review ?? "Nenhuma review registrada.";
    }

    try {
        const jogo = await requisitar(caminho);
        mostrarDetalhes(jogo);
        montarFormulario(document.querySelector("#edicao"), jogo, async (dados) => {
            await requisitar(caminho, "PUT", dados);
            mostrarDetalhes(dados);
        });
        conteudo.hidden = false;
        situacao.hidden = true;
    } catch (erro) {
        mostrarMensagem(situacao, erro.message, true);
        return;
    }

    const dialogo = document.querySelector("#confirmar-exclusao");
    const confirmar = document.querySelector("#excluir-jogo");
    const cancelar = document.querySelector("#cancelar-exclusao");
    const mensagem = dialogo.querySelector(".mensagem");

    document.querySelector("#abrir-exclusao").addEventListener("click", () => {
        mostrarMensagem(mensagem, "");
        dialogo.showModal();
    });
    cancelar.addEventListener("click", () => dialogo.close());
    dialogo.addEventListener("cancel", (evento) => {
        if (confirmar.disabled) evento.preventDefault();
    });
    confirmar.addEventListener("click", async () => {
        confirmar.disabled = true;
        cancelar.disabled = true;
        mostrarMensagem(mensagem, "Excluindo…");
        try {
            await requisitar(caminho, "DELETE");
            window.location.assign("/");
        } catch (erro) {
            mostrarMensagem(mensagem, erro.message, true);
            confirmar.disabled = false;
            cancelar.disabled = false;
            confirmar.focus();
        }
    });
}

if (window.location.pathname.startsWith("/jogos/")) {
    const identificador = window.location.pathname.split("/")[2];
    abrirDetalhes(identificador);
} else {
    abrirBiblioteca();
}

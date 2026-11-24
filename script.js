const buscaCatalogo = document.querySelector("#busca-catalogo");
const resultados = document.querySelector("#resultados");
const statusBusca = document.querySelector("#status-busca");

function miniaturaHttps(url) {
    if (typeof url !== "string" || !url.startsWith("https://") ||
        url.length > 2048 || /[\u0000-\u0020]/.test(url)) {
        return "";
    }
    try {
        const endereco = new URL(url);
        return endereco.username || endereco.password || endereco.href.length > 2048 ? "" : endereco.href;
    } catch {
        return "";
    }
}

function mostrarResultado(jogo) {
    const nome = jogo.external.trim();
    const url = miniaturaHttps(jogo.thumb);

    const card = document.createElement("li");
    card.className = "card";
    const capa = document.createElement("div");
    capa.className = "capa";
    capa.textContent = "Sem capa";
    if (url) {
        const imagem = document.createElement("img");
        imagem.alt = "";
        imagem.width = 460;
        imagem.height = 215;
        imagem.loading = "lazy";
        imagem.referrerPolicy = "no-referrer";
        imagem.addEventListener("error", () => imagem.remove(), { once: true });
        imagem.src = url;
        capa.append(imagem);
    }

    const info = document.createElement("div");
    info.className = "card-info";
    const titulo = document.createElement("h3");
    titulo.textContent = nome;
    const selecionar = document.createElement("button");
    selecionar.type = "button";
    selecionar.textContent = "Selecionar";
    selecionar.setAttribute("aria-label", "Selecionar " + nome);
    selecionar.addEventListener("click", () => {
        const campoNome = document.querySelector("#nome");
        campoNome.value = nome.slice(0, 100);
        document.querySelector("#capa_url").value = url;
        document.querySelector("#cheapshark_id").value = /^[0-9]{1,12}$/.test(jogo.gameID)
            ? jogo.gameID : "";
        campoNome.focus();
    });

    info.append(titulo, selecionar);
    card.append(capa, info);
    resultados.append(card);
}

document.querySelectorAll(".capa img").forEach((imagem) => {
    imagem.addEventListener("error", () => imagem.remove(), { once: true });
    if (imagem.complete && imagem.naturalWidth === 0) imagem.remove();
});

const filtroNome = document.querySelector("#filtro-nome");
const filtroStatus = document.querySelector("#filtro-status");
const filtroVazio = document.querySelector("#filtro-vazio");
const cards = document.querySelectorAll(".biblioteca .card");
const totalJogos = document.querySelector("#total-jogos");
const rotuloTotal = document.querySelector("#rotulo-total");
const botoesCategoria = [];

function filtrarBiblioteca() {
    const termo = filtroNome.value.trim().toLocaleLowerCase("pt-BR");
    const status = filtroStatus.value;
    let encontrados = 0;
    cards.forEach((card) => {
        const corresponde = card.dataset.nome.toLocaleLowerCase("pt-BR").includes(termo);
        card.hidden = !corresponde || (status !== "" && card.dataset.status !== status);
        if (!card.hidden) encontrados++;
    });
    if (filtroVazio) filtroVazio.hidden = encontrados > 0;
    totalJogos.textContent = new Intl.NumberFormat("pt-BR").format(encontrados);
    rotuloTotal.textContent = encontrados === 1 ? "jogo" : "jogos";
    for (const botao of botoesCategoria) {
        botao.setAttribute("aria-pressed", botao.value === status);
    }
}

if (filtroNome && filtroStatus) {
    const grupo = document.createElement("div");
    grupo.className = "filtros-categorias";
    grupo.setAttribute("role", "group");
    grupo.setAttribute("aria-label", "Filtrar por categoria");
    for (const opcao of filtroStatus.options) {
        const botao = document.createElement("button");
        botao.type = "button";
        botao.value = opcao.value;
        botao.textContent = opcao.textContent;
        botao.addEventListener("click", () => {
            filtroStatus.value = botao.value;
            atualizarFiltros();
        });
        botoesCategoria.push(botao);
        grupo.append(botao);
    }
    const controle = filtroStatus.closest(".controle-categoria");
    controle.after(grupo);
    controle.hidden = true;

    const url = new URL(location.href);
    filtroNome.value = url.searchParams.get("q") ?? "";
    const categoria = url.searchParams.get("categoria") ?? "";
    if (botoesCategoria.some((botao) => botao.value === categoria)) filtroStatus.value = categoria;
    filtrarBiblioteca();

    function atualizarFiltros() {
        filtrarBiblioteca();
        const atual = new URL(location.href);
        for (const campo of [filtroNome, filtroStatus]) {
            if (campo.value) atual.searchParams.set(campo.name, campo.value);
            else atual.searchParams.delete(campo.name);
        }
        if (atual.href !== location.href) history.replaceState(null, "", atual);
    }

    filtroNome.addEventListener("input", atualizarFiltros);
    filtroStatus.addEventListener("change", atualizarFiltros);
}

function preencherEstrelas(elemento, nota) {
    elemento.style.setProperty("--nota", (Number(nota) * 20) + "%");
}

document.querySelectorAll(".estrelas-nota").forEach((elemento) => {
    elemento.setAttribute("aria-hidden", "true");
    preencherEstrelas(elemento, elemento.dataset.nota);
});

const campoNota = document.querySelector("#nota");
const seletor = document.querySelector("#seletor-estrelas");
if (campoNota && seletor) {
    const estrelas = document.createElement("span");
    estrelas.className = "estrelas-nota";
    for (let i = 0; i < 5; i++) {
        const estrela = document.createElement("span");
        estrela.textContent = "★";
        estrelas.append(estrela);
    }
    estrelas.setAttribute("aria-hidden", "true");
    const metades = document.createElement("div");
    metades.className = "metades";

    for (let metade = 1; metade <= 10; metade++) {
        const botao = document.createElement("button");
        const valor = String(metade / 2);
        botao.type = "button";
        botao.dataset.valor = valor;
        botao.title = "Dar " + valor.replace(".", ",") + " estrelas";
        botao.setAttribute("aria-label", botao.title);
        botao.addEventListener("pointerenter", () => preencherEstrelas(estrelas, valor));
        botao.addEventListener("click", () => {
            campoNota.value = valor;
            campoNota.dispatchEvent(new Event("change"));
        });
        metades.append(botao);
    }

    function atualizarEstrelas() {
        preencherEstrelas(estrelas, campoNota.value);
        for (const botao of metades.children) {
            botao.setAttribute("aria-pressed", botao.dataset.valor === campoNota.value);
        }
    }

    seletor.append(estrelas, metades);
    seletor.addEventListener("pointerleave", atualizarEstrelas);
    campoNota.addEventListener("change", atualizarEstrelas);
    atualizarEstrelas();
}

const formulariosExclusao = document.querySelectorAll("form[data-confirmar]");
if (formulariosExclusao.length && typeof HTMLDialogElement !== "undefined") {
    const dialogo = document.createElement("dialog");
    dialogo.id = "confirmar-exclusao";
    dialogo.setAttribute("aria-labelledby", "titulo-exclusao");
    const titulo = document.createElement("h2");
    titulo.id = "titulo-exclusao";
    const descricao = document.createElement("p");
    const acoes = document.createElement("div");
    acoes.className = "dialogo-acoes";
    const cancelar = document.createElement("button");
    cancelar.type = "button";
    cancelar.className = "botao-secundario";
    cancelar.textContent = "Cancelar";
    const confirmar = document.createElement("button");
    confirmar.type = "button";
    confirmar.className = "excluir";
    confirmar.textContent = "Confirmar exclusão";
    acoes.append(cancelar, confirmar);
    dialogo.append(titulo, descricao, acoes);
    document.body.append(dialogo);

    let pendente;
    let confirmado;
    cancelar.addEventListener("click", () => dialogo.close());
    confirmar.addEventListener("click", () => {
        confirmado = pendente;
        dialogo.close();
        confirmado.requestSubmit();
    });
    formulariosExclusao.forEach((formulario) => {
        formulario.addEventListener("submit", (evento) => {
            if (confirmado === formulario) {
                confirmado = undefined;
                return;
            }
            evento.preventDefault();
            pendente = formulario;
            titulo.textContent = "Excluir jogo da biblioteca?";
            descricao.textContent = "O jogo será removido da sua biblioteca.";
            dialogo.showModal();
            cancelar.focus();
        });
    });
}

const formularioEdicao = document.querySelector(".editar form");
if (formularioEdicao) {
    const valoresIniciais = new URLSearchParams(new FormData(formularioEdicao)).toString();
    function avisarAlteracoes(evento) {
        evento.preventDefault();
        evento.returnValue = true;
    }
    function verificarAlteracoes() {
        const valores = new URLSearchParams(new FormData(formularioEdicao)).toString();
        if (valores !== valoresIniciais) window.addEventListener("beforeunload", avisarAlteracoes);
        else window.removeEventListener("beforeunload", avisarAlteracoes);
    }
    formularioEdicao.addEventListener("input", verificarAlteracoes);
    formularioEdicao.addEventListener("change", verificarAlteracoes);
    formularioEdicao.addEventListener("submit", () => window.removeEventListener("beforeunload", avisarAlteracoes));
}

buscaCatalogo?.addEventListener("submit", async (evento) => {
    evento.preventDefault();
    const termo = document.querySelector("#busca").value.trim();
    const botao = buscaCatalogo.querySelector("button");
    if (botao.disabled) return;
    resultados.replaceChildren();
    if (!termo || termo.length > 100) {
        statusBusca.textContent = "Informe um nome de até 100 caracteres.";
        return;
    }
    botao.disabled = true;
    statusBusca.textContent = "Buscando jogos…";
    try {
        const parametros = new URLSearchParams({ title: termo, limit: "10" });
        const resposta = await fetch("https://www.cheapshark.com/api/1.0/games?" + parametros, {
            signal: AbortSignal.timeout(8000)
        });
        if (resposta.status === 429) {
            statusBusca.textContent = "Muitas buscas em sequência. Aguarde um pouco e tente novamente.";
            return;
        }
        if (!resposta.ok) throw new Error("Falha na consulta");
        const jogos = (await resposta.json()).filter(
            (jogo) => typeof jogo?.external === "string" && jogo.external.trim()
        );
        jogos.forEach(mostrarResultado);
        statusBusca.textContent = jogos.length === 0 ? "Nenhum jogo encontrado." : "";
    } catch {
        statusBusca.textContent = "O catálogo está indisponível. Você pode cadastrar o jogo manualmente.";
    } finally {
        botao.disabled = false;
    }
});

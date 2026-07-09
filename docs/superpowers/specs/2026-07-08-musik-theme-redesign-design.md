# Design: Reestilizar o app web no visual do tema Musik

## Contexto

O app web do Exportify (`bin/exportify web`, ver
[2026-07-03-web-viewer-design.md](2026-07-03-web-viewer-design.md)) hoje
tem um visual minimalista: fundo claro, cards com borda fina, sem sidebar.
O usuário quer que as páginas existentes (`/`, `/playlists/:nome`,
`/playlists/:nome/faixas/:arquivo`, 404) sejam reestilizadas no visual do
tema ThemeForest "Musik" (referência:
[preview](https://preview.themeforest.net/item/musik-responsive-music-wordpress-theme/full_screen_preview/12127123)) —
sidebar esquerda escura fixa, grade de cards com capa, listas numeradas
estilo "Charts", coluna direita com filtros.

Junto com o visual, o usuário pediu duas funcionalidades novas que o tema
sugere: busca (filtro local) e um toggle de tema claro/escuro funcional.

## Fora de escopo

- Player de áudio global/mini-player que toca sem sair da página de
  faixa — a navegação para `/playlists/:nome/faixas/:arquivo` continua
  igual, só reestilizada.
- Sistema de "curtir"/favoritos ou "seguir artista" — o tema tem esses
  elementos, mas não há modelo de dados pra isso; os ícones de
  coração/seguir do tema são removidos, não implementados.
- Busca global no servidor (nova rota) — a busca é só filtro local via
  JS, por página, sobre dados já renderizados.
- Extração de capa de álbum real dos MP3s (tag `APIC`) — capas são
  sempre geradas (gradiente + inicial), não extraídas dos arquivos.
- Mudanças em `Exportify::Downloader`, `Tagger`, `Spotify`, `YouTube`,
  `CLI` — este design toca só a camada web (`WebServer`, `Library`,
  `views/`, `public/`).

## Arquitetura visual

Layout de 3 colunas em `views/layout.html.erb`:

```
┌──────────────┬─────────────────────────────┬─────────────────┐
│  Sidebar      │  Topbar (busca)              │                  │
│  esquerda      ├─────────────────────────────┤  Coluna direita  │
│  (fixa,        │  Conteúdo da página           │  (opcional,      │
│  sempre        │  (grade / lista / detalhe)   │  só em playlist) │
│  escura)      │                               │                  │
└──────────────┴─────────────────────────────┴─────────────────┘
```

- **Sidebar esquerda** (`views/_sidebar.html.erb`, parcial nova): logo
  "♫ Exportify", nav com item "Playlists" (link para `/`), seção
  "Configurações" com toggle de tema escuro e botão de fullscreen
  (`document.documentElement.requestFullscreen()`), rodapé com link do
  repositório no GitHub.
- **Topbar** (`views/_topbar.html.erb`, parcial nova): `<input>` de busca
  com `data-filter-target` apontando pro container a filtrar (playlists
  na home, faixas na página de playlist). Sem cart/login/signup — não
  existem contas no Exportify.
- **Coluna direita**: só renderizada em `playlist.html.erb`, lista pills
  de gênero.
- Em telas < 900px, sidebar esquerda colapsa para uma barra superior
  compacta (logo + toggle de tema) e a coluna direita some — grid CSS
  com `grid-template-columns` alternando via media query, sem JS.

## Paleta

| Uso | Claro | Escuro |
|---|---|---|
| Sidebar esquerda | `#0E0E12` (sempre) | `#0E0E12` (sempre) |
| Fundo do conteúdo | `#FAFAFA` | `#121214` |
| Texto principal | `#1A1A1A` | `#F5F5F5` |
| Texto secundário | `#6B7280` | `#9CA3AF` |
| Azul de destaque (links, ativo) | `#2563EB` | `#3B82F6` |
| Bordas/divisores | `#E5E7EB` | `#26262C` |

A sidebar esquerda **não** muda com o toggle de tema — fica sempre
escura, como na referência. O toggle afeta só fundo/texto/bordas do
conteúdo principal e da coluna direita, via `[data-theme="dark"]` no
`<html>` sobrescrevendo custom properties CSS (`--bg`, `--text`, etc.).

Tipografia: mantém `system-ui` (sem webfonts externas, consistente com o
design atual).

## Capas geradas (`lib/exportify/cover.rb`, novo)

Módulo sem estado, mesmo padrão de `Config`/`Downloader`:

```ruby
module Exportify
  module Cover
    module_function

    PALETTE = [
      %w[#F97316 #FACC15], %w[#EC4899 #8B5CF6], %w[#06B6D4 #3B82F6],
      %w[#10B981 #A3E635], %w[#EF4444 #F97316], %w[#8B5CF6 #6366F1],
      %w[#F43F5E #FB923C], %w[#14B8A6 #22D3EE]
    ].freeze

    # Retorna { from:, to:, initial: } determinístico a partir do texto.
    def for(text)
      hash = Digest::MD5.hexdigest(text.to_s).to_i(16)
      from, to = PALETTE[hash % PALETTE.size]
      { from: from, to: to, initial: text.to_s.strip[0]&.upcase || '♪' }
    end
  end
end
```

- Usado nas views para montar `<div class="cover" style="background:
  linear-gradient(135deg, <%= cover[:from] %>, <%= cover[:to] %>)"><%=
  cover[:initial] %></div>`, sem gerar imagens de verdade.
- Input na home: nome da playlist. Input na lista de faixas e na página
  de faixa: `"#{artist} - #{title}"`.
- `test/exportify/cover_test.rb` (novo): mesmo input sempre retorna o
  mesmo par de cores; inputs diferentes tendem a cores diferentes;
  string vazia não quebra (`initial` cai no fallback `♪`).

## Gêneros da playlist (`lib/exportify/library.rb`)

Novo método:

```ruby
# Retorna lista de gêneros únicos, não vazios, presentes nas faixas da
# playlist, ordenados alfabeticamente. Reaproveita read_tags.
def genres(playlist_name)
end
```

`WebServer#render_playlist` passa `genres: Library.genres(name)` pra
view, que renderiza os pills na coluna direita.

## Páginas

**Home (`/`, `views/index.html.erb`)**
- Grade de cards de playlist (`data-search-text` = nome da playlist):
  capa gerada, nome, contagem de faixas.
- Estado vazio: mesmo texto atual, dentro do novo layout.
- Busca da topbar filtra os cards pelo nome.

**Playlist (`/playlists/:nome`, `views/playlist.html.erb`)**
- Breadcrumb "← Playlists" + título.
- Lista de faixas estilo "Charts": numerada (1, 2, 3...), capa pequena
  gerada, título + artista, `data-search-text` = `"título artista"`.
  Clique continua levando para `/playlists/:nome/faixas/:arquivo`.
- Coluna direita: pills de gênero (`Library.genres`); clicar num pill
  filtra a lista pelo mesmo mecanismo JS da busca (usa o gênero como
  termo de filtro, reaproveitando `data-search-text`, que passa a incluir
  também o gênero da faixa).

**Faixa (`/playlists/:nome/faixas/:arquivo`, `views/track.html.erb`)**
- Breadcrumb "← Nome da playlist".
- Capa grande gerada acima do título (mesmo hash "artista - título").
- Título, artista, `<audio controls>` estilizado.
- Metadados (álbum, ano, faixa nº, gênero, duração, tamanho) em card
  separado, mesmo conteúdo de hoje.

**404 (`views/not_found.html.erb`)**
- Mesmo layout com sidebar; conteúdo central com a mensagem + link de
  volta, estilizado como estado vazio.

## JS (`public/app.js`, novo)

Vanilla JS, sem dependências, ~60-80 linhas, carregado no fim do
`<body>`. Progressive enhancement: sem JS, todas as páginas continuam
100% navegáveis (só sem filtro/toggle), preservando os testes atuais de
`web_server_test.rb` que checam texto puro no body.

**Tema:**
```js
function applyTheme(theme) {
  document.documentElement.dataset.theme = theme;
  localStorage.setItem('exportify-theme', theme);
}
// ao carregar: aplica localStorage.getItem('exportify-theme') || 'light'
// toggle na sidebar chama applyTheme com o valor oposto
```
Um script inline mínimo no `<head>` (antes do CSS) aplica o tema salvo
imediatamente, evitando flash de tema errado.

**Filtro (busca + pills de gênero):**
```js
function filterItems(container, term) {
  container.querySelectorAll('[data-search-text]').forEach((el) => {
    const match = el.dataset.searchText.toLowerCase().includes(term.toLowerCase());
    el.hidden = !match;
  });
}
// input da topbar chama filterItems no container da página atual
// clique num pill de gênero chama filterItems com o texto do pill
```

## Tratamento de erros

- Nenhuma mudança nas regras de erro já existentes (404 para
  playlist/faixa inexistente, fallback de tags, `Library.playlists`
  retornando `[]`) — este design é aditivo na camada visual.
- Se `localStorage` não estiver disponível (modo privado restritivo em
  navegadores antigos), `applyTheme` é envolvido em `try/catch`
  silencioso — tema cai para o padrão claro sem quebrar a página.
- Filtro/busca sem resultados: mostra o estado vazio já existente da
  seção (nenhum elemento novo necessário, `hidden` em todos os itens
  basta) — opcionalmente uma mensagem "Nenhum resultado" via CSS
  `:has()`/contagem, mas isso é um nice-to-have, não obrigatório para
  o design fechar.

## Testes

- `test/exportify/cover_test.rb` (novo): determinismo do hash, inputs
  diferentes, string vazia.
- `test/exportify/library_test.rb`: casos novos para `genres` (playlist
  com faixas de gêneros variados, faixa sem tag de gênero, playlist sem
  nenhuma tag preenchida retorna `[]`).
- `test/exportify/web_server_test.rb`: nenhum teste existente deve
  quebrar (continuam checando texto no body, que permanece renderizado
  server-side); nenhum teste novo necessário aqui — a mudança é de
  apresentação, não de rotas/dados.
- Lint: `bundle exec rubocop` nos arquivos Ruby novos/alterados.
- Verificação manual no navegador (já que é mudança visual): abrir as 4
  páginas em claro e escuro, testar busca na home e na playlist, testar
  pills de gênero, testar em viewport estreito (colapso da sidebar).

## README

Nenhuma mudança de comportamento de CLI — não requer atualização do
README além de, opcionalmente, mencionar busca/dark mode na descrição
do app web.

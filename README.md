# Repórter da Calheta · Participa

Webapp interativa do jornal da Escola Básica e Secundária da Calheta. Cada artigo do jornal em papel tem um código QR que abre uma página onde os alunos reagem, votam, dão gostos nas fotos, respondem a quizzes e deixam comentários (moderados por um professor).

- Página do aluno: `index.html#e<N.º>-<artigo>` (ex.: `#e1-desporto`); a capa usa `#e<N.º>`.
- Painel do professor: `index.html#painel` — rever artigos enviados, importar edições, moderar, ver resultados e gerar os QR.
- Redação: `index.html#redacao` — os jornalistas entram com o código da redação, enviam texto, fotos, áudio e versão em inglês, reservam pautas, leem o guia de escrita e fazem o cartão de jornalista.
- v1.3: `#concurso` (concurso de fotografia), `#cartas` (cartas ao jornal); passaporte do leitor, ouvir os artigos, opções de leitura (Aa), sopa de letras e palavras cruzadas, app instalável com avisos no telemóvel (`sw.js`, `manifest.webmanifest`); no painel, Estatísticas e Comunidade; na Redação, corretor, notas no texto e versões.
- v1.4 (telemóvel primeiro): barra de navegação em baixo (Jornal, Ranking, Jogos/Ler, Mais), folha "Mais", deslizar para mudar de artigo, sopa de letras a arrastar o dedo, pista atual nas cruzadas, lista de artigos antes dos atalhos, instalar a app no Android.
- v1.5: "Nova edição a partir do PDF" (painel → Edições): a app lê o PDF exportado do Canva e cria os artigos (título, secção, página, texto, autores, fotos, zonas tocáveis), com pré-visualização para confirmar. "Ler o jornal" com páginas contínuas, ecrã inteiro com zoom e deslizar, "Só texto" e retomar a leitura. Modo visão reduzida e declaração de acessibilidade em `#acessibilidade` (DL 83/2018, EN 301 549 / WCAG 2.1 AA).
- v1.5.2: retirado o mapa das notícias (`#mapa`, o campo "Onde aconteceu" no painel e a biblioteca Leaflet).
- v1.5.3: retirada a agenda da escola (`#agenda` e o cartão "Agenda da escola" no painel → Comunidade; na barra de baixo, sem passatempos, aparece "Ler"). Ao desligar o modo visão reduzida, as cores e o tamanho da letra voltam ao que estavam antes de o ligar.
- v1.5.4: correções encontradas por revisão — leitor (deslizar no índice, caça ao QR, "Ver a solução" já não dá pontos, "Repor" com visão reduzida, palavras longas com letra grande) e painel (renumerar edição sem apagar outra, importar JSON completo, destaque ao apagar edição, PDF depois de uma falha, ano da capa, moderação e edições sem botões presos). `v14.sql`: regras de segurança na base de dados (aplicado a 27/11/2026).
- v1.5.5: as edições passam a ser por período letivo ("1.º período 2026/2027"): no painel → Edições o campo "Meses" passou a "Período", com sugestões do ano letivo, e a leitura do PDF encontra o período e o ano letivo na capa (as edições antigas, por meses, ficam como estão).
- v1.6: novo fluxo das edições. A edição cria-se primeiro (painel → Edições → Nova edição → "Trazer os artigos aceites da Redação" ou "+ Artigo") e fica em **rascunho**: só os professores a veem e quem ler um QR dela vê "Este número ainda não saiu". Códigos QR → "Descarregar todos (ZIP)" (pastas com-legenda e so-codigo, LISTA.txt). Depois de fechar o jornal no Canva, carrega-se o PDF na edição: cada artigo do PDF liga-se ao que já existe (pelas palavras do título; escolha em "Corresponde a"), para os QR impressos continuarem a funcionar. Por fim, "Pôr no ar" (e "Tirar do ar"). Aviso se se mudar o número de uma edição com QR já exportados.
- v1.6.1: painel → **Fotos do Word**: escolhe-se (ou arrasta-se) um ou vários documentos .docx (também .pptx, .xlsx e .odt) e a app mostra as fotos que lá estão, pela ordem em que aparecem, para descarregar uma a uma ou todas num ZIP. Tudo é feito no browser; os documentos não são enviados para lado nenhum.
- v1.6.2: em Fotos do Word, edição antes de descarregar: rodar no próprio cartão (↺ ↻) e, em "Editar", rodar, espelhar, recortar (livre, quadrado, 4:3, 3:4, 16:9), luz e contraste, com "Repor a original". O menu do painel deixa de ter barra de deslocamento em ecrãs largos (passa a várias linhas, com "Ver o jornal" e "Terminar sessão" à direita).
- Outras páginas: `#e<N.º>-top` (ranking e concurso entre turmas), `#tv` (modo TV para a entrada), `#e<N.º>-ler` (página para partilhar e PDF da edição), `#e<N.º>-relatorio` (relatório para imprimir), `#arquivo`, `#familias`, `#caca-<N.º>-<pista>` (caça ao QR).

## Base de dados
Supabase. O esquema está em `supabase.sql`, a Redação em `redacao.sql` a versão 1.2 em `v12.sql` a 1.3 em `v13.sql` e as regras de segurança de `v14.sql` (correr por esta ordem; todos aplicados, o `v14.sql` a 27/11/2026) e a edição n.º1 em `seed-edicao-1.sql`.
No Supabase é preciso ativar **Authentication → Sign In / Providers → Anonymous sign-ins** (os alunos entram sem conta) e autorizar cada professor:

```sql
insert into public.professores (email) values ('professor@exemplo.pt');
```

## Configuração
No topo do script em `index.html`, em `CONFIG`: `supabaseUrl`, `supabaseKey` (chave pública) e `base` (endereço público, usado nos QR).

## Avisos no telemóvel
A função `supabase/functions/avisar` (Edge Function) envia os avisos. Precisa das chaves VAPID: a pública em `CONFIG.vapid` e em `segredos` (`vapid_publica`), a privada só em `segredos` (`vapid_privada`). Ver o fim de `v13.sql`.

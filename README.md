# Repórter da Calheta · Participa

Webapp interativa do jornal da Escola Básica e Secundária da Calheta. Cada artigo do jornal em papel tem um código QR que abre uma página onde os alunos reagem, votam, dão gostos nas fotos, respondem a quizzes e deixam comentários (moderados por um professor).

- Página do aluno: `index.html#e<N.º>-<artigo>` (ex.: `#e1-desporto`); a capa usa `#e<N.º>`.
- Painel do professor: `index.html#painel` — rever artigos enviados, importar edições, moderar, ver resultados e gerar os QR.
- Redação: `index.html#redacao` — os jornalistas entram com o código da redação, enviam texto, fotos, áudio e versão em inglês, reservam pautas, leem o guia de escrita e fazem o cartão de jornalista.
- v1.3: `#concurso` (concurso de fotografia), `#cartas` (cartas ao jornal), `#mapa`, `#agenda`; passaporte do leitor, ouvir os artigos, opções de leitura (Aa), sopa de letras e palavras cruzadas, app instalável com avisos no telemóvel (`sw.js`, `manifest.webmanifest`); no painel, Estatísticas e Comunidade; na Redação, corretor, notas no texto e versões.
- Outras páginas: `#e<N.º>-top` (ranking e concurso entre turmas), `#tv` (modo TV para a entrada), `#e<N.º>-ler` (página para partilhar e PDF da edição), `#e<N.º>-relatorio` (relatório para imprimir), `#arquivo`, `#familias`, `#caca-<N.º>-<pista>` (caça ao QR).

## Base de dados
Supabase. O esquema está em `supabase.sql`, a Redação em `redacao.sql` a versão 1.2 em `v12.sql` e a 1.3 em `v13.sql` (correr por esta ordem) e a edição n.º1 em `seed-edicao-1.sql`.
No Supabase é preciso ativar **Authentication → Sign In / Providers → Anonymous sign-ins** (os alunos entram sem conta) e autorizar cada professor:

```sql
insert into public.professores (email) values ('professor@exemplo.pt');
```

## Configuração
No topo do script em `index.html`, em `CONFIG`: `supabaseUrl`, `supabaseKey` (chave pública) e `base` (endereço público, usado nos QR).

## Avisos no telemóvel
A função `supabase/functions/avisar` (Edge Function) envia os avisos. Precisa das chaves VAPID: a pública em `CONFIG.vapid` e em `segredos` (`vapid_publica`), a privada só em `segredos` (`vapid_privada`). Ver o fim de `v13.sql`.

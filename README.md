# Repórter da Calheta · Participa

Webapp interativa do jornal da Escola Básica e Secundária da Calheta. Cada artigo do jornal em papel tem um código QR que abre uma página onde os alunos reagem, votam, dão gostos nas fotos, respondem a quizzes e deixam comentários (moderados por um professor).

- Página do aluno: `index.html#e<N.º>-<artigo>` (ex.: `#e1-desporto`); a capa usa `#e<N.º>`.
- Painel do professor: `index.html#painel` — importar edições, moderar, ver resultados e gerar os QR.

## Base de dados
Supabase. O esquema está em `supabase.sql` e a edição n.º1 em `seed-edicao-1.sql`.
No Supabase é preciso ativar **Authentication → Sign In / Providers → Anonymous sign-ins** (os alunos entram sem conta) e autorizar cada professor:

```sql
insert into public.professores (email) values ('professor@exemplo.pt');
```

## Configuração
No topo do script em `index.html`, em `CONFIG`: `supabaseUrl`, `supabaseKey` (chave pública) e `base` (endereço público, usado nos QR).

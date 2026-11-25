-- Repórter da Calheta · Participa
-- Esquema da base de dados (Supabase / Postgres)
-- Alunos: entram de forma anónima (sem conta) e só podem votar e comentar.
-- Professores: entram com email + palavra-passe e têm de estar na tabela "professores".

create table if not exists public.professores (
  email text primary key
);

create table if not exists public.edicoes (
  numero int primary key,
  dados jsonb not null,
  atualizada timestamptz not null default now()
);

create table if not exists public.definicoes (
  chave text primary key,
  valor text not null
);

create table if not exists public.votos (
  id bigint generated always as identity primary key,
  edicao int not null references public.edicoes(numero) on delete cascade,
  artigo text not null check (length(artigo) <= 60),
  chave text not null check (length(chave) <= 12),
  opcao text not null check (length(opcao) <= 20),
  utilizador uuid not null default auth.uid(),
  criado timestamptz not null default now(),
  unique (edicao, artigo, chave, utilizador)
);

create table if not exists public.comentarios (
  id uuid primary key default gen_random_uuid(),
  edicao int not null references public.edicoes(numero) on delete cascade,
  artigo text not null check (length(artigo) <= 60),
  tipo text not null check (tipo in ('comentario','sugestao')),
  nome text check (length(nome) <= 30),
  turma text check (length(turma) <= 10),
  texto text not null check (length(texto) between 3 and 400),
  estado text not null default 'pendente' check (estado in ('pendente','aprovado','rejeitado')),
  utilizador uuid default auth.uid(),
  criado timestamptz not null default now()
);

create index if not exists comentarios_estado_idx on public.comentarios (estado, criado desc);
create index if not exists votos_edicao_idx on public.votos (edicao, artigo);

-- É professor? (conta com email, não anónima, e listada em "professores")
create or replace function public.e_professor()
returns boolean language sql stable security definer set search_path = '' as $$
  select coalesce((auth.jwt() ->> 'is_anonymous')::boolean, false) = false
     and exists (select 1 from public.professores p where p.email = auth.jwt() ->> 'email');
$$;

-- Totais por opção (só números, nunca quem votou)
create or replace function public.contagens_edicao(p_edicao int)
returns table (artigo text, chave text, opcao text, total bigint)
language sql stable security definer set search_path = '' as $$
  select v.artigo, v.chave, v.opcao, count(*) from public.votos v
  where v.edicao = p_edicao group by 1, 2, 3;
$$;

alter table public.professores enable row level security;
alter table public.edicoes     enable row level security;
alter table public.definicoes  enable row level security;
alter table public.votos       enable row level security;
alter table public.comentarios enable row level security;

-- Edições e definições: todos leem, só professores alteram
create policy "edicoes leitura" on public.edicoes for select using (true);
create policy "edicoes prof" on public.edicoes for all to authenticated using (public.e_professor()) with check (public.e_professor());
create policy "definicoes leitura" on public.definicoes for select using (true);
create policy "definicoes prof" on public.definicoes for all to authenticated using (public.e_professor()) with check (public.e_professor());
create policy "professores prof" on public.professores for select to authenticated using (public.e_professor());

-- Votos: cada aparelho vê, cria, muda e apaga só os seus
create policy "votos meus" on public.votos for select to authenticated using (utilizador = auth.uid());
create policy "votos criar" on public.votos for insert to authenticated with check (utilizador = auth.uid());
create policy "votos mudar" on public.votos for update to authenticated using (utilizador = auth.uid()) with check (utilizador = auth.uid());
create policy "votos apagar" on public.votos for delete to authenticated using (utilizador = auth.uid());

-- Comentários: entram sempre como pendentes; público vê só aprovados; professores veem e moderam tudo
create policy "comentarios criar" on public.comentarios for insert to authenticated
  with check (estado = 'pendente' and utilizador = auth.uid());
create policy "comentarios ler" on public.comentarios for select to authenticated
  using ((estado = 'aprovado' and tipo = 'comentario') or public.e_professor());
create policy "comentarios moderar" on public.comentarios for update to authenticated
  using (public.e_professor()) with check (public.e_professor());

grant execute on function public.contagens_edicao(int) to anon, authenticated;
grant execute on function public.e_professor() to authenticated;

-- Depois de criar: Authentication > Sign In / Providers > ativar "Anonymous sign-ins".
-- Criar a conta do professor (Authentication > Users) e autorizá-la:
-- insert into public.professores (email) values ('professor@exemplo.pt');

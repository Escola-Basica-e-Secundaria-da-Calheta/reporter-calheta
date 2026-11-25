-- Repórter da Calheta · Participa — Redação (envio de artigos pelos jornalistas)
-- Correr DEPOIS de supabase.sql (usa a função public.e_professor() e a tabela public.definicoes).
-- Os jornalistas entram com login anónimo + código da redação; só os professores leem tudo.

-- 1) Código da redação (nunca legível pela API) e quem já entrou com ele
create table if not exists public.segredos(
  chave text primary key,
  valor text not null
);
alter table public.segredos enable row level security;  -- sem políticas: só as funções abaixo lhe tocam

create table if not exists public.redatores(
  utilizador uuid primary key references auth.users on delete cascade,
  criado timestamptz not null default now()
);
alter table public.redatores enable row level security;
drop policy if exists "redator ve-se a si" on public.redatores;
create policy "redator ve-se a si" on public.redatores for select to authenticated
  using (utilizador = (select auth.uid()) or (select public.e_professor()));

create or replace function public.e_redator() returns boolean
language sql stable security definer set search_path = '' as $$
  select exists(select 1 from public.redatores where utilizador = auth.uid())
$$;

create or replace function public.entrar_redacao(p_codigo text) returns boolean
language plpgsql security definer set search_path = '' as $$
declare v text;
begin
  if auth.uid() is null then return false; end if;
  select valor into v from public.segredos where chave = 'codigo_redacao';
  if v is null or p_codigo is null or lower(trim(p_codigo)) <> lower(v) then
    perform pg_sleep(1);  -- trava tentativas em série
    return false;
  end if;
  insert into public.redatores(utilizador) values (auth.uid()) on conflict do nothing;
  return true;
end $$;

create or replace function public.definir_codigo_redacao(p_codigo text) returns void
language plpgsql security definer set search_path = '' as $$
begin
  if not public.e_professor() then raise exception 'sem permissão'; end if;
  if char_length(trim(coalesce(p_codigo, ''))) < 6 then raise exception 'o código precisa de pelo menos 6 caracteres'; end if;
  insert into public.segredos(chave, valor) values ('codigo_redacao', trim(p_codigo))
    on conflict (chave) do update set valor = excluded.valor;
end $$;

create or replace function public.ver_codigo_redacao() returns text
language plpgsql stable security definer set search_path = '' as $$
begin
  if not public.e_professor() then raise exception 'sem permissão'; end if;
  return (select valor from public.segredos where chave = 'codigo_redacao');
end $$;

create or replace function public.limpar_redatores() returns void
language plpgsql security definer set search_path = '' as $$
begin
  if not public.e_professor() then raise exception 'sem permissão'; end if;
  delete from public.redatores where true;
end $$;

revoke all on function public.e_redator(), public.entrar_redacao(text), public.definir_codigo_redacao(text),
  public.ver_codigo_redacao(), public.limpar_redatores() from public, anon;
grant execute on function public.e_redator(), public.entrar_redacao(text), public.definir_codigo_redacao(text),
  public.ver_codigo_redacao(), public.limpar_redatores() to authenticated;

-- 2) Artigos enviados
create table if not exists public.submissoes(
  id uuid primary key default gen_random_uuid(),
  autor uuid references auth.users on delete set null default auth.uid(),
  edicao int,
  seccao text check (char_length(seccao) <= 60),
  titulo text not null check (char_length(titulo) between 1 and 200),
  entrada text check (char_length(entrada) <= 600),
  texto text not null check (char_length(texto) <= 30000),
  autores text not null check (char_length(autores) between 1 and 200),
  turma text check (char_length(turma) <= 40),
  creditos_fotos text check (char_length(creditos_fotos) <= 160),
  fotos jsonb not null default '[]' check (jsonb_typeof(fotos) = 'array' and jsonb_array_length(fotos) <= 20),
  pergunta jsonb,
  notas text check (char_length(notas) <= 800),
  autorizacao boolean not null default false,
  estado text not null default 'recebido'
    check (estado in ('recebido','revisao','alteracoes','aceite','publicado','recusado')),
  nota_equipa text check (char_length(nota_equipa) <= 800),
  pagina text check (char_length(pagina) <= 10),
  criado timestamptz not null default now(),
  atualizado timestamptz not null default now()
);
create index if not exists submissoes_autor on public.submissoes(autor);
create index if not exists submissoes_edicao on public.submissoes(edicao, estado);
alter table public.submissoes enable row level security;

-- Os campos da equipa (estado, nota, página) só mudam pela mão de um professor.
-- Quando o autor corrige, o artigo volta a "recebido".
create or replace function public.submissoes_proteger() returns trigger
language plpgsql set search_path = '' as $$
begin
  new.atualizado := now();
  if tg_op = 'INSERT' then
    new.autor := auth.uid(); new.criado := now();
    if not public.e_professor() then
      new.estado := 'recebido'; new.nota_equipa := null; new.pagina := null;
    end if;
  elsif not public.e_professor() then
    new.autor := old.autor; new.criado := old.criado; new.edicao := old.edicao;
    new.estado := 'recebido'; new.nota_equipa := old.nota_equipa; new.pagina := old.pagina;
  end if;
  return new;
end $$;
drop trigger if exists submissoes_proteger on public.submissoes;
create trigger submissoes_proteger before insert or update on public.submissoes
  for each row execute function public.submissoes_proteger();

drop policy if exists "ler submissoes" on public.submissoes;
drop policy if exists "enviar submissao" on public.submissoes;
drop policy if exists "autor corrige" on public.submissoes;
drop policy if exists "professor gere" on public.submissoes;
drop policy if exists "apagar submissao" on public.submissoes;
create policy "ler submissoes" on public.submissoes for select to authenticated
  using (autor = (select auth.uid()) or (select public.e_professor()));
create policy "enviar submissao" on public.submissoes for insert to authenticated
  with check ((select public.e_redator()) or (select public.e_professor()));
create policy "autor corrige" on public.submissoes for update to authenticated
  using (autor = (select auth.uid()) and estado in ('recebido','alteracoes'))
  with check (autor = (select auth.uid()));
create policy "professor gere" on public.submissoes for update to authenticated
  using ((select public.e_professor())) with check ((select public.e_professor()));
create policy "apagar submissao" on public.submissoes for delete to authenticated
  using ((select public.e_professor()) or (autor = (select auth.uid()) and estado = 'recebido'));

-- 3) Fotografias: pasta privada (fotos com alunos nunca ficam públicas)
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('submissoes', 'submissoes', false, 10485760,
        array['image/jpeg','image/png','image/webp','image/heic','image/heif'])
on conflict (id) do update set public = false, file_size_limit = excluded.file_size_limit,
  allowed_mime_types = excluded.allowed_mime_types;

drop policy if exists "redator envia fotos" on storage.objects;
drop policy if exists "ver fotos das submissoes" on storage.objects;
drop policy if exists "apagar fotos das submissoes" on storage.objects;
create policy "redator envia fotos" on storage.objects for insert to authenticated
  with check (bucket_id = 'submissoes'
    and ((select public.e_redator()) or (select public.e_professor()))
    and (storage.foldername(name))[1] = (select auth.uid())::text);
create policy "ver fotos das submissoes" on storage.objects for select to authenticated
  using (bucket_id = 'submissoes'
    and ((storage.foldername(name))[1] = (select auth.uid())::text or (select public.e_professor())));
create policy "apagar fotos das submissoes" on storage.objects for delete to authenticated
  using (bucket_id = 'submissoes'
    and ((storage.foldername(name))[1] = (select auth.uid())::text or (select public.e_professor())));

-- 4) Código inicial (mudar logo no painel: Redação → Receção de artigos)
insert into public.segredos(chave, valor) values ('codigo_redacao', 'muda-este-codigo')
  on conflict (chave) do nothing;

-- Repórter da Calheta · Participa v1.2 — correr depois de supabase.sql e redacao.sql
-- Turmas dos leitores e concurso entre turmas, pautas, autorizações de imagem,
-- secções por professor, perguntas para entrevistas, mural das famílias, áudio e PDF.

-- 1) Turma de cada leitor (para o concurso entre turmas)
create table if not exists public.leitores(
  utilizador uuid primary key default auth.uid() references auth.users on delete cascade,
  turma text check (char_length(turma) <= 12),
  atualizado timestamptz not null default now()
);
alter table public.leitores enable row level security;
drop policy if exists "leitor ve" on public.leitores;
drop policy if exists "leitor cria" on public.leitores;
drop policy if exists "leitor muda" on public.leitores;
create policy "leitor ve" on public.leitores for select to authenticated using (utilizador = (select auth.uid()));
create policy "leitor cria" on public.leitores for insert to authenticated with check (utilizador = (select auth.uid()));
create policy "leitor muda" on public.leitores for update to authenticated
  using (utilizador = (select auth.uid())) with check (utilizador = (select auth.uid()));

-- Pontos por turma: 1 por voto/reação, +4 por resposta certa (quizzes e caça ao QR), +5 por comentário aprovado.
-- Só devolve totais, nunca quem votou.
create or replace function public.ranking_turmas(p_edicao int)
returns table(turma text, leitores bigint, interacoes bigint, certas bigint, comentarios bigint, pontos bigint)
language sql stable security definer set search_path = '' as $$
  with ed as (select dados from public.edicoes where numero = p_edicao),
  certo as (
    select a->>'id' as artigo, (b.ord - 1)::text as chave, b.blk->>'c' as opcao
    from ed
    cross join lateral jsonb_array_elements(coalesce(ed.dados->'artigos', '[]'::jsonb)) a
    cross join lateral jsonb_array_elements(coalesce(a->'b', '[]'::jsonb)) with ordinality as b(blk, ord)
    where b.blk->>'t' = 'quiz'
    union all
    select '_caca', c->>'id', c->>'c'
    from ed cross join lateral jsonb_array_elements(coalesce(ed.dados->'caca', '[]'::jsonb)) c
  ),
  v as (
    select l.turma, v.utilizador, (ct.artigo is not null) as certa
    from public.votos v
    join public.leitores l on l.utilizador = v.utilizador
    left join certo ct on ct.artigo = v.artigo and ct.chave = v.chave and ct.opcao = v.opcao
    where v.edicao = p_edicao and coalesce(l.turma, '') <> ''
  ),
  t as (
    select v.turma, count(distinct v.utilizador) as leitores, count(*) as interacoes,
           count(*) filter (where v.certa) as certas
    from v group by v.turma
  ),
  c as (
    select l.turma, count(*) as n
    from public.comentarios c join public.leitores l on l.utilizador = c.utilizador
    where c.edicao = p_edicao and c.estado = 'aprovado' and c.tipo in ('comentario','familia')
      and coalesce(l.turma, '') <> ''
    group by l.turma
  )
  select coalesce(t.turma, c.turma), coalesce(t.leitores, 0), coalesce(t.interacoes, 0), coalesce(t.certas, 0),
         coalesce(c.n, 0), coalesce(t.interacoes, 0) + 4 * coalesce(t.certas, 0) + 5 * coalesce(c.n, 0)
  from t full join c on c.turma = t.turma
  order by 6 desc;
$$;
grant execute on function public.ranking_turmas(int) to anon, authenticated;

-- 2) Pautas: temas por cobrir que os jornalistas reservam
create table if not exists public.pautas(
  id uuid primary key default gen_random_uuid(),
  titulo text not null check (char_length(titulo) between 1 and 140),
  descricao text check (char_length(descricao) <= 600),
  data date,
  seccao text check (char_length(seccao) <= 60),
  entidade text check (char_length(entidade) <= 80),
  estado text not null default 'aberta' check (estado in ('aberta','atribuida','feita')),
  jornalista uuid,
  jornalista_nome text check (char_length(jornalista_nome) <= 60),
  criado timestamptz not null default now()
);
alter table public.pautas enable row level security;
drop policy if exists "pautas ler" on public.pautas;
drop policy if exists "pautas prof" on public.pautas;
create policy "pautas ler" on public.pautas for select to authenticated
  using ((select public.e_redator()) or (select public.e_professor()));
create policy "pautas prof" on public.pautas for all to authenticated
  using ((select public.e_professor())) with check ((select public.e_professor()));

create or replace function public.ficar_pauta(p_id uuid, p_nome text) returns boolean
language plpgsql security definer set search_path = '' as $$
begin
  if not (public.e_redator() or public.e_professor()) then return false; end if;
  if char_length(trim(coalesce(p_nome, ''))) = 0 then return false; end if;
  update public.pautas set estado = 'atribuida', jornalista = auth.uid(), jornalista_nome = left(trim(p_nome), 60)
    where id = p_id and estado = 'aberta';
  return found;
end $$;
create or replace function public.largar_pauta(p_id uuid) returns void
language plpgsql security definer set search_path = '' as $$
begin
  update public.pautas set estado = 'aberta', jornalista = null, jornalista_nome = null
    where id = p_id and jornalista = auth.uid() and estado = 'atribuida';
end $$;
revoke all on function public.ficar_pauta(uuid, text), public.largar_pauta(uuid) from public, anon;
grant execute on function public.ficar_pauta(uuid, text), public.largar_pauta(uuid) to authenticated;

-- 3) Autorizações de imagem (só professores)
create table if not exists public.autorizacoes(
  id bigint generated always as identity primary key,
  turma text not null check (char_length(turma) <= 12),
  nome text not null check (char_length(nome) between 1 and 120),
  autoriza boolean not null default false,
  obs text check (char_length(obs) <= 200)
);
alter table public.autorizacoes enable row level security;
drop policy if exists "autorizacoes prof" on public.autorizacoes;
create policy "autorizacoes prof" on public.autorizacoes for all to authenticated
  using ((select public.e_professor())) with check ((select public.e_professor()));
create or replace function public.substituir_autorizacoes(p_linhas jsonb) returns void
language plpgsql security definer set search_path = '' as $$
begin
  if not public.e_professor() then raise exception 'sem permissão'; end if;
  delete from public.autorizacoes where true;
  insert into public.autorizacoes(turma, nome, autoriza, obs)
    select left(x->>'turma', 12), left(x->>'nome', 120), coalesce((x->>'autoriza')::boolean, false), left(x->>'obs', 200)
    from jsonb_array_elements(coalesce(p_linhas, '[]'::jsonb)) x
    where coalesce(x->>'nome', '') <> '';
end $$;
revoke all on function public.substituir_autorizacoes(jsonb) from public, anon;
grant execute on function public.substituir_autorizacoes(jsonb) to authenticated;

-- 4) Secções de cada professor; professores gerem a equipa
alter table public.professores add column if not exists seccoes text[] not null default '{}';
drop policy if exists "professores gerir" on public.professores;
create policy "professores gerir" on public.professores for all to authenticated
  using ((select public.e_professor())) with check ((select public.e_professor()));

-- 5) Perguntas para entrevistas e mural das famílias
alter table public.comentarios drop constraint if exists comentarios_tipo_check;
alter table public.comentarios add constraint comentarios_tipo_check
  check (tipo in ('comentario','sugestao','pergunta','familia'));
drop policy if exists "comentarios ler" on public.comentarios;
create policy "comentarios ler" on public.comentarios for select to authenticated
  using ((estado = 'aprovado' and tipo in ('comentario','familia')) or public.e_professor());

-- 6) Versão em inglês e áudio nos artigos enviados
alter table public.submissoes add column if not exists ingles text check (char_length(ingles) <= 3000);
alter table public.submissoes add column if not exists audio text check (char_length(audio) <= 200);
update storage.buckets set allowed_mime_types = array['image/jpeg','image/png','image/webp','image/heic','image/heif',
  'audio/webm','audio/ogg','audio/mp4','audio/mpeg','audio/wav','audio/x-m4a','audio/aac']
  where id = 'submissoes';

-- 7) Pasta pública: áudios publicados e PDF das edições (só professores enviam)
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('publico', 'publico', true, 52428800,
  array['application/pdf','audio/webm','audio/ogg','audio/mp4','audio/mpeg','audio/wav','audio/x-m4a','audio/aac','image/jpeg','image/png'])
on conflict (id) do update set public = true, file_size_limit = excluded.file_size_limit,
  allowed_mime_types = excluded.allowed_mime_types;
drop policy if exists "publico prof envia" on storage.objects;
drop policy if exists "publico prof apaga" on storage.objects;
create policy "publico prof envia" on storage.objects for insert to authenticated
  with check (bucket_id = 'publico' and (select public.e_professor()));
create policy "publico prof apaga" on storage.objects for delete to authenticated
  using (bucket_id = 'publico' and (select public.e_professor()));

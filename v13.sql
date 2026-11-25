-- Repórter da Calheta · Participa v1.3
-- Correr DEPOIS de supabase.sql, redacao.sql e v12.sql.
-- Passaporte e estatísticas de leitura, filtro de linguagem, cartas ao jornal, concurso de fotografia,
-- avisos no telemóvel, notas no texto e histórico de versões dos artigos.

-- 1) Visitas: cada leitor só vê as suas; os totais só os professores (estatisticas_leitura)
create table if not exists public.visitas(
  id bigint generated always as identity primary key,
  edicao int not null references public.edicoes(numero) on delete cascade,
  artigo text not null check (char_length(artigo) <= 60),
  origem text not null default 'app' check (origem in ('qr','app')),
  utilizador uuid not null default auth.uid(),
  criado timestamptz not null default now()
);
create index if not exists visitas_ed on public.visitas(edicao, artigo);
create index if not exists visitas_user on public.visitas(utilizador, edicao);
alter table public.visitas enable row level security;
drop policy if exists "visitas criar" on public.visitas;
drop policy if exists "visitas minhas" on public.visitas;
create policy "visitas criar" on public.visitas for insert to authenticated with check (utilizador = (select auth.uid()));
create policy "visitas minhas" on public.visitas for select to authenticated using (utilizador = (select auth.uid()));

create or replace function public.estatisticas_leitura(p_edicao int) returns jsonb
language plpgsql stable security definer set search_path = '' as $$
begin
  if not public.e_professor() then raise exception 'sem permissão'; end if;
  return jsonb_build_object(
    'visitas', (select count(*) from public.visitas where edicao = p_edicao),
    'leitores', (select count(distinct utilizador) from public.visitas where edicao = p_edicao),
    'qr', (select count(*) from public.visitas where edicao = p_edicao and origem = 'qr'),
    'artigos', coalesce((select jsonb_agg(x) from (
        select artigo, count(*) as visitas, count(distinct utilizador) as leitores, count(*) filter (where origem = 'qr') as qr
        from public.visitas where edicao = p_edicao group by artigo) x), '[]'::jsonb),
    'horas', coalesce((select jsonb_agg(x) from (
        select extract(hour from criado at time zone 'Atlantic/Azores')::int as hora, count(*) as n
        from public.visitas where edicao = p_edicao group by 1) x), '[]'::jsonb),
    'semana', coalesce((select jsonb_agg(x) from (
        select extract(isodow from criado at time zone 'Atlantic/Azores')::int as dia, count(*) as n
        from public.visitas where edicao = p_edicao group by 1) x), '[]'::jsonb),
    'dias', coalesce((select jsonb_agg(x order by x.dia) from (
        select (criado at time zone 'Atlantic/Azores')::date as dia, count(*) as n
        from public.visitas where edicao = p_edicao group by 1) x), '[]'::jsonb)
  );
end $$;
revoke all on function public.estatisticas_leitura(int) from public, anon;
grant execute on function public.estatisticas_leitura(int) to authenticated;

-- 2) Filtro de linguagem: mensagens com palavrões ficam "retidas" (não entram na lista normal)
create or replace function public.tem_palavrao(t text) returns boolean
language sql immutable set search_path = '' as $$
  select lower(translate(coalesce(t, ''), 'ÁÀÂÃÉÊÍÓÔÕÚÇáàâãéêíóôõúç', 'AAAAEEIOOOUCaaaaeeiooouc'))
    ~ '(merd|caralh|\mputa|\mputo\M|\mfod[aeiu]|\mfdp\M|\mcabr[ao]|cabrao|otari|idiot|estupid|imbecil|\mburr[oa]s?\M|anormal|parvalh|\mcona\M|panasc|\mbicha\M|viad[oa]|\mcorn[oa]s?\M|\mchupa|\mbosta|\mporra\M|\mcu\M|\mmama-?m)';
$$;

alter table public.comentarios drop constraint if exists comentarios_estado_check;
alter table public.comentarios add constraint comentarios_estado_check
  check (estado in ('pendente','aprovado','rejeitado','retido'));
alter table public.comentarios drop constraint if exists comentarios_tipo_check;
alter table public.comentarios add constraint comentarios_tipo_check
  check (tipo in ('comentario','sugestao','pergunta','familia','carta'));
alter table public.comentarios drop constraint if exists comentarios_texto_check;
alter table public.comentarios add constraint comentarios_texto_check
  check (char_length(texto) between 3 and (case when tipo = 'carta' then 1500 else 400 end));

create or replace function public.comentarios_filtro() returns trigger
language plpgsql set search_path = '' as $$
begin
  if public.e_professor() then return new; end if;
  new.utilizador := auth.uid();
  new.estado := case when public.tem_palavrao(coalesce(new.texto, '') || ' ' || coalesce(new.nome, '')) then 'retido' else 'pendente' end;
  return new;
end $$;
drop trigger if exists comentarios_filtro on public.comentarios;
create trigger comentarios_filtro before insert on public.comentarios
  for each row execute function public.comentarios_filtro();

drop policy if exists "comentarios criar" on public.comentarios;
create policy "comentarios criar" on public.comentarios for insert to authenticated
  with check (estado in ('pendente','retido') and utilizador = (select auth.uid()));
drop policy if exists "comentarios ler" on public.comentarios;
create policy "comentarios ler" on public.comentarios for select to authenticated
  using ((estado = 'aprovado' and tipo in ('comentario','familia','carta')) or (select public.e_professor()));

-- 3) Concurso de fotografia (as fotos ficam numa pasta privada; só as aprovadas se podem ver)
create or replace function public.concurso_info() returns jsonb
language sql stable security definer set search_path = '' as $$
  select case when valor ~ '^\s*\{' then valor::jsonb else '{}'::jsonb end from public.definicoes where chave = 'concurso'
$$;
grant execute on function public.concurso_info() to anon, authenticated;

create table if not exists public.concurso_fotos(
  id uuid primary key default gen_random_uuid(),
  concurso text not null check (char_length(concurso) between 1 and 40),
  path text not null unique check (char_length(path) <= 200),
  nome text check (char_length(nome) <= 30),
  turma text check (char_length(turma) <= 12),
  legenda text check (char_length(legenda) <= 160),
  estado text not null default 'pendente' check (estado in ('pendente','aprovado','rejeitado','retido')),
  utilizador uuid not null default auth.uid(),
  criado timestamptz not null default now()
);
create index if not exists concurso_fotos_c on public.concurso_fotos(concurso, estado);
alter table public.concurso_fotos enable row level security;

create or replace function public.concurso_fotos_proteger() returns trigger
language plpgsql security definer set search_path = '' as $$
declare c jsonb := public.concurso_info();
begin
  if public.e_professor() then return new; end if;
  if coalesce((c->>'aberto')::boolean, false) = false or new.concurso is distinct from c->>'id' then
    raise exception 'o concurso não está a receber fotografias';
  end if;
  if (select count(*) from public.concurso_fotos where concurso = new.concurso and utilizador = auth.uid()) >= 3 then
    raise exception 'só podes enviar 3 fotografias';
  end if;
  new.utilizador := auth.uid();
  new.estado := case when public.tem_palavrao(coalesce(new.legenda, '') || ' ' || coalesce(new.nome, '')) then 'retido' else 'pendente' end;
  return new;
end $$;
drop trigger if exists concurso_fotos_proteger on public.concurso_fotos;
create trigger concurso_fotos_proteger before insert on public.concurso_fotos
  for each row execute function public.concurso_fotos_proteger();

drop policy if exists "concurso ver" on public.concurso_fotos;
drop policy if exists "concurso enviar" on public.concurso_fotos;
drop policy if exists "concurso prof" on public.concurso_fotos;
drop policy if exists "concurso apagar" on public.concurso_fotos;
create policy "concurso ver" on public.concurso_fotos for select to authenticated
  using (estado = 'aprovado' or utilizador = (select auth.uid()) or (select public.e_professor()));
create policy "concurso enviar" on public.concurso_fotos for insert to authenticated
  with check (utilizador = (select auth.uid()) and estado in ('pendente','retido'));
create policy "concurso prof" on public.concurso_fotos for update to authenticated
  using ((select public.e_professor())) with check ((select public.e_professor()));
create policy "concurso apagar" on public.concurso_fotos for delete to authenticated
  using ((select public.e_professor()) or (utilizador = (select auth.uid()) and estado <> 'aprovado'));

create table if not exists public.concurso_votos(
  foto uuid not null references public.concurso_fotos on delete cascade,
  utilizador uuid not null default auth.uid(),
  criado timestamptz not null default now(),
  primary key (foto, utilizador)
);
alter table public.concurso_votos enable row level security;
create or replace function public.concurso_votos_proteger() returns trigger
language plpgsql security definer set search_path = '' as $$
declare c jsonb := public.concurso_info(); f record;
begin
  select concurso, estado into f from public.concurso_fotos where id = new.foto;
  if f is null or f.estado <> 'aprovado' or coalesce((c->>'votacao')::boolean, false) = false or f.concurso is distinct from c->>'id' then
    raise exception 'a votação não está aberta';
  end if;
  if (select count(*) from public.concurso_votos v join public.concurso_fotos x on x.id = v.foto
      where v.utilizador = auth.uid() and x.concurso = f.concurso) >= 3 then
    raise exception 'só podes votar em 3 fotografias';
  end if;
  new.utilizador := auth.uid();
  return new;
end $$;
drop trigger if exists concurso_votos_proteger on public.concurso_votos;
create trigger concurso_votos_proteger before insert on public.concurso_votos
  for each row execute function public.concurso_votos_proteger();
drop policy if exists "cvotos meus" on public.concurso_votos;
drop policy if exists "cvotos criar" on public.concurso_votos;
drop policy if exists "cvotos apagar" on public.concurso_votos;
create policy "cvotos meus" on public.concurso_votos for select to authenticated using (utilizador = (select auth.uid()));
create policy "cvotos criar" on public.concurso_votos for insert to authenticated with check (utilizador = (select auth.uid()));
create policy "cvotos apagar" on public.concurso_votos for delete to authenticated using (utilizador = (select auth.uid()));

create or replace function public.concurso_contagens(p_concurso text) returns table(foto uuid, total bigint)
language sql stable security definer set search_path = '' as $$
  select f.id, count(v.utilizador) from public.concurso_fotos f
  left join public.concurso_votos v on v.foto = f.id
  where f.concurso = p_concurso and f.estado = 'aprovado' group by f.id
$$;
grant execute on function public.concurso_contagens(text) to anon, authenticated;

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('concurso', 'concurso', false, 10485760, array['image/jpeg','image/png','image/webp'])
on conflict (id) do update set public = false, file_size_limit = excluded.file_size_limit,
  allowed_mime_types = excluded.allowed_mime_types;
drop policy if exists "concurso envia foto" on storage.objects;
drop policy if exists "concurso ve foto" on storage.objects;
drop policy if exists "concurso apaga foto" on storage.objects;
create policy "concurso envia foto" on storage.objects for insert to authenticated
  with check (bucket_id = 'concurso' and (storage.foldername(name))[1] = (select auth.uid())::text
    and (coalesce((public.concurso_info()->>'aberto')::boolean, false) or (select public.e_professor())));
create policy "concurso ve foto" on storage.objects for select to authenticated
  using (bucket_id = 'concurso' and ((storage.foldername(name))[1] = (select auth.uid())::text
    or (select public.e_professor())
    or exists (select 1 from public.concurso_fotos f where f.path = name and f.estado = 'aprovado')));
create policy "concurso apaga foto" on storage.objects for delete to authenticated
  using (bucket_id = 'concurso' and ((storage.foldername(name))[1] = (select auth.uid())::text or (select public.e_professor())));

-- 4) Avisos no telemóvel (Web Push). A chave privada VAPID fica em segredos (chave 'vapid_privada'),
--    só a função "avisar" (Edge Function, com a service role) a lê.
create table if not exists public.subscricoes(
  endpoint text primary key check (char_length(endpoint) <= 800),
  dados jsonb not null,
  utilizador uuid default auth.uid(),
  criado timestamptz not null default now()
);
alter table public.subscricoes enable row level security;  -- sem políticas: só as funções abaixo
create or replace function public.guardar_subscricao(p jsonb) returns void
language plpgsql security definer set search_path = '' as $$
begin
  if auth.uid() is null or coalesce(p->>'endpoint', '') !~ '^https://' then raise exception 'subscrição inválida'; end if;
  insert into public.subscricoes(endpoint, dados, utilizador) values (p->>'endpoint', p, auth.uid())
    on conflict (endpoint) do update set dados = excluded.dados, utilizador = excluded.utilizador, criado = now();
end $$;
create or replace function public.apagar_subscricao(p_endpoint text) returns void
language sql security definer set search_path = '' as $$
  delete from public.subscricoes where endpoint = p_endpoint
$$;
create or replace function public.total_subscricoes() returns bigint
language plpgsql stable security definer set search_path = '' as $$
begin
  if not public.e_professor() then raise exception 'sem permissão'; end if;
  return (select count(*) from public.subscricoes);
end $$;
revoke all on function public.guardar_subscricao(jsonb), public.apagar_subscricao(text), public.total_subscricoes() from public, anon;
grant execute on function public.guardar_subscricao(jsonb), public.apagar_subscricao(text), public.total_subscricoes() to authenticated;

-- 5) Artigos: notas da equipa no próprio texto e histórico de versões
alter table public.submissoes add column if not exists anotacoes jsonb not null default '[]'
  check (jsonb_typeof(anotacoes) = 'array' and jsonb_array_length(anotacoes) <= 60);

create or replace function public.submissoes_proteger() returns trigger
language plpgsql set search_path = '' as $$
begin
  new.atualizado := now();
  if tg_op = 'INSERT' then
    new.autor := auth.uid(); new.criado := now();
    if not public.e_professor() then
      new.estado := 'recebido'; new.nota_equipa := null; new.pagina := null; new.anotacoes := '[]';
    end if;
  elsif not public.e_professor() then
    new.autor := old.autor; new.criado := old.criado; new.edicao := old.edicao;
    new.estado := 'recebido'; new.nota_equipa := old.nota_equipa; new.pagina := old.pagina; new.anotacoes := old.anotacoes;
  end if;
  return new;
end $$;

create table if not exists public.submissoes_versoes(
  id bigint generated always as identity primary key,
  submissao uuid not null references public.submissoes on delete cascade,
  titulo text, entrada text, texto text,
  pelo_autor boolean not null default true,
  criado timestamptz not null default now()
);
create index if not exists submissoes_versoes_s on public.submissoes_versoes(submissao, criado desc);
alter table public.submissoes_versoes enable row level security;
drop policy if exists "versoes ler" on public.submissoes_versoes;
create policy "versoes ler" on public.submissoes_versoes for select to authenticated
  using ((select public.e_professor())
    or exists (select 1 from public.submissoes s where s.id = submissao and s.autor = (select auth.uid())));

create or replace function public.submissoes_versao() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  if old.texto is distinct from new.texto or old.titulo is distinct from new.titulo or old.entrada is distinct from new.entrada then
    insert into public.submissoes_versoes(submissao, titulo, entrada, texto, pelo_autor)
      values (old.id, old.titulo, old.entrada, old.texto, not public.e_professor());
    delete from public.submissoes_versoes where submissao = old.id and id not in
      (select id from public.submissoes_versoes where submissao = old.id order by criado desc limit 30);
  end if;
  return new;
end $$;
drop trigger if exists submissoes_versao on public.submissoes;
create trigger submissoes_versao after update on public.submissoes
  for each row execute function public.submissoes_versao();

-- Para os avisos: gerar as chaves VAPID (npx web-push generate-vapid-keys), pôr a pública em CONFIG.vapid
-- no index.html e a privada aqui:
-- insert into public.segredos(chave, valor) values ('vapid_privada', '...'), ('vapid_publica', '...')
--   on conflict (chave) do update set valor = excluded.valor;

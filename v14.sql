-- Repórter da Calheta · Participa — v14: regras mais apertadas na base de dados
-- Correr DEPOIS de supabase.sql, redacao.sql, v12.sql e v13.sql (no editor SQL do Supabase).
-- Não muda nada na app: só impede, do lado do servidor, o que a app já não deixa fazer.
-- Pode correr-se mais de uma vez.

-- 1) Votos: só em blocos que existem, com respostas válidas; quiz e caça ao QR sem segunda tentativa.
--    Antes, um aluno podia gravar votos com chaves inventadas (ex.: 200 "votos" num artigo) e dar
--    centenas de pontos à turma no concurso, ou mudar a resposta do quiz depois de ver a certa.
create or replace function public.votos_validar() returns trigger
language plpgsql security definer set search_path = '' as $$
declare d jsonb; a jsonb; b jsonb; bi int; k int; t text; n int;
begin
  -- sem utilizador (editor SQL do Supabase, service role) ou professor: sem validação
  if auth.uid() is null or public.e_professor() then return coalesce(new, old); end if;
  if tg_op = 'DELETE' then
    -- apagar e voltar a responder seria uma segunda tentativa no quiz ou na caça ao QR
    if old.artigo = '_caca' then raise exception 'só há uma tentativa'; end if;
    select x->'b'->(split_part(old.chave, ':', 1)::int) into b
      from public.edicoes e, jsonb_array_elements(coalesce(e.dados->'artigos', '[]'::jsonb)) x
      where e.numero = old.edicao and x->>'id' = old.artigo and old.chave ~ '^\d{1,3}$' limit 1;
    if b->>'t' = 'quiz' then raise exception 'só há uma tentativa'; end if;
    return old;
  end if;
  select dados into d from public.edicoes where numero = new.edicao;
  if d is null then raise exception 'voto inválido: edição'; end if;

  if new.artigo = '_capa' then
    n := jsonb_array_length(coalesce(d->'capa'->'o', '[]'::jsonb));
    if new.chave <> '0' or new.opcao !~ '^\d{1,2}$' or new.opcao::int >= n then raise exception 'voto inválido: capa'; end if;
    return new;
  end if;

  if new.artigo = '_caca' then
    select c into b from jsonb_array_elements(coalesce(d->'caca', '[]'::jsonb)) c where c->>'id' = new.chave limit 1;
    if b is null or new.opcao !~ '^\d{1,2}$' or new.opcao::int >= jsonb_array_length(coalesce(b->'o', '[]'::jsonb)) then
      raise exception 'voto inválido: caça ao QR';
    end if;
    if tg_op = 'UPDATE' and new.opcao is distinct from old.opcao then raise exception 'só há uma tentativa'; end if;
    return new;
  end if;

  select x into a from jsonb_array_elements(coalesce(d->'artigos', '[]'::jsonb)) x where x->>'id' = new.artigo limit 1;
  if a is null or new.chave !~ '^\d{1,3}(:\d{1,3})?$' then raise exception 'voto inválido: artigo'; end if;
  bi := split_part(new.chave, ':', 1)::int;
  b := a->'b'->bi;
  if b is null then raise exception 'voto inválido: bloco'; end if;
  t := b->>'t';

  if position(':' in new.chave) > 0 then
    k := split_part(new.chave, ':', 2)::int;
    if t <> 'fotos' or k < 1 or k > coalesce((b->>'n')::int, 0) or new.opcao <> '1' then raise exception 'voto inválido: foto'; end if;
    return new;
  end if;

  if t = 'reacoes' then
    if new.opcao not in ('adoro', 'parabens', 'uau', 'riso') then raise exception 'voto inválido: reação'; end if;
  elsif t in ('sondagem', 'quiz') then
    if new.opcao !~ '^\d{1,2}$' or new.opcao::int >= jsonb_array_length(coalesce(b->'o', '[]'::jsonb)) then raise exception 'voto inválido: opção'; end if;
    if t = 'quiz' and tg_op = 'UPDATE' and new.opcao is distinct from old.opcao then raise exception 'só há uma tentativa'; end if;
  elsif t = 'estrelas' then
    if new.opcao not in ('1', '2', '3', '4', '5') then raise exception 'voto inválido: estrelas'; end if;
  elsif t in ('sopa', 'cruzadas') then
    if new.opcao <> '1' then raise exception 'voto inválido: passatempo'; end if;
  else
    raise exception 'voto inválido: este bloco não recebe votos';
  end if;
  if tg_op = 'UPDATE' and (new.edicao, new.artigo, new.chave) is distinct from (old.edicao, old.artigo, old.chave) then
    raise exception 'voto inválido';
  end if;
  return new;
end $$;
drop trigger if exists votos_validar on public.votos;
create trigger votos_validar before insert or update or delete on public.votos
  for each row execute function public.votos_validar();

-- 2) Turma do leitor: tem de ser uma das turmas definidas no painel (Escola → Turmas).
--    Antes, qualquer texto até 12 letras entrava e aparecia no ranking e no modo TV da entrada.
create or replace function public.leitores_validar() returns trigger
language plpgsql security definer set search_path = '' as $$
declare v text; l jsonb;
begin
  if coalesce(new.turma, '') = '' then return new; end if;
  select valor into v from public.definicoes where chave = 'turmas';
  begin l := v::jsonb; exception when others then l := null; end;
  if l is not null and jsonb_typeof(l) = 'array' and jsonb_array_length(l) > 0 and not (l ? new.turma) then
    raise exception 'turma desconhecida';
  end if;
  return new;
end $$;
drop trigger if exists leitores_validar on public.leitores;
create trigger leitores_validar before insert or update on public.leitores
  for each row execute function public.leitores_validar();

-- 3) Redação: as fotos e o áudio de um artigo têm de estar na pasta do próprio autor,
--    e não se enviam artigos novos com a receção fechada (as correções continuam a poder ser feitas).
--    Antes, um aluno podia apontar para fotos de outro aluno; ao apagar esse artigo no painel,
--    as fotos do outro aluno eram apagadas também.
create or replace function public.submissoes_caminhos() returns trigger
language plpgsql security definer set search_path = '' as $$
declare pre text := auth.uid()::text || '/'; r text;
begin
  if auth.uid() is null or public.e_professor() then return new; end if;
  if exists (select 1 from jsonb_array_elements(coalesce(new.fotos, '[]'::jsonb)) f
             where left(coalesce(f->>'path', ''), length(pre)) <> pre) then
    raise exception 'foto inválida';
  end if;
  if coalesce(new.audio, '') <> '' and left(new.audio, length(pre)) <> pre then raise exception 'áudio inválido'; end if;
  if tg_op = 'INSERT' then
    select valor into r from public.definicoes where chave = 'redacao';
    if r ~ '^\s*\{' and (r::jsonb->>'aberta') = 'false' then raise exception 'a receção de artigos está fechada'; end if;
  end if;
  return new;
end $$;
drop trigger if exists submissoes_caminhos on public.submissoes;
create trigger submissoes_caminhos before insert or update on public.submissoes
  for each row execute function public.submissoes_caminhos();

-- 4) Professor: a conta tem de ter o email confirmado, e o email compara-se sem maiúsculas.
--    (Precaução: se o registo por email estiver aberto sem confirmação, alguém podia criar uma conta
--    com o email de um professor antes de este a criar.)
create or replace function public.e_professor() returns boolean
language sql stable security definer set search_path = '' as $$
  select coalesce((auth.jwt() ->> 'is_anonymous')::boolean, false) = false
     and exists (select 1 from public.professores p join auth.users u on lower(u.email) = lower(p.email)
                 where u.id = auth.uid() and u.email_confirmed_at is not null);
$$;

-- 5) As funções dos triggers não se chamam pela API (aviso do Security Advisor do Supabase).
revoke all on function public.votos_validar(), public.leitores_validar(), public.submissoes_caminhos(),
  public.concurso_fotos_proteger(), public.concurso_votos_proteger(), public.submissoes_versao() from public, anon, authenticated;

-- =====================================================================
-- PréventIA Réseau — migration « améliorations de l'audit » (16/11/2026)
-- À exécuter AVANT de publier le nouvel index.html.
-- Ré-exécutable sans risque (if not exists / drop … if exists).
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1. Équipes ouvertes ou sur invitation
-- ---------------------------------------------------------------------
alter table public.teams add column if not exists is_open boolean not null default true;

drop policy if exists tm_insert on public.team_members;
create policy tm_insert on public.team_members for insert to authenticated with check (
  public.is_member(public.team_org(team_id)) and (
    -- on ne s'ajoute soi-même que dans une équipe ouverte
    (user_id = (select auth.uid()) and role = 'membre'
       and exists (select 1 from public.teams t where t.id = team_members.team_id and t.is_open))
    -- sinon, c'est le référent (ou un animateur) qui ajoute un collègue du même SPSTI
    or (public.can_manage_team(team_id) and exists (
          select 1 from public.memberships m
          where m.user_id = team_members.user_id and m.org_id = public.team_org(team_members.team_id)))
  )
);

-- ---------------------------------------------------------------------
-- 2. Rattacher idées, expérimentations et documents à une équipe (étiquette,
--    pas un droit d'accès : la visibilité reste celle choisie dans la fiche)
-- ---------------------------------------------------------------------
alter table public.ideas       add column if not exists team_id uuid references public.teams(id) on delete set null;
alter table public.experiments add column if not exists team_id uuid references public.teams(id) on delete set null;
alter table public.documents   add column if not exists team_id uuid references public.teams(id) on delete set null;
create index if not exists ideas_team_idx       on public.ideas(team_id);
create index if not exists experiments_team_idx on public.experiments(team_id);
create index if not exists documents_team_idx   on public.documents(team_id);

-- ---------------------------------------------------------------------
-- 3. Reproduire une expérimentation partagée par un autre SPSTI
-- ---------------------------------------------------------------------
alter table public.experiments add column if not exists source_id uuid references public.experiments(id) on delete set null;
create index if not exists experiments_source_idx on public.experiments(source_id);

create or replace function public.replication_count(p_exp uuid)
returns integer language sql stable security definer set search_path to '' as $$
  select case when public.is_network_member()
    then (select count(*)::int from public.experiments e where e.source_id = p_exp)
    else 0 end;
$$;

-- ---------------------------------------------------------------------
-- 4. Statut « Solution validée » pour une idée + règle « jamais validée
--    sans test documenté » appliquée aussi aux idées
-- ---------------------------------------------------------------------
alter table public.ideas drop constraint if exists ideas_status_check;
alter table public.ideas add constraint ideas_status_check
  check (status = any (array['nouvelle','a_etudier','retenue','en_test','validee','partagee','non_retenue']));

create or replace function public.ideas_validation_guard()
returns trigger language plpgsql security definer set search_path to '' as $$
begin
  if new.status in ('validee','partagee')
     and (tg_op = 'INSERT' or new.status is distinct from old.status)
     and not exists (select 1 from public.experiments e
                     where e.idea_id = new.id and e.status in ('validee','partagee')) then
    raise exception 'ideas_validation_documentee' using errcode = '23514';
  end if;
  return new;
end $$;
drop trigger if exists ideas_validation on public.ideas;
create trigger ideas_validation before insert or update on public.ideas
  for each row execute function public.ideas_validation_guard();

-- Le statut de l'idée suit celui de son expérimentation (jamais en arrière)
create or replace function public.sync_idea_status()
returns trigger language plpgsql security definer set search_path to '' as $$
declare
  v_new text := case new.status
    when 'selectionnee' then 'retenue' when 'en_test' then 'en_test' when 'en_evaluation' then 'en_test'
    when 'validee' then 'validee' when 'partagee' then 'partagee' else null end;
  ranks constant text[] := array['nouvelle','a_etudier','retenue','en_test','validee','partagee'];
begin
  if new.idea_id is null or v_new is null then return new; end if;
  perform set_config('app.idea_sync', '1', true);
  update public.ideas i set status = v_new
   where i.id = new.idea_id and i.org_id = new.org_id
     and coalesce(array_position(ranks, i.status), 0) < array_position(ranks, v_new);
  perform set_config('app.idea_sync', '', true);
  return new;
end $$;
drop trigger if exists experiments_sync_idea on public.experiments;
create trigger experiments_sync_idea after insert or update of status on public.experiments
  for each row execute function public.sync_idea_status();

-- content_guard : identique à la version en place, avec deux ajouts
--   a) laisse passer la synchronisation automatique ci-dessus ;
--   b) vérifie que l'équipe rattachée appartient au même SPSTI.
create or replace function public.content_guard()
returns trigger language plpgsql security definer set search_path to '' as $function$
declare
  n jsonb := to_jsonb(new);
  o jsonb;
  v_uid uuid := (select auth.uid());
  v_org uuid := (n->>'org_id')::uuid;
  v_mod boolean;
  v_admin boolean;
  patch jsonb := '{}'::jsonb;
  ns text;
  meta text[] := array['updated_at','status','status_note','network_status','visibility','active'];
begin
  if v_uid is null then return new; end if;
  if coalesce(current_setting('app.idea_sync', true), '') = '1' then return new; end if;   -- (a)
  v_mod := public.has_role(v_org, array['animateur','admin_spsti']);
  v_admin := public.has_role(v_org, array['admin_spsti']);

  if n ? 'team_id' and (n->>'team_id') is not null
     and public.team_org((n->>'team_id')::uuid) is distinct from v_org then                 -- (b)
    raise exception 'Cette équipe appartient à un autre SPSTI' using errcode = '42501';
  end if;

  if tg_op = 'INSERT' then
    patch := jsonb_build_object('author_id', v_uid, 'is_demo', false);
    if n ? 'status' and not v_mod then
      patch := patch || jsonb_build_object('status', tg_argv[0]);
    end if;
    if not v_admin then patch := patch || jsonb_build_object('network_status', 'aucun'); end if;
  else
    o := to_jsonb(old);
    -- author_id peut passer à NULL (compte supprimé), jamais être réattribué
    if n->'org_id' <> o->'org_id'
       or (n->'author_id' is distinct from o->'author_id' and n->'author_id' <> 'null'::jsonb)
       or n->'is_demo' <> o->'is_demo' or n->'created_at' <> o->'created_at' then
      raise exception 'Champ non modifiable' using errcode = '42501';
    end if;
    if n ? 'status' and n->'status' <> o->'status' then
      if tg_table_name = 'experiments' then
        if not v_mod and not ((o->>'author_id')::uuid = v_uid
             and n->>'status' in ('en_test','en_evaluation','suspendue')) then
          raise exception 'Ce changement de statut est réservé aux animateurs' using errcode = '42501';
        end if;
      elsif not v_mod then
        raise exception 'Seuls les animateurs peuvent changer le statut' using errcode = '42501';
      end if;
    end if;
    if n ? 'network_status' and n->'network_status' <> o->'network_status' and not v_admin then
      raise exception 'Seul un administrateur SPSTI peut valider un partage réseau' using errcode = '42501';
    end if;
    if (o->>'network_status') = 'approuve' and not v_admin
       and (n - meta - 'author_id') <> (o - meta - 'author_id') then
      patch := patch || jsonb_build_object('network_status', 'en_attente');
    end if;
    patch := patch || jsonb_build_object('updated_at', now());
  end if;

  if n ? 'visibility' then
    ns := coalesce(patch->>'network_status', n->>'network_status');
    if n->>'visibility' <> 'reseau' then ns := 'aucun';
    elsif ns = 'aucun' then ns := 'en_attente';
    end if;
    patch := patch || jsonb_build_object('network_status', ns);
  end if;

  new := jsonb_populate_record(new, patch);
  return new;
end $function$;

-- ---------------------------------------------------------------------
-- 5. Groupes thématiques inter-SPSTI
-- ---------------------------------------------------------------------
create table if not exists public.network_messages (
  id uuid primary key default gen_random_uuid(),
  theme text not null check (theme in ('prevention','sante','ergonomie','organisation','administratif','automatisation')),
  org_id uuid not null references public.organizations(id) on delete cascade,
  author_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
  body text not null check (char_length(body) between 1 and 2000),
  created_at timestamptz not null default now()
);
create index if not exists network_messages_theme_idx on public.network_messages(theme, created_at);
alter table public.network_messages enable row level security;

drop policy if exists netmsg_select on public.network_messages;
create policy netmsg_select on public.network_messages for select to authenticated
  using (public.is_network_member());
drop policy if exists netmsg_insert on public.network_messages;
create policy netmsg_insert on public.network_messages for insert to authenticated
  with check (author_id = (select auth.uid()) and public.is_member(org_id));
drop policy if exists netmsg_delete on public.network_messages;
create policy netmsg_delete on public.network_messages for delete to authenticated
  using (author_id = (select auth.uid()) or public.is_network_admin());

-- ---------------------------------------------------------------------
-- 6. Signalement d'un contenu (donnée sensible, propos déplacé…)
-- ---------------------------------------------------------------------
create table if not exists public.reports (
  id uuid primary key default gen_random_uuid(),
  org_id uuid not null references public.organizations(id) on delete cascade,
  reporter_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
  target_type text not null check (target_type in ('messages','network_messages','idea_comments','prompt_comments','experiment_logs')),
  target_id uuid not null,
  context text check (char_length(context) <= 200),
  excerpt text check (char_length(excerpt) <= 300),
  reason text check (char_length(reason) <= 500),
  resolved_at timestamptz,
  created_at timestamptz not null default now()
);
create index if not exists reports_org_idx on public.reports(org_id, created_at desc);
alter table public.reports enable row level security;

drop policy if exists rep_insert on public.reports;
create policy rep_insert on public.reports for insert to authenticated
  with check (reporter_id = (select auth.uid()) and public.is_member(org_id) and resolved_at is null);
drop policy if exists rep_select on public.reports;
create policy rep_select on public.reports for select to authenticated
  using (reporter_id = (select auth.uid())   -- l'auteur du signalement relit le sien
         or public.has_role(org_id, array['animateur','admin_spsti']) or public.is_network_admin());
drop policy if exists rep_update on public.reports;
create policy rep_update on public.reports for update to authenticated
  using (public.has_role(org_id, array['animateur','admin_spsti']) or public.is_network_admin())
  with check (public.has_role(org_id, array['animateur','admin_spsti']) or public.is_network_admin());

-- ---------------------------------------------------------------------
-- 7. Adhésion : domaines e-mail autorisés par SPSTI (liste vide = pas de filtre)
-- ---------------------------------------------------------------------
alter table public.organizations add column if not exists email_domains text[] not null default '{}';

create or replace function public.join_organization(p_code text)
returns uuid language plpgsql security definer set search_path to '' as $function$
declare
  v_org uuid; v_uid uuid := (select auth.uid());
  v_domains text[]; v_dom text;
begin
  if v_uid is null then raise exception 'Connexion requise' using errcode = '42501'; end if;
  select org_id into v_org from public.org_secrets where join_code = upper(btrim(p_code));
  if v_org is null then raise exception 'Code d''invitation invalide' using errcode = 'P0002'; end if;
  select email_domains into v_domains from public.organizations where id = v_org;
  if coalesce(array_length(v_domains, 1), 0) > 0 then
    select lower(split_part(u.email, '@', 2)) into v_dom from auth.users u where u.id = v_uid;
    if v_dom is null or not (v_dom = any (v_domains)) then
      raise exception 'Adresse e-mail non autorisée pour ce SPSTI : utilisez votre adresse professionnelle.' using errcode = '42501';
    end if;
  end if;
  insert into public.memberships (org_id, user_id, role) values (v_org, v_uid, 'collaborateur')
  on conflict do nothing;
  return v_org;
end $function$;

-- ---------------------------------------------------------------------
-- 8. Prompts : outil / modèle testé, et retour « a marché / n'a pas marché »
-- ---------------------------------------------------------------------
alter table public.prompts add column if not exists model_tested text check (char_length(model_tested) <= 200);
alter table public.prompt_comments add column if not exists worked boolean;

-- ---------------------------------------------------------------------
-- 9. Vue d'ensemble du réseau (uniquement ce qui est produit et partagé)
-- ---------------------------------------------------------------------
create or replace function public.network_stats()
returns table (org_id uuid, validated integer, shared integer, replicated integer)
language sql stable security definer set search_path to '' as $$
  select o.id,
    (select count(*)::int from public.experiments e where e.org_id = o.id and not e.is_demo and e.status in ('validee','partagee')),
    (select count(*)::int from public.ideas x       where x.org_id = o.id and x.network_status = 'approuve')
  + (select count(*)::int from public.experiments x where x.org_id = o.id and x.network_status = 'approuve')
  + (select count(*)::int from public.prompts x     where x.org_id = o.id and x.network_status = 'approuve')
  + (select count(*)::int from public.documents x   where x.org_id = o.id and x.network_status = 'approuve'),
    (select count(*)::int from public.experiments r join public.experiments s on s.id = r.source_id
      where s.org_id = o.id and r.org_id <> o.id)
  from public.organizations o
  where public.is_network_member();
$$;

-- ---------------------------------------------------------------------
-- 10. RGPD : suppression de son propre compte
--     (contributions conservées sans auteur, messages supprimés)
-- ---------------------------------------------------------------------
create or replace function public.delete_my_account()
returns void language plpgsql security definer set search_path to '' as $$
declare v_uid uuid := (select auth.uid());
begin
  if v_uid is null then raise exception 'Connexion requise' using errcode = '42501'; end if;
  if exists (select 1 from public.memberships m
             where m.user_id = v_uid and m.role = 'admin_spsti'
               and not exists (select 1 from public.memberships o
                               where o.org_id = m.org_id and o.role = 'admin_spsti' and o.user_id <> v_uid)) then
    raise exception 'Vous êtes le seul administrateur d''un SPSTI : nommez un autre administrateur avant de supprimer votre compte.' using errcode = '42501';
  end if;
  delete from auth.users where id = v_uid;
end $$;

-- ---------------------------------------------------------------------
-- 11. Droits d'exécution : plus aucune fonction du portail appelable sans connexion
-- ---------------------------------------------------------------------
revoke execute on function public.can_manage_team(uuid), public.is_team_member(uuid), public.team_org(uuid)
  from public, anon;
grant execute on function public.can_manage_team(uuid), public.is_team_member(uuid), public.team_org(uuid)
  to authenticated;
-- fonctions de déclencheur : jamais appelées directement
revoke execute on function public.team_add_creator(), public.ideas_validation_guard(), public.sync_idea_status()
  from public, anon, authenticated;
revoke execute on function public.replication_count(uuid), public.network_stats(), public.delete_my_account()
  from public, anon;
grant execute on function public.replication_count(uuid), public.network_stats(), public.delete_my_account()
  to authenticated;

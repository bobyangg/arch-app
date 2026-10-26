-- Words Arch does not allow.
--
-- Apple asks apps where people post anything for a way to filter objectionable
-- material (App Review Guideline 1.2), and Arch had none: a name, a prompt
-- answer or a message could say anything at all. This is that filter.
--
-- **Two strengths.** Slurs are refused everywhere, messages included. Explicit
-- sexual words and selling (OnlyFans, sugar daddy) are refused only in a
-- profile -- name, pronouns, work, prompt answers, interests -- because a
-- profile is what strangers are shown, and a conversation between two adults
-- who chose to have it is not policed word by word.
--
-- **The app says no first.** The list is `Arch/Resources/BlockedTerms.json`,
-- and this file is generated from it; `ContentFilter` in the app applies the
-- same rules, so the button that would save a blocked word waits with a line
-- saying why, and nobody meets the refusal here. That matters most in
-- onboarding, which saves everything at the end with `try?` -- a name refused
-- here would have been a profile that silently never existed. This is the
-- backstop for an old build, or a client that is not the app.
--
-- **The rules, identical in both places:**
--   whole words only, so "class" is not "ass" and "spicy" is not a slur;
--   look-alikes read as letters (0 o, 1 i, 3 e, 4 a, 5 s, 7 t, @ a, $ s, ! i);
--   a letter written more times still counts ("niiice" is "nice"), but fewer
--   does not ("con" is not "coon");
--   single letters spaced out ("f u c k") are read as one word.
--
-- Reclaimed and ambiguous words are left out on purpose -- queer, dyke, homo,
-- cum (magna cum laude), dick (a name) -- because blocking them would block
-- people describing themselves, a degree, or their own name.
--
-- To add a word: add it to the JSON and to the table, in the same change.
--   insert into private.blocked_terms (term, scope) values ('word', 'profile');

create table if not exists private.blocked_terms (
    term        text primary key check (term ~ '^[a-z]+( [a-z]+)*$'),
    scope       text not null check (scope in ('everywhere', 'profile')),
    added_at    timestamptz not null default now()
);

revoke all on private.blocked_terms from public, anon, authenticated;

insert into private.blocked_terms (term, scope) values
    ('nigger', 'everywhere'),
    ('niggers', 'everywhere'),
    ('nigga', 'everywhere'),
    ('niggas', 'everywhere'),
    ('nigguh', 'everywhere'),
    ('niggah', 'everywhere'),
    ('sandnigger', 'everywhere'),
    ('sandniggers', 'everywhere'),
    ('coon', 'everywhere'),
    ('coons', 'everywhere'),
    ('jigaboo', 'everywhere'),
    ('jigaboos', 'everywhere'),
    ('porchmonkey', 'everywhere'),
    ('porch monkey', 'everywhere'),
    ('jungle bunny', 'everywhere'),
    ('pickaninny', 'everywhere'),
    ('golliwog', 'everywhere'),
    ('darkie', 'everywhere'),
    ('darkies', 'everywhere'),
    ('chink', 'everywhere'),
    ('chinks', 'everywhere'),
    ('gook', 'everywhere'),
    ('gooks', 'everywhere'),
    ('zipperhead', 'everywhere'),
    ('zipperheads', 'everywhere'),
    ('spic', 'everywhere'),
    ('spics', 'everywhere'),
    ('spick', 'everywhere'),
    ('spicks', 'everywhere'),
    ('wetback', 'everywhere'),
    ('wetbacks', 'everywhere'),
    ('beaner', 'everywhere'),
    ('beaners', 'everywhere'),
    ('kike', 'everywhere'),
    ('kikes', 'everywhere'),
    ('christ killer', 'everywhere'),
    ('christ killers', 'everywhere'),
    ('paki', 'everywhere'),
    ('pakis', 'everywhere'),
    ('raghead', 'everywhere'),
    ('ragheads', 'everywhere'),
    ('towelhead', 'everywhere'),
    ('towelheads', 'everywhere'),
    ('squaw', 'everywhere'),
    ('squaws', 'everywhere'),
    ('injun', 'everywhere'),
    ('injuns', 'everywhere'),
    ('honky', 'everywhere'),
    ('honkies', 'everywhere'),
    ('faggot', 'everywhere'),
    ('faggots', 'everywhere'),
    ('fag', 'everywhere'),
    ('fags', 'everywhere'),
    ('faggy', 'everywhere'),
    ('tranny', 'everywhere'),
    ('trannies', 'everywhere'),
    ('shemale', 'everywhere'),
    ('shemales', 'everywhere'),
    ('retard', 'everywhere'),
    ('retards', 'everywhere'),
    ('retarded', 'everywhere'),
    ('spaz', 'everywhere'),
    ('mongoloid', 'everywhere'),
    ('mongoloids', 'everywhere'),
    ('kys', 'everywhere'),
    ('kill yourself', 'everywhere'),
    ('go kill yourself', 'everywhere'),
    ('fuck', 'profile'),
    ('fucks', 'profile'),
    ('fucked', 'profile'),
    ('fucker', 'profile'),
    ('fuckers', 'profile'),
    ('fucking', 'profile'),
    ('fuckin', 'profile'),
    ('motherfucker', 'profile'),
    ('motherfuckers', 'profile'),
    ('cunt', 'profile'),
    ('cunts', 'profile'),
    ('cock', 'profile'),
    ('cocks', 'profile'),
    ('dickhead', 'profile'),
    ('dickheads', 'profile'),
    ('dick pic', 'profile'),
    ('dick pics', 'profile'),
    ('dickpic', 'profile'),
    ('dickpics', 'profile'),
    ('pussy', 'profile'),
    ('pussies', 'profile'),
    ('tits', 'profile'),
    ('titties', 'profile'),
    ('boobs', 'profile'),
    ('slut', 'profile'),
    ('sluts', 'profile'),
    ('whore', 'profile'),
    ('whores', 'profile'),
    ('bitch', 'profile'),
    ('bitches', 'profile'),
    ('asshole', 'profile'),
    ('assholes', 'profile'),
    ('blowjob', 'profile'),
    ('blowjobs', 'profile'),
    ('handjob', 'profile'),
    ('handjobs', 'profile'),
    ('cumshot', 'profile'),
    ('creampie', 'profile'),
    ('gangbang', 'profile'),
    ('horny', 'profile'),
    ('nudes', 'profile'),
    ('sexting', 'profile'),
    ('porn', 'profile'),
    ('porno', 'profile'),
    ('nsfw', 'profile'),
    ('xxx', 'profile'),
    ('dildo', 'profile'),
    ('dildos', 'profile'),
    ('onlyfans', 'profile'),
    ('only fans', 'profile'),
    ('fansly', 'profile'),
    ('cashapp', 'profile'),
    ('cash app', 'profile'),
    ('venmo me', 'profile'),
    ('sugar daddy', 'profile'),
    ('sugardaddy', 'profile'),
    ('sugar baby', 'profile'),
    ('sugarbaby', 'profile'),
    ('sugar mommy', 'profile'),
    ('escort', 'profile'),
    ('escorts', 'profile')
on conflict (term) do update set scope = excluded.scope;

-- The words of a text, as `ContentFilter.words(in:)` makes them.
create or replace function private.arch_words(_text text)
returns text[]
language plpgsql
immutable
set search_path to 'public'
as $function$
declare
    token text;
    words text[] := '{}';
    run text := '';
begin
    if _text is null then
        return words;
    end if;
    foreach token in array regexp_split_to_array(
        translate(lower(_text), '013457@$!', 'oieastasi'), '[^a-z]+')
    loop
        continue when token = '';
        if length(token) = 1 then
            run := run || token;
        else
            if run <> '' then
                words := words || run;
                run := '';
            end if;
            words := words || token;
        end if;
    end loop;
    if run <> '' then
        words := words || run;
    end if;
    return words;
end;
$function$;

-- The first listed term in a text, or null. `_scope` is 'profile' or
-- 'message'; a message is checked against the everywhere list only.
create or replace function private.arch_blocked_term(_text text, _scope text)
returns text
language sql
stable
security definer
set search_path to 'public'
as $function$
    select bt.term
      from private.blocked_terms bt,
           (select array_to_string(private.arch_words(_text), ' ') as joined) w
     where w.joined <> ''
       and (_scope = 'profile' or bt.scope = 'everywhere')
       -- Each letter may be written more times than in the list: c+o+o+n+.
       and w.joined ~ ('(^| )' || regexp_replace(bt.term, '([a-z])', '\1+', 'g') || '( |$)')
     limit 1
$function$;

create or replace function private.refuse_blocked_terms()
returns trigger
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
    hit text;
begin
    if tg_table_name = 'messages' then
        hit := coalesce(private.arch_blocked_term(new.body, 'message'),
                        private.arch_blocked_term(new.plan::text, 'message'));
    elsif tg_table_name = 'profiles' then
        hit := coalesce(private.arch_blocked_term(new.name, 'profile'),
                        private.arch_blocked_term(new.pronouns, 'profile'),
                        private.arch_blocked_term(new.work, 'profile'));
    elsif tg_table_name = 'profile_prompts' then
        hit := private.arch_blocked_term(new.answer, 'profile');
    elsif tg_table_name = 'profile_interests' then
        hit := private.arch_blocked_term(new.text, 'profile');
    end if;
    if hit is not null then
        -- The word is not repeated back.
        raise exception 'This has a word Arch does not allow.'
            using errcode = '23514', detail = tg_table_name;
    end if;
    return new;
end;
$function$;

revoke all on function private.arch_words(text) from public, anon, authenticated;
revoke all on function private.arch_blocked_term(text, text) from public, anon, authenticated;
revoke all on function private.refuse_blocked_terms() from public, anon, authenticated;

drop trigger if exists profiles_refuse_blocked_terms on profiles;
create trigger profiles_refuse_blocked_terms
    before insert or update of name, pronouns, work on profiles
    for each row execute function private.refuse_blocked_terms();

drop trigger if exists profile_prompts_refuse_blocked_terms on profile_prompts;
create trigger profile_prompts_refuse_blocked_terms
    before insert or update of answer on profile_prompts
    for each row execute function private.refuse_blocked_terms();

drop trigger if exists profile_interests_refuse_blocked_terms on profile_interests;
create trigger profile_interests_refuse_blocked_terms
    before insert or update of text on profile_interests
    for each row execute function private.refuse_blocked_terms();

drop trigger if exists messages_refuse_blocked_terms on messages;
create trigger messages_refuse_blocked_terms
    before insert on messages
    for each row execute function private.refuse_blocked_terms();

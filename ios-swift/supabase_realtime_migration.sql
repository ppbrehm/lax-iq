-- Enables Supabase Realtime change broadcasts for live Game Hub sync
-- (assistant coach logs stats/time on one device -> head coach's Game Hub
-- updates live on another, via postgres_changes subscriptions).

alter publication supabase_realtime add table games;
alter publication supabase_realtime add table game_players;

-- Ensures UPDATE/DELETE events carry full previous-row data (not just the
-- primary key), which the app's merge logic and row filters rely on.
alter table games replica identity full;
alter table game_players replica identity full;

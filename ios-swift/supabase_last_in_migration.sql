-- Tracks when a player was last subbed in, so the Game Hub dashboard can show
-- "time on field since last sub in" (separate from their cumulative game time).

alter table game_players add column if not exists last_in_at timestamptz;

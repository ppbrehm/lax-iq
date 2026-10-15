-- Adds scoreboard fields (quarter, opponent's score) used by the Game Hub
-- dashboard. Our own score is derived from the sum of player goals, so it
-- doesn't need a column.

alter table games add column if not exists quarter integer not null default 1;
alter table games add column if not exists opponent_score integer not null default 0;

-- Lets Game Hub's play-call picker filter saved plays by the formation they were
-- built from (1-4-1, 2-2-2, etc.), so a coach can pick a formation, then a play
-- saved under it.

alter table plays add column if not exists formation text;

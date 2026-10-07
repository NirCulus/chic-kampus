-- Reconcile existing inventory metadata with the local seed without replacing stock counts.
insert into public.ingredients (id, name, stock, unit_type, min_stock) values
  ('packaging', 'Kemasan', 50, 'pcs', 5)
on conflict (id) do nothing;

update public.ingredients as ingredient
set name = seed.name,
    unit_type = seed.unit_type,
    min_stock = seed.min_stock
from (values
  ('chicken_sm', 'Ayam Small', 'porsi', 5),
  ('chicken_md', 'Ayam Medium', 'porsi', 5),
  ('chicken_lg', 'Ayam Large', 'porsi', 5),
  ('sauce_classic', 'Classic Cheese Sauce', 'porsi', 5),
  ('sauce_lava', 'Hot Lava Sauce', 'porsi', 5),
  ('sauce_mushroom', 'Magic Mushroom Sauce', 'porsi', 5),
  ('sauce_thunder', 'Black Thunder Sauce', 'porsi', 5),
  ('rice', 'Nasi', 'porsi', 10),
  ('fries', 'Kentang', 'porsi', 10),
  ('packaging', 'Kemasan', 'pcs', 5)
) as seed(id, name, unit_type, min_stock)
where ingredient.id = seed.id;

alter table public.ingredients alter column min_stock set default 0;

update public.stock_ledger
set change_type = 'adjustment'
where change_type in ('restock', 'spoilage', 'manual_adjustment');

alter table public.stock_ledger
  drop constraint if exists stock_ledger_change_type_check;
alter table public.stock_ledger
  add constraint stock_ledger_change_type_check
  check (change_type in ('sale', 'refund', 'adjustment'));

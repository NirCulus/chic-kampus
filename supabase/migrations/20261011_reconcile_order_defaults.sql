-- Match order defaults to the local schema while leaving existing rows unchanged.
alter table public.orders
  alter column payment_status drop default,
  alter column status drop default,
  alter column total_revenue set default 0;

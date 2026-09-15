-- ============================================================
-- Schema for the mini shop system
-- Run this ENTIRELY in Supabase: Dashboard -> SQL Editor -> New query -> Run
-- ============================================================

-- 1) Products table
create table if not exists products (
  id bigint generated always as identity primary key,
  name text not null,
  description text,
  price numeric(10,2) not null,
  stock integer not null default 0,
  created_at timestamptz not null default now()
);

-- 2) Orders table
create table if not exists orders (
  id bigint generated always as identity primary key,
  product_id bigint references products(id),
  customer_name text not null,
  customer_phone text,
  quantity integer not null,
  created_at timestamptz not null default now()
);

-- 3) Row Level Security
alter table products enable row level security;
alter table orders enable row level security;

-- Anyone (anon key, i.e. the public website) can READ products and orders.
-- Writing orders does NOT happen via direct INSERT policy - it goes through
-- the place_order() function below, so stock updates + order creation stay atomic.
create policy "Public can read products" on products
  for select using (true);

create policy "Public can read orders" on orders
  for select using (true);

-- 4) Seed data - a few sample products so the store isn't empty
insert into products (name, description, price, stock) values
  ('כיסא עץ מלא', 'כיסא עץ איכותי בעיצוב כפרי', 249.90, 15),
  ('שולחן קפה זכוכית', 'שולחן קפה מודרני, זכוכית מחוסמת', 399.00, 8),
  ('מנורת רצפה סקנדינבית', 'מנורת רצפה בעיצוב מינימליסטי', 179.50, 20),
  ('ספה תלת מושבית', 'ספת בד רכה בגוון אפור', 1899.00, 5),
  ('שטיח שאגי 200x300', 'שטיח רך ועבה לסלון', 349.00, 10);

-- 5) place_order(): the "extra feature" - atomic inventory management.
-- Checks stock, decrements it, and inserts the order in ONE transaction,
-- so two customers ordering the last item at the same moment can't both succeed
-- (no overselling). This is safer than "read stock in JS, then write" which
-- has a race condition.
create or replace function place_order(
  p_product_id bigint,
  p_customer_name text,
  p_customer_phone text,
  p_quantity integer
) returns orders
language plpgsql
security definer
as $$
declare
  v_stock integer;
  v_order orders;
begin
  if p_quantity is null or p_quantity < 1 then
    raise exception 'Quantity must be at least 1';
  end if;

  -- lock the product row so concurrent orders can't both read the same stock
  select stock into v_stock from products where id = p_product_id for update;

  if v_stock is null then
    raise exception 'Product not found';
  end if;

  if v_stock < p_quantity then
    raise exception 'Insufficient stock: only % left', v_stock;
  end if;

  update products set stock = stock - p_quantity where id = p_product_id;

  insert into orders (product_id, customer_name, customer_phone, quantity)
  values (p_product_id, p_customer_name, p_customer_phone, p_quantity)
  returning * into v_order;

  return v_order;
end;
$$;

grant execute on function place_order(bigint, text, text, integer) to anon, authenticated;

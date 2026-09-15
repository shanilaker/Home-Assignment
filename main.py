"""
FastAPI backend for the mini shop system.

Flow:
  GET  /        -> loads products from Supabase, renders the store page
  POST /order   -> calls the place_order() Postgres function (atomic stock
                   check + decrement + order insert), then redirects back
  GET  /orders  -> loads all orders (joined with product name), renders
                   the business-side page
"""

import os
from typing import Optional

from fastapi import FastAPI, Request, Form
from fastapi.responses import HTMLResponse, RedirectResponse
from fastapi.staticfiles import StaticFiles
from fastapi.templating import Jinja2Templates
from dotenv import load_dotenv
from supabase import create_client, Client

# Load SUPABASE_URL / SUPABASE_KEY from a local .env file (for local runs).
# On Render, these are set as real environment variables instead - either
# way, os.environ picks them up.
load_dotenv()

SUPABASE_URL = os.environ["SUPABASE_URL"]
SUPABASE_KEY = os.environ["SUPABASE_KEY"]

supabase: Client = create_client(SUPABASE_URL, SUPABASE_KEY)

app = FastAPI()
app.mount("/static", StaticFiles(directory="static"), name="static")
templates = Jinja2Templates(directory="templates")


@app.get("/", response_class=HTMLResponse)
def home(request: Request, message: Optional[str] = None, error: Optional[str] = None):
    result = supabase.table("products").select("*").order("id").execute()
    products = result.data
    return templates.TemplateResponse(
        "index.html",
        {"request": request, "products": products, "message": message, "error": error},
    )


@app.post("/order")
def create_order(
    product_id: int = Form(...),
    customer_name: str = Form(...),
    customer_phone: str = Form(""),
    quantity: int = Form(...),
):
    try:
        supabase.rpc(
            "place_order",
            {
                "p_product_id": product_id,
                "p_customer_name": customer_name,
                "p_customer_phone": customer_phone or None,
                "p_quantity": quantity,
            },
        ).execute()
    except Exception as exc:  # noqa: BLE001 - we want to show the DB error to the user
        return RedirectResponse(url=f"/?error={exc}", status_code=303)

    return RedirectResponse(url="/?message=ההזמנה בוצעה בהצלחה", status_code=303)


@app.get("/orders", response_class=HTMLResponse)
def orders_page(request: Request):
    result = (
        supabase.table("orders")
        .select("id, customer_name, customer_phone, quantity, created_at, products(name)")
        .order("created_at", desc=True)
        .execute()
    )
    return templates.TemplateResponse("orders.html", {"request": request, "orders": result.data})

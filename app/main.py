import os
import subprocess

import polars as pl
import usaddress
import sqlite3
from fastapi import FastAPI, Form, Request, status
from fastapi.responses import HTMLResponse, JSONResponse, RedirectResponse
from fastapi.staticfiles import StaticFiles
from fastapi.templating import Jinja2Templates

VERSION = "2.0.0"

app = FastAPI()

# Set up Jinja2 templates
templates = Jinja2Templates(directory="app/templates")

# Serve static files (CSS, JS, etc.)
app.mount("/assets", StaticFiles(directory="app/assets"), name="assets")

# Serve the generated HTML files
app.mount("/outputs", StaticFiles(directory=f"outputs/v{VERSION}"), name="outputs")


@app.get("/", response_class=HTMLResponse)
async def read_root(request: Request):
    """Render the homepage."""
    return templates.TemplateResponse(
        "index.html", {"request": request, "title": "Property Tax Explainer"}
    )


async def search_address(
    search_term: str = Form(...), exact_match: bool = False
):
    add_df = pl.scan_csv("data/Address_Points.csv", infer_schema=False)
    parsed_address = {k: v.lower() for v, k in usaddress.parse(search_term)}

    filtered_df = add_df.clone()
    address_fields_mapping = [
        ("StreetName", "STNAMECOM"),
        ("AddressNumber", "ADDRNOCOM"),
        ("OccupancyIdentifier", "SUBADDCOM"),
        ("PlaceName", "PLACENAME"),
    ]
    f = True

    for usaddress_field, pl_column in address_fields_mapping:
        if usaddress_field in parsed_address:
            f_inexact = (
                pl.col(pl_column)
                .str.to_lowercase()
                .str.contains(parsed_address.get(usaddress_field))
            )
            f_exact = pl.col(
                pl_column
            ).str.to_lowercase().str.strip_chars() == parsed_address.get(
                usaddress_field
            )

            f = False
            filtered_df = filtered_df.filter(f_exact if exact_match else f_inexact)

    if f:
        return []
    
    suggestions = (
        filtered_df.select("ADDRDELIV", "PIN")
        .rename({"ADDRDELIV": "key", "PIN": "value"})
        .head(5)
        .collect()
        .to_dicts()
    )

    return suggestions


@app.post("/address_suggestions")
async def address_suggestions(
    request: Request, search_term: str = Form(...), exact_match: bool = False
):
    
    suggestions = await search_address(search_term, exact_match)
    return JSONResponse(content=suggestions)


@app.get("/searchdb", response_class=HTMLResponse)
async def search_db(
    request: Request, given_pin: str = Form(...)
):
    """Search database."""

    base_dir = os.path.dirname(__file__)  # Directory of the current script
    db_path = os.path.join(base_dir, "../data/ptaxsim-2023.0.0.db") 
    con = sqlite3.connect(db_path)

    cur = con.cursor()
    cur.execute("SELECT * FROM pin WHERE pin = ?", (given_pin,))
    res = cur.fetchall()
    con.close()
    
    if len(res) == 0:
        return False
    else:
        return True


@app.post("/submit", response_class=RedirectResponse)
async def handle_pin(
    request: Request, search_category: str = Form(...), search_term: str = Form(...), search_term_hidden: str = Form(...)
):
    """Handle PIN input and render the QMD file."""
    base_dir = os.path.dirname(__file__)  # Directory of the current script
    qmd_file = os.path.abspath(os.path.join(base_dir, "../ptaxsim_explainer.qmd"))

    if search_category == "three_years":
        prior_year = 2020
    elif search_category == "five_years":
        prior_year = 2018
    else:
        prior_year = 2022

    if len(search_term) == 14 and search_term.isdigit():
        pin = search_term
    
    elif len(search_term_hidden) == 14 and search_term_hidden.isdigit():
        pin = search_term_hidden

    elif isinstance(search_term, str):
        suggestions = await search_address(search_term, exact_match=False)
        if len(suggestions) > 0:
            pin = suggestions[0]['value']

    else:
        wrong_pin = search_term
        return HTMLResponse(
            content=f"<h1>Error: Invalid PIN or Address - {wrong_pin}</h1>",
            status_code=status.HTTP_400_BAD_REQUEST,
        )

    try:
        if not await search_db(request, given_pin=pin):
            if search_term:
                return HTMLResponse(
                content=f"<h1>Error: PIN or Address Not Found in Database - {search_term}</h1>",
                status_code=status.HTTP_400_BAD_REQUEST,
            )

        else:
            # Render the Quarto document with the provided PIN
            print(f"Quarto file path: {qmd_file}")  # Debug: print the path
            print("prior year", prior_year)
            subprocess.run(
                [
                    "quarto",
                    "render",
                    qmd_file,
                    "--to",
                    "html",
                    "--output",
                    f"{pin}.html",
                    "--output-dir",
                    f"outputs/v{VERSION}",
                    "--execute-param",
                    "current_year=2023",
                    "--execute-param",
                    f"prior_year={prior_year}",
                    "--execute-param",
                    f"pin_14={pin}",
                ],
                check=True,
                capture_output=True,
                text=True,
            )

            # Serve the generated HTML
            return RedirectResponse(
                url=f"/outputs/{pin}.html", status_code=status.HTTP_302_FOUND
            )

    except subprocess.CalledProcessError as e:
        return HTMLResponse(
            content=f"<h1>Error rendering the QMD file</h1><p>{e.stderr}</p>",
            status_code=500,
        )

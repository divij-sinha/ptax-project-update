import os
import subprocess

import polars as pl
import usaddress
from fastapi import FastAPI, Form, Request, status
from fastapi.responses import HTMLResponse, JSONResponse, RedirectResponse
from fastapi.staticfiles import StaticFiles
from fastapi.templating import Jinja2Templates

app = FastAPI()

# Set up Jinja2 templates
templates = Jinja2Templates(directory="app/templates")

# Serve static files (CSS, JS, etc.)
app.mount("/assets", StaticFiles(directory="app/assets"), name="assets")

# Serve the generated HTML files
app.mount("/outputs", StaticFiles(directory="outputs"), name="outputs")


@app.get("/", response_class=HTMLResponse)
async def read_root(request: Request):
    """Render the homepage."""
    return templates.TemplateResponse(
        "index.html", {"request": request, "title": "Property Tax Explainer"}
    )


@app.post("/address_suggestions")
async def address_suggestions(
    request: Request, search_term: str = Form(...), exact_match: bool = False
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
            print(filtered_df.collect().shape)

    if f:
        return []

    suggestions = (
        filtered_df.select("ADDRDELIV", "PIN")
        .rename({"ADDRDELIV": "key", "PIN": "value"})
        .head(5)
        .collect()
        .to_dicts()
    )
    return JSONResponse(content=suggestions)


# @app.get("/outputs/", response_class=HTMLResponse)
# async def return_file(pin: str):


@app.post("/submit", response_class=RedirectResponse)
async def handle_pin(
    request: Request, search_term: str = Form(...), search_term_hidden: str = Form(...)
):
    """Handle PIN input and render the QMD file."""
    base_dir = os.path.dirname(__file__)  # Directory of the current script
    qmd_file = os.path.abspath(
        os.path.join(base_dir, "../ptaxsim_explainer_update_as.qmd")
    )
    output_file = os.path.join(base_dir, "../ptaxsim_explainer_update_as.html")

    if len(search_term) == 14 and search_term.isdigit():
        pin = search_term
    elif len(search_term_hidden) == 14 and search_term_hidden.isdigit():
        pin = search_term_hidden
    else:
        return HTMLResponse(
            content=f"<h1>Error: Invalid PIN or Address - {pin}</h1>",
            status_code=status.HTTP_400_BAD_REQUEST,
        )

    try:
        # Render the Quarto document with the provided PIN
        print(f"Quarto file path: {qmd_file}")  # Debug: print the path

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
                "outputs/",
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

        return HTMLResponse(
            content=f"<h1>Error: Output file not found - {output_file}</h1>",
            status_code=500,
        )

    except subprocess.CalledProcessError as e:
        return HTMLResponse(
            content=f"<h1>Error rendering the QMD file</h1><p>{e.stderr}</p>",
            status_code=500,
        )

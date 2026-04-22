import glob
import os
import re
import shutil
import smtplib
import sqlite3
import subprocess
from email.mime.application import MIMEApplication
from email.mime.multipart import MIMEMultipart
from email.mime.text import MIMEText

import mimetypes

import polars as pl
import usaddress
from dotenv import load_dotenv
from email_validator import EmailNotValidError, validate_email
from fastapi import BackgroundTasks, FastAPI, Form, HTTPException, Request, status
from fastapi.responses import HTMLResponse, JSONResponse, RedirectResponse, Response
from fastapi.staticfiles import StaticFiles
from fastapi.templating import Jinja2Templates
from google.cloud import storage
from google.cloud.exceptions import NotFound
from redis import Redis
from rq import Queue

load_dotenv()

MODE = "TIF"  # default mode, can be changed to "PTAX" for explainer
VERSION = "2.3"

# Rendered HTML lives in GCS; the local outputs/ directory is a transient
# staging area only (render_quarto writes there, uploads, then deletes).
GCS_BUCKET = os.getenv("GCS_BUCKET")
if not GCS_BUCKET:
    raise RuntimeError("GCS_BUCKET not set; required for serving and writes.")
GCS_PREFIX = os.getenv("GCS_PREFIX", "ptax-project/outputs").strip("/")
_gcs_client = storage.Client()
_bucket = _gcs_client.bucket(GCS_BUCKET)


def output_filename(mode: str, pin: str, prior_year: int) -> str:
    """TIF reports don't vary by lookback period; PTAX ones do."""
    if mode == "TIF":
        return f"{pin}.html"
    return f"{pin}_{prior_year}.html"


def gcs_blob_name(mode: str, pin: str, fname: str) -> str:
    return f"{GCS_PREFIX}/v{VERSION}/{mode}/{pin}/{fname}"


def gcs_output_exists(mode: str, pin: str, fname: str) -> bool:
    return _bucket.blob(gcs_blob_name(mode, pin, fname)).exists()

redis_conn = Redis()
queue = Queue(connection=redis_conn)
print(f"Redis connection established: {redis_conn}")

# Address CSV loaded once at startup — only the columns needed for lookup/search
_ADDRESS_DF: pl.DataFrame | None = None


def _get_address_df() -> pl.DataFrame:
    global _ADDRESS_DF
    if _ADDRESS_DF is None:
        _ADDRESS_DF = pl.read_parquet("data/address_points.parquet")
    return _ADDRESS_DF


# SQLite connection opened once per process in read-only mode with a warm page cache
_DB_PATH = os.path.join(os.path.dirname(__file__), "../data/ptaxsim-2024.0.0-alpha.1.db")
_db_conn: sqlite3.Connection | None = None


def get_db() -> sqlite3.Connection:
    global _db_conn
    if _db_conn is None:
        _db_conn = sqlite3.connect(f"file:{_DB_PATH}?mode=ro", uri=True, check_same_thread=False)
        _db_conn.execute("PRAGMA cache_size = -65536")  # 64 MB page cache
        _db_conn.execute("PRAGMA temp_store = MEMORY")
    return _db_conn

app = FastAPI()

# Set up Jinja2 templates
templates = Jinja2Templates(directory="app/templates")

# Serve static files (CSS, JS, etc.)
app.mount("/assets", StaticFiles(directory="app/assets"), name="assets")


@app.get("/outputs/{full_path:path}")
def serve_output(full_path: str):
    """Stream rendered HTML (or any sibling asset) from GCS.

    Paths map 1:1 to gs://$GCS_BUCKET/$GCS_PREFIX/v{VERSION}/{full_path}.
    Existing redirects (e.g. /outputs/TIF/12345/12345.html) work unchanged.
    """
    blob = _bucket.blob(f"{GCS_PREFIX}/v{VERSION}/{full_path}")
    try:
        data = blob.download_as_bytes()
    except NotFound:
        raise HTTPException(status_code=404)
    media_type = mimetypes.guess_type(full_path)[0] or "application/octet-stream"
    return Response(
        content=data,
        media_type=media_type,
        headers={"Cache-Control": "public, max-age=31536000, immutable"},
    )


@app.get("/", response_class=HTMLResponse)
async def read_root(request: Request):
    """Render the homepage."""
    return templates.TemplateResponse("index.html", {"request": request, "title": "Property Tax Explainer"})


@app.get("/mode/{mode}", response_class=HTMLResponse)
async def read_root_mode(request: Request, mode: str):
    """Render the homepage."""
    if mode.upper() == "PTAX":
        return templates.TemplateResponse("index_ptax.html", {"request": request, "title": "Property Tax Explainer"})
    elif mode.upper() == "TIF":
        return templates.TemplateResponse("index_tif.html", {"request": request, "title": "TIF Explainer"})
    else:
        return templates.TemplateResponse("index.html", {"request": request, "title": "Property Tax & TIF Explainer"})


@app.post("/email", response_class=HTMLResponse)
# https://medium.com/@abdullahzulfiqar653/sending-emails-with-attachments-using-python-32b908909d73
async def handle_email(request: Request):
    """Handle emailing report."""
    form_data = await request.form()
    email = form_data.get("email_term")

    success_message = None

    try:
        emailinfo = validate_email(email, check_deliverability=False)

        if emailinfo:
            load_dotenv()
            sender_email = os.getenv("sender_email")
            sender_password = os.getenv("sender_password")
            subject = "Email Subject"
            body = "This is the body of the text message"
            recipient_email = email
            smtp_server = os.getenv("smtp_server")
            smtp_port = os.getenv("smtp_port")

            path_to_folder = f"outputs/v{VERSION}/"
            html_files = glob.glob(os.path.join(path_to_folder, "*.html"))
            if html_files:
                path_to_file = max(html_files, key=os.path.getmtime)

            message = MIMEMultipart()
            message["Subject"] = subject
            message["From"] = sender_email
            message["To"] = recipient_email
            body_part = MIMEText(body)
            message.attach(body_part)

            with open(path_to_file, "rb") as file:
                message.attach(MIMEApplication(file.read(), Name="tax_explainer_report.html"))

            with smtplib.SMTP_SSL(smtp_server, smtp_port) as server:
                server.login(sender_email, sender_password)
                server.sendmail(sender_email, recipient_email, message.as_string())

            success_message = "Email sent successfully!"

    except EmailNotValidError as e:
        print(str(e))

    html_file = "outputs/" + os.path.basename(path_to_file)
    redirect_url = f"{html_file}#success_message"

    return RedirectResponse(url=redirect_url, status_code=status.HTTP_302_FOUND)


def get_address_pin(pin: str):
    """Get address from pin."""
    try:
        pin2 = pin[:-4] + "0000"  # condo addresses are for pin10
        df = _get_address_df()
        filtered = df.filter(pl.col("PIN").is_in([pin, pin2])).select("PIN", "ADDRDELIV").to_dict(as_series=False)
        return filtered["ADDRDELIV"][0]
    except Exception as e:
        print(f"Error retrieving address for PIN {pin}: {e}")
        return "--NOT FOUND--"


async def search_address(search_term: str = Form(...), exact_match: bool = False):
    parsed_address = {k: v.lower() for v, k in usaddress.parse(search_term)}

    filtered_df = _get_address_df().lazy()
    address_fields_mapping = [
        ("StreetName", "STNAMECOM"),
        ("StreetNamePreDirectional", "St_PreDir"),
        ("AddressNumber", "ADDRNOCOM"),
        ("OccupancyIdentifier", "SUBADDCOM"),
        ("PlaceName", "PLACENAME"),
    ]
    f = True

    for usaddress_field, pl_column in address_fields_mapping:
        if usaddress_field in parsed_address:
            if usaddress_field == "AddressNumber":
                f_exact = pl.col(pl_column).str.to_lowercase().str.strip_chars() == parsed_address.get(usaddress_field)
                f_inexact = f_exact
            else:
                f_inexact = pl.col(pl_column).str.to_lowercase().str.contains(parsed_address.get(usaddress_field))
                f_exact = pl.col(pl_column).str.to_lowercase().str.strip_chars() == parsed_address.get(usaddress_field)

            f = False
            filtered_df = filtered_df.filter(f_exact if exact_match else f_inexact)

    if f:
        return []

    suggestions = filtered_df.select("ADDRDELIV", "PIN").rename({"ADDRDELIV": "key", "PIN": "value"}).head(5).collect().to_dicts()

    return suggestions


@app.post("/address_suggestions")
async def address_suggestions(request: Request, search_term: str = Form(...), exact_match: bool = False):
    suggestions = await search_address(search_term, exact_match)
    return JSONResponse(content=suggestions)


@app.get("/searchdb", response_class=RedirectResponse)
async def search_db(request: Request, given_pin: str, prior_year: int, address: str, mode: str):
    """Search database."""

    con = get_db()
    cur = con.cursor()
    cur.execute("SELECT * FROM pin WHERE pin = ?", (given_pin,))
    res = cur.fetchall()
    if len(res) == 0:
        # try subpins
        cur.execute(f"SELECT * FROM pin WHERE pin like '{given_pin[:-4]}%'")
        res = cur.fetchall()
        pins = set([r[1] for r in res])
        if len(pins) > 0:
            return templates.TemplateResponse(
                "choose_pin.html",
                {"request": request, "pins": pins, "given_pin": given_pin, "prior_year": prior_year, "mode": mode},
            )
        else:
            return templates.TemplateResponse(
                "message.html",
                {"request": request, "message": f"Error: PIN or Address Not Found in Database - {given_pin}"},
                status_code=404,
            )

    else:
        return RedirectResponse(
            f"/renderdoc?pin={given_pin}&prior_year={prior_year}&address={address}&mode={mode}", status_code=status.HTTP_302_FOUND
        )


@app.get("/renderdoc")
async def render_doc(
    request: Request,
    background_tasks: BackgroundTasks,
    pin: str,
    prior_year: int,
    mode: str,
    address: str = None,
):
    base_dir = os.path.dirname(__file__)  # Directory of the current script
    if mode == "TIF":
        qmd_file = os.path.abspath(os.path.join(base_dir, "../ptaxsim_explainer_tif.qmd"))
    elif mode == "PTAX":
        qmd_file = os.path.abspath(os.path.join(base_dir, "../ptaxsim_explainer.qmd"))
    else:
        raise ValueError(f"Invalid mode: {mode}. Expected 'TIF' or 'PTAX'.")
    try:
        # print(f"Quarto file path: {qmd_file}")  # Debug: print the path
        if address is None:
            address = get_address_pin(pin)
        # print(f"Address for PIN {pin}: {address}")

        # background_tasks.add_task(
        #     run_quarto,
        #     qmd_file=qmd_file,
        #     pin=pin,
        #     prior_year=prior_year,
        #     address=address,
        # )
        job_map_key = f"{mode}:{pin}"
        existing_id = redis_conn.hget("pin_job_map", job_map_key)
        if existing_id:
            existing_job = queue.fetch_job(existing_id.decode())
            if existing_job and not existing_job.is_finished and not existing_job.is_failed:
                print(f"Reusing job {existing_job.id} for PIN {pin} ({mode}).")
                return RedirectResponse(url=f"/processing?pin={pin}&mode={mode}&prior_year={prior_year}", status_code=status.HTTP_303_SEE_OTHER)

        job = queue.enqueue(
            "app.main.run_quarto",
            qmd_file,
            pin,
            prior_year,
            address,
            mode,
            result_ttl=86400,  # keep result for 1 day
        )
        redis_conn.hset("pin_job_map", job_map_key, job.id)
        print(f"Job ID {job.id} for PIN {pin} ({mode}) enqueued.")

        response = RedirectResponse(url=f"/processing?pin={pin}&mode={mode}&prior_year={prior_year}", status_code=status.HTTP_303_SEE_OTHER)
        # print(response)
        return response

    except subprocess.CalledProcessError as e:
        return templates.TemplateResponse(
            "message.html",
            {"request": request, "message": "Error rendering the QMD file - " + e.stderr},
            status_code=500,
        )


@app.post("/submit", response_class=RedirectResponse)
async def handle_pin(
    request: Request,
    search_category: str = Form(...),
    search_term: str = Form(...),
    search_term_hidden: str = Form(...),
    mode: str = Form(...),
):
    """Handle PIN input and render the QMD file."""

    if search_category == "three_years":
        prior_year = 2021
    elif search_category == "five_years":
        prior_year = 2019
    elif search_category == "one_year":
        prior_year = 2023
    else:
        prior_year = 1

    ## replace all non-numeric characters with empty string
    search_term_parsed = re.sub(r"[^\d]", "", search_term)
    search_term_hidden_parsed = re.sub(r"[^\d]", "", search_term_hidden)

    if search_term_parsed.isdigit() and len(search_term_parsed) == 14:
        pin = search_term_parsed
        address = get_address_pin(pin)

    elif search_term_hidden_parsed.isdigit() and len(search_term_hidden_parsed) == 14:
        pin = search_term_hidden_parsed
        address = search_term

    elif isinstance(search_term, str):
        suggestions = await search_address(search_term, exact_match=False)
        if len(suggestions) > 0:
            pin = suggestions[0]["value"]
            address = suggestions[0]["key"]
        else:
            wrong_pin = search_term
            return templates.TemplateResponse(
                "message.html",
                {"request": request, "message": f"Error: Invalid PIN or Address - {wrong_pin}"},
                status_code=400,
            )

    else:
        wrong_pin = search_term
        return templates.TemplateResponse(
            "message.html",
            {"request": request, "message": f"Error: Invalid PIN or Address - {wrong_pin}"},
            status_code=400,
        )

    # Store searches
    output_file = "search_terms.txt"
    with open(output_file, "a") as f:
        # Write the values, separating them with commas
        f.write(f"{search_term}, {search_category}\n")

    fname = output_filename(mode, pin, prior_year)
    if gcs_output_exists(mode, pin, fname):
        # If the file already exists, redirect to it
        return RedirectResponse(url=f"/outputs/{mode}/{pin}/{fname}", status_code=status.HTTP_302_FOUND)

    else:
        return RedirectResponse(
            f"/searchdb?given_pin={pin}&prior_year={prior_year}&address={address}&mode={mode}", status_code=status.HTTP_302_FOUND
        )
        # return HTMLResponse(
        #     content=f"""
        #         <h1>Error: PIN or Address Not Found in Database - {search_term}</h1>
        #         <button onclick="window.location.href='/'">Back</button>
        #     """,
        #     status_code=status.HTTP_400_BAD_REQUEST,
        # )


@app.get("/processing")
async def processing_page(request: Request, pin: str, mode: str, prior_year: int = 2023, n: int = 1, status: str = ""):
    # Render a template that shows "processing" and auto-refreshes
    return templates.TemplateResponse("processing.html", {"request": request, "pin": pin, "n": n, "mode": mode, "prior_year": prior_year})


@app.get("/check_complete")
async def check_complete(request: Request, pin: str, mode: str, prior_year: int = 2023, n: int = 1):
    fname = output_filename(mode, pin, prior_year)
    if gcs_output_exists(mode, pin, fname):
        return RedirectResponse(url=f"/outputs/{mode}/{pin}/{fname}", status_code=status.HTTP_302_FOUND)
    # Check if the job is complete
    raw = redis_conn.hget("pin_job_map", f"{mode}:{pin}")
    if not raw:
        return templates.TemplateResponse(
            "message.html",
            {"request": request, "message": f"Error: Error processing PIN {pin}! Please try again, error reported to admin."},
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
        )
    job_id = raw.decode("utf-8")
    job = queue.fetch_job(job_id)
    if job.is_finished:
        # Job is finished, redirect to the output file
        return RedirectResponse(url=f"/outputs/{mode}/{pin}/{fname}", status_code=status.HTTP_302_FOUND)
    # Check if output file exists or some other completion indicator
    if job.is_failed:
        with open("error_log.txt", "a") as f:
            f.write(f"Error processing PIN {pin} after 10 attempts.\n")
        return templates.TemplateResponse(
            "message.html",
            {"request": request, "message": f"Error: Error processing PIN {pin}! Please try again, error reported to admin."},
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
        )
    return RedirectResponse(url=f"/processing?pin={pin}&n={n + 1}&mode={mode}&prior_year={prior_year}&status={job.get_status()}")


def run_quarto(qmd_file: str, pin: str, prior_year: int, address: str, mode: str, output_root: str | None = None):
    # Each render runs in its own subdir so Quarto's crossref INDEX is not shared
    # (concurrent writes to .quarto/xref/INDEX corrupt it). Passing --output-dir
    # would force Quarto into project mode which re-uses the shared INDEX, so we
    # render to the subdir and upload the output to GCS after. QUARTO_CROSSREF_INDEX_PATH
    # gives each render a unique xref index; PTAX_PROJECT_ROOT lets the QMD's
    # setup chunk setwd()/opts_knit$set(root.dir=...) back to the project root
    # so relative "data/..." paths resolve.
    # output_root is legacy (previously pointed at NAS); all rendered HTML now
    # lives in GCS, so the param is accepted but ignored.
    del output_root
    project_root = os.path.abspath(os.path.dirname(qmd_file))
    ext = os.path.splitext(qmd_file)[1]
    job_stem = f"_job_{mode}_{pin}"
    job_dir = os.path.join(project_root, "_jobs", f"{mode}_{pin}")
    job_qmd = os.path.join(job_dir, f"{job_stem}{ext}")
    fname = output_filename(mode, pin, prior_year)
    job_html = os.path.join(job_dir, fname)

    shutil.rmtree(job_dir, ignore_errors=True)
    os.makedirs(job_dir, exist_ok=True)
    try:
        shutil.copy2(qmd_file, job_qmd)
        # renv's activate.R uses a relative path; write a thin .Rprofile here
        # that sources the project's activate.R via absolute path.
        with open(os.path.join(job_dir, ".Rprofile"), "w") as f:
            f.write(f'source({os.path.join(project_root, "renv/activate.R")!r})\n')
        env = os.environ.copy()
        env["QUARTO_CROSSREF_INDEX_PATH"] = os.path.join(job_dir, "xref.json")
        env["PTAX_PROJECT_ROOT"] = project_root
        env["RENV_PROJECT"] = project_root
        result = subprocess.run(
            [
                "quarto", "render", os.path.basename(job_qmd),
                "--to", "html",
                "--no-clean",
                "--output", fname,
                "--execute-param", "current_year=2024",
                "--execute-param", f"prior_year={prior_year}",
                "--execute-param", f"pin_14={pin}",
                "--execute-param", f"address={address}",
            ],
            check=True,
            capture_output=True,
            text=True,
            env=env,
            cwd=job_dir,
        )
        _bucket.blob(gcs_blob_name(mode, pin, fname)).upload_from_filename(
            job_html, content_type="text/html"
        )
        return {"stdout": result.stdout, "stderr": result.stderr, "returncode": result.returncode}
    except subprocess.CalledProcessError as e:
        print(f"Error: {e.stderr}")
        raise e
    finally:
        shutil.rmtree(job_dir, ignore_errors=True)

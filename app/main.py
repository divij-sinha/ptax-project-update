import subprocess
import os
from fastapi import FastAPI, Form, Request
from fastapi.responses import HTMLResponse
from fastapi.templating import Jinja2Templates
from fastapi.staticfiles import StaticFiles

app = FastAPI()

# Set up Jinja2 templates
templates = Jinja2Templates(directory="templates")

# Serve static files (CSS, JS, etc.)
app.mount("/assets", StaticFiles(directory="assets"), name="assets")

@app.get("/", response_class=HTMLResponse)
async def read_root(request: Request):
    """Render the homepage."""
    return templates.TemplateResponse(
        "index.html", {"request": request, "title": "Property Tax Explainer"}
    )

@app.post("/submit", response_class=HTMLResponse)
async def handle_pin(request: Request, pin: str = Form(...)):
    """Handle PIN input and render the QMD file."""
    base_dir = os.path.dirname(__file__)  # Directory of the current script
    qmd_file = os.path.abspath(os.path.join(base_dir, "../ptaxsim_explainer_update_as.qmd"))
    output_file = os.path.join(base_dir, "../ptaxsim_explainer_update_as.html")

    try:
        # Render the Quarto document with the provided PIN
        print(f"Quarto file path: {qmd_file}")  # Debug: print the path

        subprocess.run(
            ["quarto", "render", qmd_file, "--to", "html", "--execute-param", f"pin_14={pin}"],
            check=True,
            capture_output=True,
            text=True
        )

        # Serve the generated HTML
        if os.path.exists(output_file):
            with open(output_file, "r") as f:
                content = f.read()
            return HTMLResponse(content=content)

        return HTMLResponse(content=f"<h1>Error: Output file not found - {output_file}</h1>", status_code=500)

    except subprocess.CalledProcessError as e:
        return HTMLResponse(content=f"<h1>Error rendering the QMD file</h1><p>{e.stderr}</p>", status_code=500)
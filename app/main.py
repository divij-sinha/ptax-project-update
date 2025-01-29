import subprocess
import os
import shutil
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

    output_folder = os.path.abspath(os.path.join(base_dir, f"../outputs/v2.0"))
    output_file = os.path.join(output_folder, f"{pin}.html")

    output_file_name = f"{pin}.html"
    temp_output_file = os.path.join(base_dir, "../ptaxsim_explainer_update_as.html")
    print(f"Temp output file path: {temp_output_file}")  # Debug: print the path
    final_output_file = os.path.join(output_folder, output_file_name)

    try:
        # Render the Quarto document with the provided PIN
        print(f"Output file path: {output_file}")  # Debug: print the path

        # Serve the generated HTML
        if not os.path.exists(output_file):
            subprocess.run(
                ["quarto", "render", qmd_file, "--to", "html", "--execute-param", f"pin_14={pin}"],
                check=True,
                capture_output=True,
                text=True
            )

            # Move the generated HTML file to the desired output location
            if os.path.exists(temp_output_file):
                shutil.move(temp_output_file, final_output_file)  # Move to final output path
            else:
                return HTMLResponse(content=f"<h1>Error: Temporary output file not found - {temp_output_file}</h1>", status_code=500)


        with open(output_file, "r") as f:
            content = f.read()
        return HTMLResponse(content=content)   
        
        # return HTMLResponse(content=f"<h1>Error: Output file not found - {output_file}</h1>", status_code=500)

    except subprocess.CalledProcessError as e:
        return HTMLResponse(content=f"<h1>Error rendering the QMD file</h1><p>{e.stderr}</p>", status_code=500)
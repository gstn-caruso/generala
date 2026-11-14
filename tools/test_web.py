"""Exercise the exported WebAssembly game in an isolated Chromium context."""
from functools import partial
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
import re
import threading


def smoke_web(folder):
    from playwright.sync_api import sync_playwright

    class QuietHandler(SimpleHTTPRequestHandler):
        def log_message(self, *_args):
            pass

    server = ThreadingHTTPServer(("127.0.0.1", 0), partial(QuietHandler, directory=str(folder.resolve())))
    worker = threading.Thread(target=server.serve_forever, daemon=True)
    worker.start()
    errors = []
    try:
        with sync_playwright() as playwright:
            browser = playwright.chromium.launch(headless=True, args=[
                "--no-sandbox", "--use-gl=angle", "--use-angle=swiftshader", "--enable-unsafe-swiftshader"])
            context = browser.new_context(viewport={"width": 1440, "height": 900})
            page = context.new_page()
            page.on("pageerror", lambda error: errors.append(str(error)))
            page.on("console", lambda message: errors.append(message.text)
                    if message.type == "error" and re.search(r"(?:SCRIPT )?ERROR:|Aborted|RuntimeError", message.text) else None)
            page.goto(f"http://127.0.0.1:{server.server_port}/index.html", wait_until="load")
            page.wait_for_function("""() => {
                const canvas = document.querySelector('canvas');
                const status = document.getElementById('status');
                return canvas && canvas.width > 0 && canvas.height > 0 &&
                    (!status || getComputedStyle(status).display === 'none' ||
                    getComputedStyle(status).visibility === 'hidden');
            }""", timeout=90000)
            page.wait_for_timeout(1200)
            page.mouse.click(210, 420)
            page.wait_for_timeout(900)
            page.keyboard.press("Space")
            page.wait_for_timeout(8500)
            output = Path("build/web-smoke")
            output.mkdir(parents=True, exist_ok=True)
            page.screenshot(path=str(output / "game.png"))
            if errors:
                raise RuntimeError("Web runtime errors: " + "\n".join(errors))
            if page.locator("canvas").count() != 1:
                raise RuntimeError("Missing game canvas")
            print("Web game: Chromium startup and input smoke test passed.")
            context.close()
            browser.close()
    finally:
        server.shutdown()
        server.server_close()
        worker.join(timeout=5)

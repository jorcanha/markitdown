# CLAUDE.md — Guía para agentes

Documento vivo: cualquier agente (o persona) que aprenda algo relevante sobre el proyecto debe añadirlo aquí.
Idioma de trabajo con el propietario: **español**. Código, identificadores y docstrings: **inglés** (como upstream).

## Qué es este repo

- Fork personal de [microsoft/markitdown](https://github.com/microsoft/markitdown) (MIT), en `https://github.com/jorcanha/markitdown`.
- Objetivo: convertir documentos (sobre todo **PDF**) a Markdown para que un LLM (Claude) los procese gastando menos tokens; adaptar la herramienta a las necesidades del propietario, entenderla y mejorarla.
- El historial de upstream está fusionado en `main` (merge con `--allow-unrelated-histories`), así que `git log` muestra los commits originales de Microsoft y se pueden traer cambios nuevos.
- Plan y estado del trabajo: [`PLAN.md`](PLAN.md).

## Reglas de licencia y autoría (obligatorias)

- **No eliminar ni modificar** los avisos de copyright de Microsoft (`LICENSE`, cabeceras `SPDX`, `ThirdPartyNotices.md`, `packages/markitdown-ocr/LICENSE`).
- Archivos **nuevos** del fork pueden llevar: `# SPDX-FileCopyrightText: 2026 Jorge Cañas` + `# SPDX-License-Identifier: MIT`.
- Archivos **modificados** de upstream: conservar la cabecera original; si se añade una línea, que sea adicional, nunca sustituyendo.
- No usar marcas/logos de Microsoft de forma que sugiera respaldo oficial.
- Se puede (y debe) indicar que el trabajo se hace con Claude Code: los commits llevan `Co-Authored-By: Claude ...`.

## Git

- Remotos: `origin` = fork del propietario (push aquí). `upstream` = `https://github.com/microsoft/markitdown.git` (solo lectura).
- Sincronizar con upstream: `git fetch upstream && git merge upstream/main` (resolver conflictos respetando los cambios del fork).
- Hay un clon local de upstream (sin tocar) en `C:\Users\jorge\Documents\github\_markdown\markitdown` — sirve de referencia; **no editarlo**.
- Mensajes de commit: en inglés o español, imperativos y concisos. Cambios grandes en rama propia + PR hacia `main`.

## Entorno de desarrollo (Windows 11, Python 3.13, uv)

```powershell
uv venv --python 3.13 .venv
uv pip install --python .venv -e "packages/markitdown[all]" pytest openai
.venv\Scripts\python -m pytest packages/markitdown/tests -q
.venv\Scripts\markitdown archivo.pdf -o salida.md
```

- Upstream usa `hatch` (`cd packages/markitdown && hatch test`); con uv + pytest funciona igual.
- Formato: `black` (ver `.pre-commit-config.yaml`). Ejecutar `pre-commit run --all-files` o `black packages/` antes de commitear.
- Tests que requieren red (YouTube, Wikipedia remota…) se saltan con la variable `GITHUB_ACTIONS` definida (ver `skip_remote` en `tests/test_module_vectors.py`).
- **Línea base en Windows (2026-11-13, `GITHUB_ACTIONS=1`)**: 138 passed, 33 skipped, 41 failed. Los 41 fallos son del entorno, no del código:
  - 40 tests de CLI (`test_cli_*.py`) ejecutan `subprocess.run(["python", "-m", "markitdown", ...])`; en Windows `python` se resuelve al Python **base** (el `python.exe` del venv es un lanzador), que no tiene el paquete → "No module named markitdown". Arreglo pendiente: usar `sys.executable` en los tests.
  - `test_module_misc.py::test_file_uris` espera rutas POSIX (`/path/to/file.txt`) y en Windows obtiene `C:\path\to\file.txt`.
  - Sin `GITHUB_ACTIONS` además fallan tests de red y `test_speech_transcription` (requiere `ffmpeg`).
- Rutas: la herramienta Bash es Git Bash (`/c/Users/...`); PowerShell también está disponible.

## Arquitectura (paquete `packages/markitdown/src/markitdown/`)

Monorepo con 4 paquetes en `packages/`:

| Paquete | Qué hace |
|---|---|
| `markitdown` | Librería + CLI principal. |
| `markitdown-mcp` | Servidor MCP con una sola tool `convert_to_markdown(uri)` (STDIO / HTTP / SSE). Útil para conectar a Claude. |
| `markitdown-ocr` | Plugin: OCR de imágenes embebidas (PDF/DOCX/PPTX/XLSX) usando un LLM con visión (`llm_client`). Se registra con prioridad `-1.0` para reemplazar a los conversores built-in. |
| `markitdown-sample-plugin` | Ejemplo de plugin (RTF). Plantilla para crear plugins propios. |

Flujo de conversión (`_markitdown.py`):

1. `MarkItDown.convert(source)` despacha según el tipo: `convert_local` (ruta), `convert_uri` (`http/https/file/data:`), `convert_response`, `convert_stream`.
2. `_get_stream_info_guesses()` construye candidatos `StreamInfo` (mimetype, extensión, charset) combinando extensión + **magika** (detección por contenido) + `charset_normalizer`.
3. `_convert()` recorre cada guess × cada conversor ordenado por `priority` (menor = primero; específicos `0.0`, genéricos `10.0`). El primero cuyo `accepts()` sea True y cuyo `convert()` no falle gana.
4. Normalización final: `rstrip` por línea y colapsar 3+ saltos de línea a 2.

- Contrato de conversor: `DocumentConverter.accepts(stream, info, **kw)` **no debe mover** la posición del stream (hay `assert`); `convert()` devuelve `DocumentConverterResult(markdown, title)`.
- Los conversores viven en `converters/`; se registran en `MarkItDown.enable_builtins()` (el último registrado con igual prioridad se prueba primero).
- Dependencias opcionales por formato (`[pdf]`, `[docx]`…); si faltan, el conversor lanza `MissingDependencyException` al convertir.
- Plugins: entry point `markitdown.plugin` con función `register_converters(markitdown, **kwargs)`; solo se activan con `enable_plugins=True` / `--use-plugins`.

### Conversor PDF (`converters/_pdf_converter.py`) — el más relevante para este fork

- Usa **pdfplumber** página a página: `_extract_form_content_from_words()` intenta detectar tablas/formularios sin bordes por posición de palabras; si la página no parece formulario usa `page.extract_text()`.
- Si **ninguna** página es formulario, descarta lo anterior y re-extrae todo con **pdfminer** (`extract_text`) → mejor espaciado en prosa, pero el PDF se parsea dos veces.
- Post-proceso: `_merge_partial_numbering_lines` (numeración estilo MasterFormat `.1`, `.2`).
- Limitaciones conocidas (oportunidades de mejora, ver `PLAN.md`):
  - Salida mayormente **texto plano**: no detecta encabezados (`#`), negritas ni listas.
  - No elimina encabezados/pies de página repetidos ni números de página → tokens desperdiciados.
  - No une palabras cortadas por guion al final de línea ni párrafos partidos por saltos de línea.
  - No inserta marcadores de página (útiles para citar "pág. N").
  - PDFs escaneados → salida vacía salvo plugin OCR (requiere LLM con visión, cuesta tokens) o Azure Document Intelligence.
  - `_extract_tables_from_words()` es **código muerto** (no se usa en ningún sitio).

## Convenciones para cambios

- Preferir cambios **opt-in** (parámetros/flags nuevos con valor por defecto que mantenga el comportamiento de upstream) para facilitar merges futuros y no romper tests.
- Todo cambio de comportamiento debe venir con test en `packages/markitdown/tests/` (ficheros de prueba en `tests/test_files/`).
- Medir el impacto en tokens: comparar tamaño de salida (caracteres / tokens aproximados ≈ chars/4) antes y después en un PDF de muestra.
- No subir PDFs personales o confidenciales al repo (es público). Usar `/output/` (ignorado) para pruebas locales.

## Registro de decisiones y hallazgos

- 2026-11-13: Creación del fork a partir del clon local de upstream (commit `a51f725`, versión `0.1.6b2`). LICENSE con doble copyright (Microsoft + Jorge Cañas). README con aviso de fork. `.gitignore` = plantilla Python de GitHub + entradas de upstream + `/output/`.

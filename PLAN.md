# Plan de trabajo del fork

Estado: `[ ]` pendiente · `[~]` en curso · `[x]` hecho. Actualizar este archivo al avanzar.

## Fase 0 — Puesta en marcha

- [x] Fusionar historial de `microsoft/markitdown` en este repo (remoto `upstream`).
- [x] LICENSE con copyright de Microsoft + propietario del fork; aviso de fork en README.
- [x] Crear `CLAUDE.md` (guía para agentes) y este `PLAN.md`.
- [x] Entorno local con `uv` y ejecución de la suite de tests como línea base.
- [x] Ajustar `pyproject.toml` (URLs del proyecto apuntando al fork, autor adicional) **sin** publicar en PyPI con el nombre `markitdown` (ya existe; si algún día se publica, usar otro nombre).
- [ ] Hacer que la suite pase en Windows: usar `sys.executable` en lugar de `"python"` en `test_cli_*.py` y adaptar `test_file_uris` a rutas Windows (ver `CLAUDE.md`).
- [ ] Decidir si se mantienen los workflows de GitHub Actions de upstream (tests + pre-commit) — en principio sí, son gratis en repos públicos.

## Fase 1 — Entender y medir (sin cambiar comportamiento)

- [ ] Reunir un conjunto de PDFs de prueba representativos de mi uso real (prosa, tablas, escaneados, multicolumna) — fuera del repo si son privados.
- [ ] Script `scripts/benchmark_tokens.py`: convierte una carpeta y reporta por archivo tamaño del PDF, caracteres de salida, tokens aproximados y tiempo. Opcional: tokens exactos con la API de conteo de tokens de Anthropic.
- [ ] Comparar contra alternativas (p. ej. `pymupdf4llm`, `docling`) en calidad y tokens, para decidir dónde vale la pena invertir.

## Fase 2 — Mejoras para PDF (opt-in, con tests)

Ordenadas por relación impacto/esfuerzo para ahorrar tokens y mejorar la comprensión del LLM:

1. [ ] **Limpieza de ruido**: quitar encabezados/pies repetidos en muchas páginas y números de página sueltos.
2. [ ] **Reflujo de texto**: unir palabras cortadas con guion al final de línea y líneas de un mismo párrafo.
3. [ ] **Limpieza de caracteres**: ligaduras (`ﬁ`→`fi`), `(cid:NN)`, espacios múltiples, caracteres de control.
4. [ ] **Marcadores de página** opcionales (`<!-- page 3 -->`) para poder citar.
5. [ ] **Encabezados**: inferir `#`/`##` a partir del tamaño de fuente (pdfplumber da `size` por carácter).
6. [ ] **Rendimiento**: evitar el doble parseo (pdfplumber + pdfminer) cuando no hay formularios.
7. [ ] Eliminar código muerto `_extract_tables_from_words` (o reutilizarlo).
8. [ ] Detectar PDFs escaneados (sin capa de texto) y avisar claramente en lugar de devolver vacío; opción de OCR local (p. ej. Tesseract) sin coste de tokens.

## Fase 3 — Flujo de trabajo con Claude

- [ ] Conversión por lotes de una carpeta: `markitdown-batch <carpeta> -o <salida>` (recursivo, salta los ya convertidos, log de errores).
- [ ] Configurar `markitdown-mcp` en Claude Code / Claude Desktop y documentarlo aquí.
- [ ] Opcional: modo "compacto" que aplique todas las limpiezas de la fase 2 de una vez (`--compact`).

## Fase 4 — Mantenimiento

- [ ] Sincronizar periódicamente con `upstream/main` y anotar en `CLAUDE.md` los conflictos relevantes.
- [ ] Valorar proponer a upstream (PR) las mejoras genéricas que funcionen bien.

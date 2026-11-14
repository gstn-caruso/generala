# Contribuir

Usá Godot **4.7.2 estándar**, Python 3 y una rama por cambio. La interfaz y las
reglas de la mesa están en español. Conservá las partidas locales existentes al
modificar la persistencia y verificá los puntos visibles si cambiás el dado 3D.

## Validación local

```bash
python3 -m unittest discover -s tools -p 'test_*.py'
GODOT="$HOME/.local/share/generala/godot-4.7.2" python3 tools/check.py
```

El runner realiza una importación limpia en una copia temporal y ejecuta los
tests con datos de usuario aislados. También podés ejecutar los tests individuales
que aparecen en el README.

## Pull requests y versiones

Los títulos de PR siguen Conventional Commits. GitHub usa el título y el cuerpo
del PR para el commit de squash:

- `feat: agregar una función` publica una versión menor.
- `fix: corregir un problema`, `perf:` y `revert:` publican un parche.
- `feat!: cambiar un formato` o un pie `BREAKING CHANGE: ...` publican una versión mayor.
- `docs:`, `ci:`, `test:`, `build:`, `chore:`, `refactor:` y `style:` no publican por sí solos.

La primera versión es `0.1.0`. Los tags `vMAJOR.MINOR.PATCH` son la fuente del
versionado; no hace falta editar `version.txt` en cada PR. Si hay varios cambios,
se aplica el incremento mayor. La política de cambios incompatibles también se
aplica antes de `1.0.0`.

Antes de integrar un PR deben pasar `PR title` y `Verify and package`. Al integrar
en `main`, el workflow vuelve a verificar, exporta y prueba el binario real. Si
corresponde una versión, publica el ZIP Linux x86_64 y `SHA256SUMS.txt`.

El release se prepara como borrador y se hace visible después de subir los
archivos. Un reintento verifica el commit del tag; un release ya publicado se
conserva. Los cambios de documentación siguen pasando las pruebas sin crear una
nueva versión.

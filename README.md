Eres “CodeAgent”, un copiloto de código 100% determinista y local (sin LLM). 
Objetivo: autocompletar, refactorizar, explicar, generar tests y navegar proyectos en cualquier lenguaje soportado por medio de proveedores de lenguaje (Language Providers).

**Principios:**
- Determinismo: misma entrada ⇒ misma salida.
- Veracidad técnica: solo propones símbolos/llamadas que existen en el proyecto, toolchains instaladas y base de conocimiento local (KB).
- Multilenguaje expandible: puedes cargar y descargar Providers en caliente.
- Seguridad: no realizas acciones destructivas sin mostrar un diff previo.
- Telemetría local: aprendes del repositorio contando usos (estadísticas) pero sin IA.

**Capacidades:**
1. Autocompletar por contexto (AST/Tipos/Alcance), plantillas y firmas existentes.
2. Quick-Fixes y refactors seguros (Rename, Extract, Inline, Move, Change Signature).
3. Explicar código con plantillas deterministas (AST+CFG+Docstrings).
4. Generar esqueletos de tests por lenguaje/framework.
5. Búsqueda y salto semántico (símbolos, referencias, similitud lexical/estructura).
6. “Aprendizaje” no-ML: actualizas la KB con símbolos, patrones, métricas de uso, APIs, snippets y anti-patrones detectados.

**Reglas:**
- Nunca inventes APIs ni funciones inexistentes.
- Si hay conflicto entre reglas: gana la de tipos > alcance > popularidad > prefijo.
- Ofrece siempre alternativas clasificadas por compatibilidad de tipo y proximidad de scope.
- Antes de aplicar refactors, valida parseo y compila/formatea si el toolchain lo permite.

**Interfaz:**
- Protocolo LSP estándar + comandos custom (`generateTests`, `explainRange`, `findSimilar`, `importDocs`, `learnLanguagePack`).
- Entrada y salida en JSON, sin llamadas externas.

---

## “Aprender cualquier lenguaje”: diseño por Language Providers

Cada lenguaje es un plugin con esta interfaz mínima:

```ts
// Pseudo-TS (aplica igual en Go/Rust)
export interface LanguageProvider {
  id: string;                         // "python", "rust", "ts", "java", ...
  files: string[];                    // extensiones soportadas
  parse(text: string, uri: string): ASTResult;           // AST + tabla de símbolos
  typeInfo?(projectRoot: string): TypeIndex;             // opcional (TS/Go/Rust/Java)
  cfg(ast: ASTResult): CFG;                              
  lint(ast: ASTResult, cfg: CFG): Diagnostic[];
  quickFixes(ast: ASTResult, diag: Diagnostic): TextEdit[];
  refactors(ast: ASTResult, sel: Range): RefactorPlan[];
  snippets(context: CompletionCtx): Snippet[];
  frameworkHints?(projectRoot: string): FrameworkHint[]; // Django/Express/Spring/etc.
  testScaffold(symbol: Symbol): TestFile;                // pytest/JUnit/Jest/go test...
  format?(uri: string, code: string): string;            // usa toolchain si existe
  discoverToolchain?(): ToolchainInfo;                   // “tengo go, rustc, node, javac…"
}
```

### Cómo “aprende” un lenguaje nuevo (sin ML):

- Añades el Provider (tree-sitter + reglas + snippets + test templates).
- Ejecutas `learnLanguagePack` con:
  - gramática (tree-sitter o parser nativo),
  - reglas (quick-fix/refactor),
  - plantillas y convenciones (formato, test runner, layout),
  - ingestión de documentación (ver ETL abajo).
- El agente indexa tu repo y la doc importada: recuerda símbolos, patrones más usados, errores frecuentes, imports típicos, rutas de proyecto.

---

## Base de conocimiento local (KB): “todo lo que sabe”

Persistencia en SQLite (o LMDB). Esquema clave:

```sql
-- Archivos y símbolos
CREATE TABLE file (
  id INTEGER PRIMARY KEY,
  uri TEXT UNIQUE, hash TEXT, lang TEXT, mtime INTEGER
);
CREATE TABLE symbol (
  id INTEGER PRIMARY KEY,
  file_id INTEGER, name TEXT, kind TEXT, signature TEXT,
  visibility TEXT, range_start INTEGER, range_end INTEGER,
  doc TEXT, FOREIGN KEY(file_id) REFERENCES file(id)
);
CREATE TABLE reference (
  id INTEGER PRIMARY KEY,
  symbol_id INTEGER, file_id INTEGER, pos INTEGER,
  FOREIGN KEY(symbol_id) REFERENCES symbol(id),
  FOREIGN KEY(file_id) REFERENCES file(id)
);

-- Índices de búsqueda (lexical/trigram)
CREATE VIRTUAL TABLE code_fts USING fts5(content, uri, lang, tokenize='unicode61');
CREATE TABLE trigram ( tri TEXT, symbol_id INTEGER, freq INTEGER );

-- Tipos y relaciones
CREATE TABLE type_info (
  symbol_id INTEGER PRIMARY KEY, type_text TEXT, nullable INTEGER
);
CREATE TABLE call_graph ( caller_id INTEGER, callee_id INTEGER );

-- Reglas, snippets y patrones
CREATE TABLE rule (
  id TEXT PRIMARY KEY, lang TEXT, pattern TEXT, action TEXT, severity TEXT
);
CREATE TABLE snippet (
  id TEXT PRIMARY KEY, lang TEXT, prefix TEXT, body TEXT, description TEXT, framework TEXT
);
CREATE TABLE pattern_stats (
  id TEXT PRIMARY KEY, lang TEXT, kind TEXT, text TEXT, uses INTEGER, last_used INTEGER
);

-- Documentación y APIs importadas
CREATE TABLE api (
  id INTEGER PRIMARY KEY, lang TEXT, lib TEXT, name TEXT, signature TEXT, doc TEXT
);
CREATE TABLE api_index ( token TEXT, api_id INTEGER );
CREATE TABLE cheat ( id INTEGER PRIMARY KEY, lang TEXT, topic TEXT, body TEXT );

-- Métricas y preferencias del proyecto/sesión
CREATE TABLE usage (
  id INTEGER PRIMARY KEY, symbol_id INTEGER, used_at INTEGER
);
CREATE TABLE config (
  key TEXT PRIMARY KEY, value TEXT
);
```

### Qué guarda “todo lo que sabe”:

- Definiciones del repo (símbolos, firmas, docstrings).
- Doc/API offline (stdlib, librerías populares).
- Snippets y reglas propias + de cada framework.
- Patrones frecuentes (por conteo de uso, no por IA).
- Antipatrones detectados (linters/CFG).
- Preferencias del usuario/proyecto (estilo, runners, formateador).

---

## ETL de conocimiento (importar “lo que sabe” Copilot… localmente, sin Copilot)

No copiamos Copilot; construimos tu propia KB:

**Fuentes (offline):**
- Documentación estándar por lenguaje (p. ej., pydoc → HTML/JSON; go doc; Javadoc JDK).
- Doc de libs instaladas (pip/npm/cargo/maven/nuget) parseada a texto.
- Cheatsheets/Manpages locales (convertidas a Markdown).
- Tu repo y repos locales espejo (si tienes monorepos de referencia).

**Pipeline (comando importDocs):**
- Descubrir toolchain y libs instaladas.
- Extraer doc → normalizar a Markdown plano.
- Tokenizar y meter en api / api_index / cheat / code_fts.
- Generar snippets a partir de usage examples detectados (heurística de bloques con llamadas típicas).
- Indexar.

**Ejemplo CLI:**
```bash
codeagent importDocs --lang python --stdlib --pip-env .venv
codeagent importDocs --lang ts --npm --framework express
codeagent importDocs --lang go --gopath auto
```

---

## Autocompletado y ranking (multi-lenguaje, sin ML)

**Entrada de contexto:** nodo AST en cursor, tipo esperado, símbolos visibles, tokens previos, framework hints.

**Candidatos:**
- símbolos del scope,
- API de KB compatibles por tipo,
- snippets acordes al patrón,
- imports disponibles.

**Score determinista:**
```markdown
score = 0.25 ScopeProximity
      + 0.25 TypeMatch
      + 0.15 Popularity(references_count)
      + 0.10 PathSimilarity
      + 0.10 RecentUse
      + 0.10 LexicalPrefix
      + 0.05 DocHint
```
Empate: orden alfabético estable.

---

## Quick-Fixes y Refactors (extensibles por lenguaje)

**Quick-Fixes base:** import faltante, variable no usada, null-check, SQL parametrizado, cierre de I/O, shadowing, n+1 en ORM.  
**Refactors base:** Rename, Extract Var/Method, Inline, Move, Change Signature.

Cada regla es un archivo declarativo + ejecutor:

```yaml
id: python.missing_import
lang: python
pattern: "UnresolvedName(name)"
action: "InsertImport(name, module=ResolveModule(name))"
severity: "warning"
```

---

## Explicación determinista (hover/panel)

**Plantilla por símbolo:**
- Qué es (función/clase) + firma y tipo.
- Resumen (de docstring, 1–2 frases).
- Flujo (CFG: ramas, excepciones).
- Dependencias (call graph).
- Complejidad ciclomatica y LOC.
- Sin texto creativo: ficha técnica con enlaces “go to definition”.

---

## Generación de tests (por lenguaje)

- Python: pytest + parametrize.
- TS/JS: Jest + mocks desde interfaces.
- Go: _test.go con tablas.
- Java: JUnit5 parametrizado.
- C#: xUnit/NUnit según config.

**Comando:**
```bash
codeagent generateTests --symbol mypkg.Util.Normalize
```

---

## Cliente VS Code + LSP

Inline suggestions (ghost text), hover, code actions, refactors, panel KB (APIs/snippets), y comandos:

- CodeAgent: Generate Tests
- CodeAgent: Explain Selection
- CodeAgent: Find Similar
- CodeAgent: Import Docs
- CodeAgent: Learn Language Pack

**settings.json (ejemplo):**
```json
{
  "codeagent.langPacks": ["python", "ts", "go", "rust", "java"],
  "codeagent.dbPath": ".codeagent/kb.sqlite",
  "codeagent.indexOnOpen": true,
  "codeagent.snippetFrameworks": ["django", "express", "spring"]
}
```

---

## Esqueleto mínimo del servidor (Go)

```go
// main.go
func main() { StartLSP() }
```
```go
// suggest/score.go
func Score(c Candidate, ctx Ctx) float64 { /* fórmula determinista */ }
```
```go
// kb/schema.go
// Ejecuta migraciones SQL (las tablas de arriba).
```
```go
// provider/registry.go
var Providers = map[string]LanguageProvider{}
func Register(p LanguageProvider) { Providers[p.ID()] = p }
```
```go
// provider/python/python.go
type PyProvider struct {/*...*/}
func (p *PyProvider) Parse(text, uri string) ASTResult { /* tree-sitter-python */ }
func (p *PyProvider) TestScaffold(sym Symbol) TestFile { /* pytest templates */ }
```

---

## Cómo “aprender” un lenguaje nuevo en 30 minutos

1. Copia un Provider base (`provider/template/`).
2. Sustituye parse, snippets, quickFixes, testScaffold, format.
3. Añade gramática tree-sitter del lenguaje.
4. Ejecuta:

```bash
codeagent learnLanguagePack --from provider/ruby --id ruby
codeagent importDocs --lang ruby --stdlib --gems
```
5. Reindexa el proyecto. Listo.

---

## “Añade una base de datos con todo lo que él sabe”

Hecho: la KB anterior. Para “llenarla” rápido:

```bash
codeagent index --project .
codeagent importDocs --lang python --stdlib --pip-env .venv
codeagent importDocs --lang ts --npm
codeagent importDocs --lang go --gopath auto
codeagent minePatterns --project . --min-uses 3
```
- index: símbolos y referencias del repo.
- importDocs: APIs y doc local de toolchains.
- minePatterns: extrae snippets de uso frecuente (sin IA: por frecuencia + AST shape).

---

## Seguridad, rendimiento y calidad

- Todo local; sin red.
- Cachés mmap + parsing incremental.
- Watch FS para invalidar índices.
- Golden tests de sugerencias por contexto; dry-run de refactors con diff; p95 latency < 50 ms por completion.

---

## Roadmap de activación

- MVP: Python + TS + Go; KB SQLite; VS Code extension.
- Refactors avanzados: Change Signature + Move across modules.
- Packs de frameworks: Django/Express/Spring.
- Packs extra: Rust/Java/C#/C++.
- Minería de patrones: librerías internas; cheats locales.
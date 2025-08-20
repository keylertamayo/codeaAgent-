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

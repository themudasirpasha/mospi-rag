# MoSPI Scraper + LLaMA-powered Q&A Chatbot

A production-quality pipeline that:
1. **Scrapes** statistical publications and press releases from [MoSPI](https://mospi.gov.in)
2. **Extracts** text and tables from PDFs
3. **ETL** validates, chunks, and exports data to Parquet + SQLite
4. **Indexes** text chunks in a FAISS vector store
5. **Answers** natural-language questions using LLaMA 3 (via Ollama) with source citations

---

## Architecture

```
MoSPI Website
    │
    ▼  scraper/crawl.py  (HTTPX + BeautifulSoup)
SQLite DB  ◄──────────────────────────────────────┐
    │         scraper/parse.py (pdfplumber)        │
    │         → data/raw/pdf/*.pdf                 │
    │         → tables stored in DB                │
    ▼
pipeline/run.py
    ├─ validate.py   (title / date / URL checks)
    ├─ chunker.py    (1000-token windows, 150 overlap)
    ├─ chunks.parquet
    └─ datasets/catalog.json
    │
    ▼
rag/retriever.py  (SentenceTransformers → FAISS)
    │
    ▼
rag/api.py  (FastAPI)   POST /ask → LLaMA 3 via Ollama → answer + citations
    │
    ▼
rag/ui/app.py  (Streamlit)  ← browser
```

---

## Quick Start

### 1. Prerequisites

- Python 3.11+
- [Docker](https://docs.docker.com/get-docker/) + Docker Compose
- [Ollama](https://ollama.com/download) (or let Docker manage it)

### 2. Clone & configure

```bash
git clone https://github.com/your-username/mospi-rag
cd mospi-rag
cp .env.example .env
```

### 3. Install dependencies (local dev)

```bash
make install
# or: pip install -r requirements.txt
```

### 4. Run the full pipeline locally

```bash
# Step 1 — Crawl MoSPI listings
make crawl

# Step 2 — Download & parse PDFs
make parse

# Step 3 — Validate, chunk, export Parquet + catalog
make etl

# Step 4 — Build FAISS vector index
make index

# Step 5 — Print a run summary
make report
```

### 5. Start the chatbot (Docker)

```bash
# Start Ollama + API + UI
make up

# Pull the LLaMA 3 model (first time only, ~4 GB)
docker exec -it mospi-rag-ollama-1 ollama pull llama3
```

Open **http://localhost:8501** in your browser.

---

## Running with Docker Compose

```bash
# Start all services
docker compose up --build

# Run scraper on demand
docker compose --profile scraper up scraper

# Run ETL + index rebuild on demand
docker compose --profile pipeline up pipeline

# Stop everything
docker compose down
```

---

## CLI Reference

```bash
# Crawl with custom seed URL and page limit
python -m scraper.crawl --seed-url https://mospi.gov.in/press-releases --max-pages 5

# Parse/download PDFs
python -m scraper.parse

# Show run summary
python -m scraper.report

# Run ETL pipeline
python -m pipeline.run

# Build vector index
python -m rag.retriever --build

# Test a query against the index
python -m rag.retriever --query "What is the GDP growth rate for Q3 2024?"
```

---

## API Endpoints

| Method | Path      | Body / Response |
|--------|-----------|-----------------|
| GET    | `/health` | `{status, model}` |
| POST   | `/ask`    | `{question, top_k?, temperature?}` → `{answer, citations[]}` |
| POST   | `/ingest` | Rebuilds index → `{status, message}` |

**Example:**
```bash
curl -X POST http://localhost:8000/ask \
  -H "Content-Type: application/json" \
  -d '{"question": "What was the CPI inflation in January 2024?", "top_k": 5}'
```

---

## Tests

```bash
make test
# or:
pytest scraper/tests/ pipeline/tests/ -v
```

- **Unit tests**: HTML parser, date normaliser, category mapping, document validator, text chunker
- **Integration tests**: End-to-end mock crawl → DB → ETL → chunk pipeline, PDF extraction

---

## Data Artifacts

| Path | Description |
|------|-------------|
| `data/mospi.db` | SQLite with `documents`, `files`, `tables` |
| `data/raw/pdf/` | Downloaded PDF files |
| `data/processed/chunks.parquet` | Chunked text with doc lineage |
| `data/processed/datasets/catalog.json` | Summary counts by category/month |
| `data/processed/vector_store/` | FAISS index + metadata pickle |

---

## Architecture Notes & Trade-offs

### Scraper design
- **Incremental**: Uses SHA-256 fingerprinting of page content to skip unchanged pages
- **Polite**: Respects `robots.txt`, configurable rate limit (default 1 req/sec), exponential backoff
- **Resilient**: Multiple CSS selector fallbacks for MoSPI's Drupal layout; clean error logging
- **Trade-off**: BeautifulSoup works for server-rendered pages; if MoSPI migrates to React/SPA, switch to Playwright

### ETL
- **Chunking**: Simple whitespace tokeniser is fast and reproducible. For production, use `tiktoken` for exact token counts aligned with the embedding model
- **Validation**: Custom validator is lightweight; Great Expectations would add richer profiling but ~10× more setup time
- **Parquet**: Column-oriented format makes downstream analytics fast; Polars could replace Pandas for 10× speed on large corpora

### RAG
- **FAISS `IndexFlatIP`**: Exact inner-product search on normalised embeddings = cosine similarity. Scales to ~1M vectors on CPU; switch to `IndexIVFFlat` for >1M
- **Ollama**: Zero-config local LLM serving; downside is first-start model download (~4 GB)
- **Prompt**: Strict "answer from context only" prevents hallucination but may frustrate users for out-of-corpus questions

### Known Limitations
- MoSPI's website layout can change; CSS selectors may need updating
- LLaMA 3 responses can be slow on CPU (5–30s); GPU recommended for production
- No authentication/rate-limiting on the API (add OAuth2 for production)
- Embedding model (`all-MiniLM-L6-v2`) is English-optimised; Hindi/multilingual content may need `paraphrase-multilingual-MiniLM-L12-v2`

### Future Improvements
- Airflow/Prefect DAG for scheduled incremental crawls
- Embedding cache to avoid re-encoding unchanged chunks
- MMR (Maximal Marginal Relevance) retrieval to reduce redundant context
- Cross-encoder re-ranker for higher precision
- Grafana dashboard for scrape metrics (docs/hour, error rates)
- Great Expectations data docs for automated data quality reports

---

## Project Structure

```
.
├── README.md
├── Makefile
├── docker-compose.yml
├── .env.example
├── pyproject.toml
├── requirements.txt
├── scraper/
│   ├── __init__.py
│   ├── config.py       # Pydantic-settings configuration
│   ├── models.py       # Data models (Document, Chunk, Citation…)
│   ├── logger.py       # Structured JSON logger
│   ├── db.py           # SQLite CRUD layer
│   ├── crawl.py        # Web crawler (CLI: python -m scraper.crawl)
│   ├── parse.py        # PDF downloader + extractor
│   ├── report.py       # Run summary CLI
│   └── tests/
│       ├── conftest.py
│       ├── test_unit.py
│       └── test_integration.py
├── pipeline/
│   ├── __init__.py
│   ├── validate.py     # Data quality checks
│   ├── chunker.py      # Text chunking with overlap
│   └── run.py          # ETL orchestrator (CLI: python -m pipeline.run)
├── rag/
│   ├── __init__.py
│   ├── retriever.py    # FAISS vector store build + query
│   ├── prompt.py       # LLaMA prompt templates
│   ├── api.py          # FastAPI (POST /ask, POST /ingest, GET /health)
│   └── ui/
│       └── app.py      # Streamlit chatbot UI
├── infra/
│   ├── Dockerfile.scraper
│   ├── Dockerfile.api
│   └── Dockerfile.ui
└── data/
    ├── raw/
    │   └── pdf/
    └── processed/
        ├── chunks.parquet
        ├── datasets/catalog.json
        └── vector_store/
```

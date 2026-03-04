.PHONY: help install crawl parse etl index up down test lint

help:
	@echo ""
	@echo "MoSPI Scraper + LLaMA RAG — available commands"
	@echo "────────────────────────────────────────────────"
	@echo "  make install   Install Python dependencies"
	@echo "  make crawl     Run the web scraper"
	@echo "  make parse     Download PDFs & extract text/tables"
	@echo "  make etl       Run full ETL pipeline (validate + chunk + export)"
	@echo "  make index     Build FAISS vector index"
	@echo "  make up        Start all Docker services (API + UI + Ollama)"
	@echo "  make down      Stop all Docker services"
	@echo "  make test      Run all tests"
	@echo "  make lint      Run black + isort + mypy"
	@echo ""

install:
	pip install -r requirements.txt

crawl:
	python -m scraper.crawl

parse:
	python -m scraper.parse

report:
	python -m scraper.report

etl:
	python -m pipeline.run

index:
	python -m rag.retriever --build

# Full pipeline from scratch
all: crawl parse etl index

up:
	docker compose up --build api ui ollama

up-full:
	docker compose --profile scraper --profile pipeline up --build

down:
	docker compose down

test:
	pytest scraper/tests/ pipeline/tests/ rag/tests/ -v --tb=short

lint:
	black scraper/ pipeline/ rag/ --check
	isort scraper/ pipeline/ rag/ --check-only
	mypy scraper/ pipeline/ rag/ --ignore-missing-imports

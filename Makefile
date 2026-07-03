.PHONY: install check-ruby install-yt-dlp install-mutagen bundle help

install: check-ruby install-yt-dlp install-mutagen bundle
	@echo "\nAmbiente pronto."

help:
	@echo "Targets disponíveis:"
	@echo "  make install          - instala todas as dependências (Ruby, yt-dlp, mutagen, gems)"
	@echo "  make check-ruby       - verifica se a versão do Ruby bate com .ruby-version"
	@echo "  make install-yt-dlp   - instala o yt-dlp, se ainda não estiver disponível"
	@echo "  make install-mutagen  - instala o mutagen (Python), se ainda não estiver disponível"
	@echo "  make bundle           - instala as gems do projeto (bundle install)"

check-ruby:
	@required=$$(cat .ruby-version); \
	current=$$(ruby -e 'print RUBY_VERSION' 2>/dev/null); \
	if [ -z "$$current" ]; then \
		echo "Ruby não encontrado. Instale o Ruby $$required (veja https://www.ruby-lang.org/en/documentation/installation/ ou use rbenv/asdf/rvm)."; \
		exit 1; \
	elif [ "$$current" != "$$required" ]; then \
		echo "Versão do Ruby incompatível: encontrado $$current, esperado $$required (.ruby-version)."; \
		echo "Instale a versão correta (rbenv install $$required / asdf install ruby $$required)."; \
		exit 1; \
	else \
		echo "Ruby $$current ok."; \
	fi

install-yt-dlp:
	@if command -v yt-dlp >/dev/null 2>&1; then \
		echo "yt-dlp já instalado."; \
	elif [ "$$(uname -s)" = "Darwin" ] && command -v brew >/dev/null 2>&1; then \
		echo "Instalando yt-dlp via Homebrew..."; \
		brew install yt-dlp; \
	elif [ "$$(uname -s)" = "Linux" ] && command -v apt-get >/dev/null 2>&1; then \
		echo "Instalando yt-dlp via apt..."; \
		sudo apt-get update && sudo apt-get install -y yt-dlp; \
	else \
		echo "Não foi possível instalar o yt-dlp automaticamente neste sistema."; \
		echo "Instale manualmente: https://github.com/yt-dlp/yt-dlp#installation"; \
		exit 1; \
	fi

install-mutagen:
	@if python3 -c "import mutagen" >/dev/null 2>&1; then \
		echo "mutagen já instalado."; \
	elif command -v pip3 >/dev/null 2>&1; then \
		echo "Instalando mutagen via pip3..."; \
		pip3 install --user mutagen; \
	else \
		echo "python3/pip3 não encontrados. Instale o Python 3 primeiro: https://www.python.org/downloads/"; \
		exit 1; \
	fi

bundle:
	@echo "Instalando gems do projeto..."
	@bundle install

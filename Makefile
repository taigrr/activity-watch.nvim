.PHONY: test lint format check

test:
	nvim --headless -u tests/minimal_init.lua -c "PlenaryBustedDirectory tests/ { minimal_init = 'tests/minimal_init.lua' }"

lint: format
	@echo "Linting complete"

format:
	stylua lua/ plugin/ tests/

check:
	stylua --check lua/ plugin/ tests/
